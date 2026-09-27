const std = @import("std");

const fs = @import("../../fs.zig");
const win32 = @import("win32.zig");
const meta = @import("../../meta.zig");

pub const Handle = win32.HANDLE;

pub const path_sep = '\\';
pub const path_sep_str = "\\";

/// Including null
pub const max_path_bytes = win32.PATH_MAX_WIDE * 3 + 1;
/// Not including null
pub const max_name_bytes = win32.NAME_MAX * 3;

pub const Permissions = enum(u32) {
    default_file,
    default_dir,
    _,

    pub fn readOnly(this: Permissions) Permissions {
        _ = this;
        unreachable;
    }
};

pub inline fn isSep(char: anytype) bool {
    meta.expectUnsigned(char);
    return char == '\\' or char == '/';
}

pub inline fn cwd() fs.Dir {
    return .{ .handle = std.os.windows.peb().ProcessParameters.CurrentDirectory.Handle };
}

pub fn existsAt(dir: fs.Dir, path: [:0]const u8) fs.ExistsAtError!bool {
    if (path.len == 0) return error.BadPath;
    if (path.len > win32.PATH_MAX_WIDE) return error.NameTooLong;

    const parsed_path = try parsePath(path);

    var wide_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
    var char_count = std.unicode.wtf8ToWtf16Le(&wide_buf, path) catch return error.BadPath;

    if (parsed_path.type != .verbatim) {
        while (char_count > 1 and isSep(wide_buf[char_count - 1])) {
            if (wide_buf[char_count - 2] == ':') break;
            char_count -= 1;
        }

        for (wide_buf[0..char_count]) |*codepoint| {
            if (codepoint.* == '/') codepoint.* = '\\';
        }
    }

    wide_buf[char_count] = 0;

    const name: win32.NT_UNICODE_STRING = .{
        .length = @intCast(char_count * @sizeOf(u16)),
        .maximum_length = @intCast((char_count + 1) * @sizeOf(u16)),
        .buffer = wide_buf[0..char_count :0],
    };

    var object_attributes: win32.NT_OBJECT_ATTRIBUTES = undefined;
    var nt_name: win32.NT_UNICODE_STRING = undefined;

    switch (parsed_path.type) {
        // In place prefix swap
        .local_device,
        .verbatim,
        // Resolve and prefix
        .rooted,
        .drive_relative,
        // Prefix only
        .unc,
        .drive_absolute,
        => {
            switch (win32.RtlDosPathNameToNtPathName_U_WithStatus(name.buffer, &nt_name, null, null)) {
                .SUCCESS => {},
                .OBJECT_NAME_INVALID => return error.BadPath,
                .NO_MEMORY => return error.OutOfMemory,
                .ACCESS_DENIED => return error.AccessDenied,
                else => return error.Unexpected,
            }
            object_attributes.init(&nt_name, .{ .CASE_INSENSITIVE = true }, null, null);
        },

        .relative => {
            object_attributes.init(&name, .{ .CASE_INSENSITIVE = true }, dir.handle, null);
        },
    }
    defer if (parsed_path.type != .relative) win32.RtlFreeUnicodeString(&nt_name);

    var out_info: win32.NT_FILE_BASIC_INFORMATION = undefined;
    switch (win32.NtQueryAttributesFile(&object_attributes, &out_info)) {
        .SUCCESS => return true,
        .OBJECT_NAME_NOT_FOUND, .OBJECT_PATH_NOT_FOUND => return false,
        .OBJECT_NAME_INVALID => return error.BadPath,
        .ACCESS_DENIED => return error.AccessDenied,
        .IO_REPARSE_TAG_NOT_HANDLED => return error.TooManySymLinks,
        else => return error.Unexpected,
    }
}

pub fn openDirAt(dir: fs.Dir, path: [:0]const u8, options: fs.OpenDirAtOptions) fs.OpenDirAtError!fs.Dir {
    _ = dir;
    _ = path;
    _ = options;
    unreachable;
}

