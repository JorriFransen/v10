const std = @import("std");

const assert = @import("../../assert.zig").assert;
const fs = @import("../../fs.zig");
const meta = @import("../../meta.zig");
const win32 = @import("win32.zig");

pub const Handle = win32.HANDLE;

pub const path_sep = '\\';
pub const path_sep_str = "\\";

/// Including null
pub const max_path_bytes = win32.PATH_MAX_WIDE * 3 + 1;
/// Not including null
pub const max_name_bytes = win32.NAME_MAX * 3;

const nt_path_prefix: [4]u16 = .{ '\\', '?', '?', '\\' };

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
    var nt_path_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
    const nt_path = try toNtPath(dir, path, &nt_path_buf);

    std.log.debug("existAt final name: '{f}', dir_handle: {}", .{ std.unicode.fmtUtf16Le(nt_path.path), nt_path.root_handle != null });

    const final_nt_unicode_name = win32.NT_UNICODE_STRING.init(nt_path.path);
    const object_attributes: win32.NT_OBJECT_ATTRIBUTES = .init(&final_nt_unicode_name, .{ .CASE_INSENSITIVE = true }, nt_path.root_handle, null);

    var out_info: win32.NT_FILE_BASIC_INFORMATION = undefined;
    switch (win32.NtQueryAttributesFile(&object_attributes, &out_info)) {
        .SUCCESS => return true,
        .OBJECT_NAME_NOT_FOUND, .OBJECT_PATH_NOT_FOUND => return false,
        .OBJECT_NAME_INVALID => return error.BadPath,
        .ACCESS_DENIED => return error.AccessDenied,
        .IO_REPARSE_TAG_NOT_HANDLED => return error.TooManySymLinks,
        else => |e| {
            std.log.err("Unexpected NtQueryAttributesFile error: '{s}' ({})", .{ std.enums.tagName(win32.NTSTATUS, e) orelse "", @intFromEnum(e) });
            return error.Unexpected;
        },
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
                if (std.mem.findNone(u8, path[4..], "/\\") == null) {
                    return error.BadPath;
                } else {
                    if (path[0] == path_sep and path[1] == path_sep and path[2] == '?' and path[3] == path_sep) {
                        return .{ .type = .verbatim, .root_end = 4 }; // \\?\
                    }
                    return .{ .type = .local_device, .root_end = 4 }; // \\.\x
                };

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

const NtPath = struct {
    path: [:0]u16,
    root_handle: ?win32.HANDLE,
};

fn toNtPath(dir: fs.Dir, path: [:0]const u8, buf: [:0]u16) !NtPath {
    if (path.len > buf.len) return error.NameTooLong;
    const parsed_path = try parsePath(path);

    var name_len = std.unicode.wtf8ToWtf16Le(buf, path) catch return error.BadPath;

    if (parsed_path.type != .verbatim) {
        while (name_len > 1 and isSep(buf[name_len - 1])) {
            if (buf[name_len - 2] == ':') break;
            name_len -= 1;
        }
    }

    buf[name_len] = 0;
    var name: [:0]u16 = buf[0..name_len :0];

    var nt_name: win32.NT_UNICODE_STRING = undefined;
    var dir_handle: ?win32.HANDLE = null;

    switch (parsed_path.type) {
        // In place prefix swap
        .verbatim => {
            name[0..nt_path_prefix.len].* = nt_path_prefix;
        },
        .local_device,
        // Resolve and prefix
        .rooted,
        .drive_relative,
        // Prefix only
        .unc,
        .drive_absolute,
        => {
            switch (win32.RtlDosPathNameToNtPathName_U_WithStatus(name, &nt_name, null, null)) {
                .SUCCESS => {},
                .OBJECT_NAME_INVALID => return error.BadPath,
                .NO_MEMORY => return error.OutOfMemory,
                .ACCESS_DENIED => return error.AccessDenied,
                else => return error.Unexpected,
            }
            const nt_name_slice = nt_name.slice();
            if (buf.len < nt_name_slice.len + 1) return error.NameTooLong;
            @memcpy(buf[0 .. nt_name_slice.len + 1], nt_name_slice.ptr[0 .. nt_name_slice.len + 1]);
            name = buf[0..nt_name_slice.len :0];
        },

        .relative => {
            if (std.os.windows.normalizePath(u16, name)) |normalized_len| {
                name[normalized_len] = 0;
                name = name[0..normalized_len :0];
                dir_handle = dir.handle;
            } else |e| switch (e) {
                error.TooManyParentDirs => {
                    name = try relativeEscapingDirHandleNtPath(dir, path, buf);
                },
            }
        },
    }
    defer if (parsed_path.type != .relative) win32.RtlFreeUnicodeString(&nt_name);

    return .{ .path = name, .root_handle = dir_handle };
}

fn relativeEscapingDirHandleNtPath(dir: fs.Dir, path: [:0]const u8, dest: [:0]u16) ![:0]u16 {
    var buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;

    const dir_path_len = win32.GetFinalPathNameByHandleW(dir.handle, &buf, buf.len + 1, 0);
    if (dir_path_len == 0) {
        const err = win32.GetLastError();
        return switch (err) {
            .PATH_NOT_FOUND => error.BadPath,
            .NOT_ENOUGH_MEMORY => error.OutOfMemory,
            .ACCESS_DENIED => error.AccessDenied,
            .INVALID_PARAMETER => unreachable,
            else => error.Unexpected,
        };
    }
    if (dir_path_len > buf.len + 1) return error.NameTooLong;

    const dir_path = buf[0..dir_path_len];
    std.log.debug("dir path: '{f}'", .{std.unicode.fmtUtf16Le(dir_path)});

    if (dir_path_len + path.len + 1 > buf.len) return error.NameTooLong;

    buf[dir_path_len] = path_sep;

    const path_len = std.unicode.wtf8ToWtf16Le(buf[dir_path_len + 1 ..], path) catch return error.BadPath;
    const unresolved_len = dir_path_len + path_len + 1;
    buf[unresolved_len] = 0;
    const unresolved_name = buf[0..unresolved_len :0];
    std.log.debug("unresolved_name: '{f}'", .{std.unicode.fmtUtf16Le(unresolved_name)});

    const dest_len_bytes = dest.len * @sizeOf(u16);
    const result_len_bytes = win32.RtlGetFullPathName_U(unresolved_name, @intCast(dest_len_bytes), dest.ptr, null);
    if (result_len_bytes == 0) return error.BadPath;
    if (result_len_bytes > dest_len_bytes) return error.NameTooLong;

    dest[0..nt_path_prefix.len].* = nt_path_prefix;

    const result_len = result_len_bytes / @sizeOf(u16);

    return dest[0..result_len :0];
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
    try testParse("\\\\?/C:\\foo", .local_device, "\\\\?/");
    try testParse("//?/foo", .local_device, "//?/");

    // verbatim
    try testParse("\\\\?\\C:\\foo", .verbatim, "\\\\?\\");
    try testParse("\\\\?\\\\foo", .verbatim, "\\\\?\\");
    try testParse("\\\\?\\UNC\\server\\share", .verbatim, "\\\\?\\");
    try testParse("\\\\?\\Volume{X}\\", .verbatim, "\\\\?\\");
    try testParse("\\\\?\\GLOBALROOT\\", .verbatim, "\\\\?\\");
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
