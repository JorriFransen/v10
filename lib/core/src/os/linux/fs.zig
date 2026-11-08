const std = @import("std");

const fs = @import("../../fs.zig");
const linux = @import("linux.zig");
const mem = @import("../../mem/mem.zig");

const log = @import("../../log.zig").scoped(.@"core.fs.linux");

const debug = @import("../../debug.zig");
const assert = debug.assert;

pub const Handle = linux.fd_t;

pub const path_sep = '/';
pub const path_sep_str = "/";
/// including null
pub const max_input_path_bytes = linux.PATH_MAX;
/// including null
pub const max_output_path_bytes = linux.PATH_MAX;
/// not including null
pub const max_input_name_bytes = linux.NAME_MAX;
/// not including null
pub const max_output_name_bytes = linux.NAME_MAX;

const S = linux.S;

pub const Permissions = enum(linux.mode_t) {
    default_file = @bitCast(S.default_file),
    default_dir = @bitCast(S.default_dir),
    _,

    pub fn toS(this: Permissions) S {
        return @bitCast(@backingInt(this));
    }
};

pub inline fn isSep(char: u8) bool {
    return char == path_sep;
}

pub inline fn close(handle: Handle) void {
    linux.close(handle);
}

pub inline fn cwd() fs.Dir {
    return .{ .handle = linux.AT.FDCWD };
}

pub fn existsAt(dir: fs.Dir, sub_path: [:0]const u8) fs.ExistsAtError!bool {
    if (sub_path.len == 0) return false;

    const result = linux.faccessat(dir.handle, sub_path, .F_OK) catch |e| switch (e) {
        error.ACCES => return error.AccessDenied,
        error.PERM => return error.PermissionDenied,
        error.IO => return error.IO,
        error.LOOP => return error.SymLinkNotResolved,
        error.NAMETOOLONG => return error.NameTooLong,
        error.NOMEM => return error.OutOfMemory,

        else => return linux.unexpectedError(e),
    };
    return result;
}

pub fn fileTypeAt(dir: fs.Dir, sub_path: [:0]const u8, options: fs.FileTypeAtOptions) fs.FileTypeAtError!fs.FileType {
    if (sub_path.len == 0) return error.BadPath;

    var stat: linux.Statx = undefined;
    linux.statx(
        dir.handle,
        sub_path,
        .{ .SYMLINK_NOFOLLOW = !options.follow_symlinks },
        .{ .TYPE = true },
        &stat,
    ) catch |e| return switch (e) {
        error.ACCES => error.AccessDenied,
        error.NOENT => error.FileNotFound,
        error.NAMETOOLONG => error.NameTooLong,
        error.NOTDIR => error.NotDir,
        error.NOMEM => error.OutOfMemory,
        error.LOOP => error.SymLinkNotResolved,

        else => return linux.unexpectedError(e),
    };

    if (!stat.mask.TYPE) return debug.programmerError("statx type failed", .{}, null);

    const mode: linux.S = @fromBackingInt(stat.mode);

    return switch (mode.TYPE) {
        .FIFO => .pipe,
        .CHR => .char,
        .DIR => .dir,
        .BLK => .block,
        .REG => .file,
        .LNK => .link,
        .SOCK => .socket,

        else => return debug.programmerError("Invalid file type (int: {})", .{@backingInt(mode.TYPE)}, null),
    };
}

pub fn mTimeAt(dir: fs.Dir, sub_path: [:0]const u8, options: fs.MTimeAtOptions) fs.MTimeAtError!fs.Timestamp {
    if (sub_path.len == 0) return error.BadPath;

    var stat: linux.Statx = undefined;
    linux.statx(
        dir.handle,
        sub_path,
        .{ .SYMLINK_NOFOLLOW = !options.follow_symlinks },
        .{ .MTIME = true },
        &stat,
    ) catch |e| return switch (e) {
        error.ACCES => error.AccessDenied,
        error.NOENT => error.FileNotFound,
        error.NAMETOOLONG => error.NameTooLong,
        error.NOTDIR => error.NotDir,
        error.NOMEM => error.OutOfMemory,
        error.LOOP => error.SymLinkNotResolved,

        else => return linux.unexpectedError(e),
    };

    if (!stat.mask.MTIME) return debug.programmerError("statx mtime failed", .{}, null);

    const ns = stat.mtime.ns();
    return .fromNs(ns);
}

