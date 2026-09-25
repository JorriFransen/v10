const std = @import("std");

const fs = @import("../../fs.zig");
const win32 = @import("win32.zig");

pub const Handle = win32.HANDLE;

pub const path_sep = '\\';
pub const path_sep_str = "\\";

pub const max_path_bytes = win32.PATH_MAX_WIDE;
pub const max_name_bytes = 255;

pub const Permissions = enum(u32) {
    default_file,
    default_dir,
    _,

    pub fn readOnly(this: Permissions) Permissions {
        _ = this;
        unreachable;
    }
};

pub inline fn isSep(char: u8) bool {
    return char == '\\' or char == '/';
}

pub inline fn cwd() fs.Dir {
    return .{ .handle = std.os.windows.peb().ProcessParameters.CurrentDirectory.Handle };
}

pub fn existsAt(dir: fs.Dir, path: [:0]const u8) fs.ExistsAtError!bool {
    if (path.len == 0) return error.BadPath;

    const path_root_end = parsePathRoot(path);
    const absolute = path_root_end != 0;

    var wide_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
    const wide_len = win32.MultiByteToWideChar(.UTF8, .{ .ERR_INVALID_CHARS = true }, path.ptr, -1, @ptrCast(&wide_buf), wide_buf.len + 1);
    if (wide_len == 0) {
        switch (win32.GetLastError()) {
            .INVALID_FLAGS, .INVALID_PARAMETER => unreachable,
            .INSUFFICIENT_BUFFER => return error.NameTooLong,
            .NO_UNICODE_TRANSLATION => return error.BadPath,
            else => return error.Unexpected,
        }
    }

    const char_count: usize = @intCast(wide_len - 1);

    for (wide_buf[0..char_count]) |*codepoint| {
        if (codepoint.* == '/') codepoint.* = '\\';
    }

    var object_attributes: win32.NT_OBJECT_ATTRIBUTES = undefined;

    const name: win32.NT_UNICODE_STRING = .{
        .length = @intCast(char_count * @sizeOf(u16)),
        .maximum_length = @intCast(wide_len * @sizeOf(u16)),
        .buffer = wide_buf[0..char_count :0],
    };

    var nt_name: win32.NT_UNICODE_STRING = undefined;
    if (absolute) {
        switch (win32.RtlDosPathNameToNtPathName_U_WithStatus(name.buffer, &nt_name, null, null)) {
            .SUCCESS => {},
            .OBJECT_NAME_INVALID => return error.BadPath,
            .NO_MEMORY => return error.OutOfMemory,
            .ACCESS_DENIED => return error.AccessDenied,
            else => return error.Unexpected,
        }
        object_attributes.init(&nt_name, .{ .CASE_INSENSITIVE = true }, null, null);
    } else {
        object_attributes.init(&name, .{ .CASE_INSENSITIVE = true }, dir.handle, null);
    }
    defer if (absolute) win32.RtlFreeUnicodeString(&nt_name);

    var out_info: win32.NT_FILE_BASIC_INFORMATION = undefined;
    switch (win32.NtQueryAttributesFile(&object_attributes, &out_info)) {
        .SUCCESS => return true,
        .OBJECT_NAME_NOT_FOUND, .OBJECT_PATH_NOT_FOUND => return false,
        .ACCESS_DENIED => return error.AccessDenied,
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

/// Returns the length of the root prefix
pub fn parsePathRoot(path: []const u8) usize {
    if (path.len == 0) return 0;

    if (isSep(path[0])) {
        if (path.len < 2 or !isSep(path[1]))
            return 1 // \x
        else if (path.len > 2 and (path[2] == '.' or path[2] == '?')) // \\. or \\?
            if (path.len == 3) return 3 // exactly \\. or \\?
            else if (isSep(path[3])) return 4; // \\.\x or \\?\x

        // unc absolute
        // \\x
        const server_end = std.mem.findAnyPos(u8, path, 2, "/\\") orelse return 2;
        var it = std.mem.tokenizeAny(u8, path[server_end + 1 ..], "/\\");

        // There might be multiple separators between server and share
        const share = it.next() orelse return server_end;

        const server = path[2..server_end];
        var len = 2 + (share.ptr - server.ptr) + share.len;
        if (path.len > len and isSep(path[len])) len += 1;

        return len;
    } else if (path.len < 2 or path[1] != ':')
        return 0 // x
    else if (path.len > 2 and isSep(path[2]))
        return 3; // x:\

    return 2;
}