pub fn createDirAt(dir: fs.Dir, dir_name: [:0]const u8, options: fs.CreateDirAtOptions) fs.CreateDirAtError!void {
    _ = dir;
    _ = dir_name;
    _ = options;
    unreachable;
}

pub const DirIterator = struct {
    pub const Options = fs.DirIteratorOptions;

    pub const Entry = fs.DirIteratorEntry;

    pub const Error = fs.DirIteratorError;
    pub const InitError = fs.DirIteratorInitError;
    pub const NextError = fs.DirIteratorNextError;

    pub fn init(dir: fs.Dir, options: Options) InitError!DirIterator {
        _ = dir;
        _ = options;
        unreachable;
    }

    pub fn next(this: *DirIterator) NextError!?Entry {
        _ = this;
        unreachable;
    }
};

pub const ParsedPath = struct {
    type: Type,
    root_end: usize,

    pub const Type = enum {
        relative,
        rooted,
        drive_absolute,
        drive_relative,
        unc,
        local_device,
        verbatim,
    };
};

pub fn parsePath(path: []const u8) error{BadPath}!ParsedPath {
    if (path.len == 0) return error.BadPath;

    if (isSep(path[0])) {
        if (path.len < 2 or !isSep(path[1]))
            if (path.len > 2 and path[2] == '?')
                return error.BadPath
            else
                return .{ .type = .rooted, .root_end = 1 } // \x
        else if (path.len > 2 and (path[2] == '.' or path[2] == '?')) // \\. or \\?
            if (path.len == 3) return error.BadPath // exactly \\. or \\?
            else if (isSep(path[3]))
                if (std.mem.findNone(u8, path[4..], "/\\") == null)
                    return error.BadPath
                else
                    return .{ .type = if (path[2] == '.') .local_device else .verbatim, .root_end = 4 }; // \\.\x or \\?\x

        // \\x
        const server_end = std.mem.findAnyPos(u8, path, 2, "/\\") orelse return error.BadPath;
        if (server_end == 2) return error.BadPath;
        var it = std.mem.tokenizeAny(u8, path[server_end + 1 ..], "/\\");

        // There might be multiple separators between server and share
        const share = it.next() orelse return error.BadPath;

        const server = path[2..server_end];
        var len = 2 + (share.ptr - server.ptr) + share.len;
        if (path.len > len and isSep(path[len])) len += 1;

        return .{ .type = .unc, .root_end = len };
    }

    const drive_len = std.unicode.utf8ByteSequenceLength(path[0]) catch return error.BadPath;
    // 4-byte sequences start at a codepoint that needs a surrogate pair, which
    // WTF-16 cannot express, so RtlDetermineDosPathNameType_U sees no colon at
    // index 1 and reports relative. Match that.
    if (drive_len > 3 or path.len <= drive_len or path[drive_len] != ':')
        return .{ .type = .relative, .root_end = 0 } // x
    else if (path.len > drive_len + 1 and isSep(path[drive_len + 1]))
        return .{ .type = .drive_absolute, .root_end = drive_len + 2 }; // x:\

    return .{ .type = .drive_relative, .root_end = drive_len + 1 };
}