pub fn openDirAt(dir: fs.Dir, sub_path: [:0]const u8, options: fs.OpenDirAtOptions) fs.OpenDirAtError!fs.Dir {
    const mode: linux.O = .{
        .DIRECTORY = true,
        .CLOEXEC = true,
        .PATH = !options.iterate,
        .NOFOLLOW = !options.follow_symlinks,
    };

    const result = linux.openat(dir.handle, sub_path, mode, .{}) catch |e| switch (e) {
        error.INVAL => return error.BadPath,
        error.ACCES => return error.AccessDenied,
        error.PERM => return error.PermissionDenied,
        error.NOENT => return error.FileNotFound,
        error.BUSY => return error.DeviceBusy,
        error.DQUOT, error.NOSPC => return error.NoSpace,
        error.EXIST => return error.AlreadyExists,
        error.LOOP => return error.SymLinkNotResolved,
        error.MFILE => return error.ProcessHandleQuotaExceeded,
        error.NAMETOOLONG => return error.NameTooLong,
        error.NFILE => return error.SystemHandleQuotaExceeded,
        error.NOMEM => return error.OutOfMemory,
        error.NOTDIR => return error.NotDir,

        else => return linux.unexpectedError(e),
    };

    return .{ .handle = result };
}

pub fn createDirAt(dir: fs.Dir, sub_path: [:0]const u8, options: fs.CreateDirAtOptions) fs.CreateDirAtError!void {
    if (sub_path.len == 0) return error.BadPath;

    linux.mkdirat(dir.handle, sub_path, options.permissions.toS()) catch |e| switch (e) {
        error.ACCES => return error.AccessDenied,
        error.PERM => return error.PermissionDenied,
        error.DQUOT, error.NOSPC => return error.NoSpace,
        error.EXIST => return error.AlreadyExists,
        error.INVAL => return error.BadPath,
        error.LOOP => return error.SymLinkNotResolved,
        error.NAMETOOLONG => return error.NameTooLong,
        error.NOENT => return error.FileNotFound,
        error.NOMEM => return error.OutOfMemory,
        error.NOTDIR => return error.NotDir,
        error.ROFS => return error.ReadOnlyFileSystem,
        error.OVERFLOW => return error.MissingIdMapping,

        else => return linux.unexpectedError(e),
    };
}

pub const DirIteratorImpl = struct {
    comptime {
        assert(@hasField(linux.Dirent64, "d_name"));
    }
    pub const entry_header_size = @offsetOf(linux.Dirent64, "d_name");
    pub const min_buffer_size = std.mem.alignForward(usize, entry_header_size + linux.Dirent64.max_name_len, @alignOf(linux.Dirent64));
    pub const default_buffer_size = 8 * min_buffer_size;

    const Options = fs.DirIteratorUnmanaged.Options;
    const Entry = fs.DirIteratorUnmanaged.Entry;

    const Error = fs.DirIteratorUnmanaged.Error;

    pub fn next(it: *fs.DirIteratorUnmanaged, buffer: []align(@alignOf(usize)) u8) Error!?Entry {
        state: switch (it.state) {
            .done => return null,

            .reset => {
                _ = linux.lseek(it.dir.handle, 0, .SET) catch return error.InvalidHandle;
                it.buffer_used = 0;
                it.buffer_offset = 0;
                it.state = .iterating;
                continue :state .iterating;
            },

            .iterating => {
                while (true) {
                    while ((it.buffer_used - it.buffer_offset) >= @sizeOf(linux.Dirent64)) {
                        const entry: *linux.Dirent64 = @ptrCast(@alignCast(buffer.ptr + it.buffer_offset));

                        if (entry.d_reclen == 0) return error.MalformedDirEntry;
                        if (entry.d_reclen > it.buffer_used - it.buffer_offset) return error.MalformedDirEntry;

                        it.buffer_offset += entry.d_reclen;

                        const name_len = entry.d_reclen - entry_header_size;
                        const name_slice = @as([*]const u8, @ptrCast(&entry.d_name))[0..name_len];
                        const name = mem.sliceToSentinel(name_slice, 0);

                        switch (name.len) {
                            0 => return error.MalformedDirEntry,
                            1 => if (name[0] == '.') continue,
                            2 => if (name[0] == '.' and name[1] == '.') continue,
                            else => {},
                        }

                        const file_type = switch (entry.d_type) {
                            .UNKNOWN => fileTypeAt(it.dir, name, .{ .follow_symlinks = false }) catch .unknown,
                            .FIFO => .pipe,
                            .CHR => .char,
                            .DIR => .dir,
                            .BLK => .block,
                            .REG => .file,
                            .LNK => .link,
                            .SOCK => .socket,
                            .WHT => .whiteout,
                        };

                        return .{ .name = name, .type = file_type };
                    } else {
                        if (it.buffer_offset != it.buffer_used) return error.MalformedDirEntry;

                        it.buffer_used = 0;
                        it.buffer_offset = 0;
                    }

                    it.buffer_used = linux.getdents64(it.dir.handle, buffer) catch |e| switch (e) {
                        error.BADF,
                        error.NOENT,
                        error.NOTDIR,
                        error.IO,
                        => return error.InvalidHandle,

                        error.FAULT => return debug.programmerError("Invalid pointer", .{}, null),
                        error.INVAL => return debug.programmerError("Result buffer too small", .{}, null),
                        error.UnexpectedErrno => return linux.unexpectedError(e),
                    };

                    if (it.buffer_used == 0) {
                        it.state = .done;
                        return null;
                    }
                }
            },
        }
    }
};
