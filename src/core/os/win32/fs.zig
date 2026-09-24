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
    _ = dir;
    _ = path;
    unreachable;
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