test parsePath {
    const t = std.testing;

    const testParse = struct {
        pub fn testParse(path: []const u8, expected_type: ParsedPath.Type, expected_root: []const u8) !void {
            const parsed = try parsePath(path);

            try t.expectEqual(expected_type, parsed.type);
            try t.expectEqualStrings(expected_root, path[0..parsed.root_end]);
        }
    }.testParse;

    // relative — root_end is always 0
    try testParse("foo", .relative, "");
    try testParse("a/b\\c/", .relative, "");
    try testParse("C", .relative, "");
    try testParse(":", .relative, ""); // len 1, short-circuits
    try testParse(":\\foo", .relative, ""); // path[1] != ':'
    try testParse(".", .relative, "");
    try testParse("con.txt", .relative, ""); // reserved names not special-cased
    try testParse("\u{20AC}", .relative, ""); // no colon
    try testParse("\u{1F600}:\\foo", .relative, ""); // 4-byte lead
    try testParse("\xC3", .relative, ""); // truncated 2-byte lead
    try testParse("..", .relative, "");
    try testParse("../foo", .relative, "");
    try testParse("./foo", .relative, "");

    // rooted
    try testParse("\\", .rooted, "\\");
    try testParse("/", .rooted, "/");
    try testParse("\\foo", .rooted, "\\");
    try testParse("/foo", .rooted, "/");
    try testParse("\\foo\\bar", .rooted, "\\");
    try testParse("\\?x", .rooted, "\\"); // '?' illegal in a name, not validated
    try testParse("\\:", .rooted, "\\");
    try testParse("\\C:", .rooted, "\\");
    try testParse("\\C:\\", .rooted, "\\");
    try testParse("/C:/", .rooted, "/");
    try testParse("\\?", .rooted, "\\");
    try testParse("\\?\\", .rooted, "\\");
    try testParse("\\?\\abc", .rooted, "\\");

    // drive_relative
    try testParse("C:", .drive_relative, "C:");
    try testParse("C:foo", .drive_relative, "C:");
    try testParse("c:", .drive_relative, "c:");
    try testParse("c:foo", .drive_relative, "c:");
    try testParse("C:a\\b", .drive_relative, "C:");
    try testParse("C::", .drive_relative, "C:");
    try testParse("C::\\foo", .drive_relative, "C:");
    try testParse("\u{20AC}:", .drive_relative, "\u{20AC}:");
    try testParse("é:", .drive_relative, "é:");
    try testParse("é:foo", .drive_relative, "é:");
    try testParse("::", .drive_relative, "::");
    try testParse("1:", .drive_relative, "1:");
    try testParse("::foo", .drive_relative, "::");

    // drive_absolute
    try testParse("C:\\", .drive_absolute, "C:\\");
    try testParse("C:\\foo", .drive_absolute, "C:\\");
    try testParse("c:\\", .drive_absolute, "c:\\");
    try testParse("c:\\foo", .drive_absolute, "c:\\");
    try testParse("C:/", .drive_absolute, "C:/");
    try testParse("C:/foo", .drive_absolute, "C:/");
    try testParse("C://foo", .drive_absolute, "C:/");
    try testParse("1:\\foo", .drive_absolute, "1:\\");
    try testParse("?:\\foo", .drive_absolute, "?:\\");
    try testParse("\u{20AC}:\\", .drive_absolute, "\u{20AC}:\\");
    try testParse("\u{20AC}:\\foo", .drive_absolute, "\u{20AC}:\\");
    try testParse("\u{00E9}:\\foo", .drive_absolute, "\u{00E9}:\\");
    try testParse("::\\", .drive_absolute, "::\\");

    // unc — root includes exactly one trailing separator when present
    try testParse("\\\\server\\share", .unc, "\\\\server\\share");
    try testParse("\\\\server\\share\\", .unc, "\\\\server\\share\\");
    try testParse("\\\\server\\share\\foo", .unc, "\\\\server\\share\\");
    try testParse("\\\\server\\share\\\\foo", .unc, "\\\\server\\share\\");
    try testParse("\\\\server\\\\share", .unc, "\\\\server\\\\share");
    try testParse("\\\\server\\\\share\\foo", .unc, "\\\\server\\\\share\\");
    try testParse("//server/share", .unc, "//server/share");
    try testParse("//server/share/", .unc, "//server/share/");
    try testParse("//server/share/foo", .unc, "//server/share/");
    try testParse("//server//share", .unc, "//server//share");
    try testParse("\\\\server\\sharefoo", .unc, "\\\\server\\sharefoo");
    try testParse("\\\\server\\share\\..\\foo", .unc, "\\\\server\\share\\");
    try testParse("\\\\srv\\\u{20AC}\\foo", .unc, "\\\\srv\\\u{20AC}\\");
    try testParse("\\\\?x\\y", .unc, "\\\\?x\\y"); // server named "?x"
    try testParse("\\\\127.0.0.1\\c$\\", .unc, "\\\\127.0.0.1\\c$\\");
    try testParse("\\\\127.0.0.1\\c$\\foo", .unc, "\\\\127.0.0.1\\c$\\");
    try testParse("\\\\??\\C:\\", .unc, "\\\\??\\C:\\");

    // local_device
    try testParse("\\\\.\\foo", .local_device, "\\\\.\\");
    try testParse("\\\\./foo", .local_device, "\\\\./");
    try testParse("\\\\.//foo", .local_device, "\\\\./");
    try testParse("\\\\.\\Volume{GUID}\\", .local_device, "\\\\.\\");
    try testParse("\\\\.\\unix\\path", .local_device, "\\\\.\\");
    try testParse("\\\\.\\C:\\", .local_device, "\\\\.\\");
    try testParse("\\\\.\\UNC\\server\\share\\", .local_device, "\\\\.\\");
    try testParse("//./foo", .local_device, "//./");
    try testParse("\\\\.\\.", .local_device, "\\\\.\\");

    // verbatim
    try testParse("\\\\?\\C:\\foo", .verbatim, "\\\\?\\");
    try testParse("\\\\?/C:\\foo", .verbatim, "\\\\?/");
    try testParse("\\\\?\\\\foo", .verbatim, "\\\\?\\");
    try testParse("\\\\?\\UNC\\server\\share", .verbatim, "\\\\?\\");
    try testParse("\\\\?\\Volume{X}\\", .verbatim, "\\\\?\\");
    try testParse("\\\\?\\GLOBALROOT\\", .verbatim, "\\\\?\\");
    try testParse("//?/foo", .verbatim, "//?/");
    try testParse("\\\\?\\.", .verbatim, "\\\\?\\");

    try t.expectError(error.BadPath, parsePath(""));
    try t.expectError(error.BadPath, parsePath("//"));
    try t.expectError(error.BadPath, parsePath("\\/"));
    try t.expectError(error.BadPath, parsePath("/\\"));
    try t.expectError(error.BadPath, parsePath("///"));
    try t.expectError(error.BadPath, parsePath("\\\\\\"));
    try t.expectError(error.BadPath, parsePath("\\\\.")); // bare prefix
    try t.expectError(error.BadPath, parsePath("\\\\?"));
    try t.expectError(error.BadPath, parsePath("//?"));
    try t.expectError(error.BadPath, parsePath("//?/"));
    try t.expectError(error.BadPath, parsePath("\\\\?\\")); // separators only after prefix
    try t.expectError(error.BadPath, parsePath("//."));
    try t.expectError(error.BadPath, parsePath("//./"));
    try t.expectError(error.BadPath, parsePath("\\\\.\\"));
    try t.expectError(error.BadPath, parsePath("\\\\?////"));
    try t.expectError(error.BadPath, parsePath("\\\\.\\/\\"));
    try t.expectError(error.BadPath, parsePath("\\\\")); // no server
    try t.expectError(error.BadPath, parsePath("\\\\server")); // no share
    try t.expectError(error.BadPath, parsePath("\\\\server\\"));
    try t.expectError(error.BadPath, parsePath("\\\\server\\\\")); // empty server
    try t.expectError(error.BadPath, parsePath("\\\\\\foo")); // empty server
    try t.expectError(error.BadPath, parsePath("////foo")); // empty server
    try t.expectError(error.BadPath, parsePath("\\\\.x")); // '.' without separator is a server name, and has none
    try t.expectError(error.BadPath, parsePath("\\??"));
    try t.expectError(error.BadPath, parsePath("\\\\??"));
    try t.expectError(error.BadPath, parsePath("\\\\??\\"));
    try t.expectError(error.BadPath, parsePath("\\??\\C:\\foo")); // NT path
    try t.expectError(error.BadPath, parsePath("/??/C:/foo")); // NT path
    try t.expectError(error.BadPath, parsePath("\\??x\\y"));
    try t.expectError(error.BadPath, parsePath("\x80foo")); // invalid UTF-8 lead bytes
    try t.expectError(error.BadPath, parsePath("\xBF"));
    try t.expectError(error.BadPath, parsePath("\xF8"));
    try t.expectError(error.BadPath, parsePath("\xFF"));
}
