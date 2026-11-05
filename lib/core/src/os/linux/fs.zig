const std = @import("std");

const debug = @import("../../debug.zig");
const fs = @import("../../fs.zig");
const linux = @import("linux.zig");
const mem = @import("../../mem/mem.zig");

pub const Handle = linux.fd_t;

pub const path_sep = '/';
pub const path_sep_str = "/";
/// including null
pub const max_input_path_bytes = linux.PATH_MAX;
/// including null
pub const max_output_path_bytes = linux.PATH_MAX;
/// not including null
pub const max_name_bytes = linux.NAME_MAX;

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
    pub const max_entry_size = std.mem.alignForward(usize, @sizeOf(linux.Dirent64) + linux.Dirent64.max_name_len, @alignOf(linux.Dirent64));

    const Options = fs.DirIterator.Options;
    const Entry = fs.DirIterator.Entry;

    const Error = fs.DirIterator.Error;
    const InitError = fs.DirIterator.InitError;
    const NextError = fs.DirIterator.NextError;

    pub fn init(it: *fs.DirIterator, dir: fs.Dir, options: Options) InitError!void {
        if (options.reset_handle_pos) {
            _ = linux.lseek(dir.handle, 0, .SET) catch |e| switch (e) {
                error.BADF => return error.InvalidHandle,
                else => return error.SeekFailed,
            };
        }

        it.* = .{
            .dir = dir,
            .entries = &.{},
            .buffer = undefined,
            .impl = .{},
        };
    }

    pub fn next(it: *fs.DirIterator) NextError!?Entry {
        if (it.entries.len == 0) {
            const new_len = linux.getdents64(it.dir.handle, &it.buffer) catch |e| switch (e) {
                error.BADF,
                error.NOENT,
                error.NOTDIR,
                error.IO,
                => return error.InvalidHandle,

                else => return linux.unexpectedError(e),
            };

            it.entries = it.buffer[0..new_len];
        }

        while (it.entries.len >= @sizeOf(linux.Dirent64)) {
            const entry: *linux.Dirent64 = @ptrCast(@alignCast(it.entries.ptr));

            if (entry.d_reclen == 0) return error.MalformedDirEntry;

            it.entries = it.entries[entry.d_reclen..];

            const name_len = entry.d_reclen - @offsetOf(linux.Dirent64, "d_name");
            const name_slice = @as([*]const u8, @ptrCast(&entry.d_name))[0..name_len];
            const name = mem.sliceToSentinel(name_slice, 0);

            switch (name.len) {
                0 => return error.MalformedDirEntry,

                1 => if (name[0] == '.') continue,
                2 => if (name[0] == '.' and name[1] == '.') continue,

                else => return .{
                    .name = name,
                    .type = switch (entry.d_type) {
                        .UNKNOWN => .unknown,
                        .FIFO => .pipe,
                        .CHR => .char,
                        .DIR => .dir,
                        .BLK => .block,
                        .REG => .file,
                        .LNK => .link,
                        .SOCK => .socket,
                        .WHT => .whiteout,
                    },
                },
            }
        } else if (it.entries.len != 0) {
            return error.MalformedDirEntry;
        }

        return null;
    }
};
