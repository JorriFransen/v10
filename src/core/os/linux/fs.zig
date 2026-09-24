const std = @import("std");

const fs = @import("../../fs.zig");
const linux = @import("linux.zig");
const mem = @import("../../mem/mem.zig");

pub const Handle = linux.fd_t;

pub const path_sep = '/';
pub const path_sep_str = "/";
pub const max_path_bytes = linux.PATH_MAX;
pub const max_name_bytes = linux.NAME_MAX;

const S = linux.S;

pub const Permissions = enum(linux.mode_t) {
    default_file = S.IRUSR | S.IWUSR | S.IRGRP | S.IWGRP | S.IROTH | S.IWOTH,
    default_dir = S.IRWXU | S.IRWXG | S.IRWXO,
    _,

    pub fn readOnly(this: Permissions) Permissions {
        var result: linux.mode_t = this;
        result &= ~(S.IWUSR | S.IWGRP | S.IWOTH);
        return @enumFromInt(result);
    }
};

pub inline fn isSep(char: u8) bool {
    return char == path_sep;
}

pub fn close(handle: Handle) void {
    linux.close(handle);
}

pub fn cwd() fs.Dir {
    return .{ .handle = linux.AT.FDCWD };
}

pub fn existsAt(dir: fs.Dir, path: [:0]const u8) fs.ExistsAtError!bool {
    const result = linux.faccessat(dir.handle, path, .F_OK) catch |e| switch (e) {
        error.BADF => @panic("Invalid dir handle"),
        error.FAULT => @panic("Invalid path pointer"),
        error.INVAL, error.ROFS, error.TXTBSY => unreachable,

        error.ACCES => return error.AccessDenied,
        error.PERM => return error.PermissionDenied,
        error.IO => return error.IO, // What does std do?
        error.LOOP => return error.TooManySymLinks,
        error.NAMETOOLONG => return error.NameTooLong,
        error.NOMEM => return error.OutOfMemory,

        error.UnexpectedErrno => return error.Unexpected,
    };
    return result;
}

pub fn openDirAt(dir: fs.Dir, path: [:0]const u8, options: fs.OpenDirAtOptions) fs.OpenDirAtError!fs.Dir {
    const mode: linux.O = .{
        .DIRECTORY = true,
        .CLOEXEC = true,
        .PATH = !options.iterate,
        .NOFOLLOW = !options.follow_symlinks,
    };

    const result = linux.openat(dir.handle, path, mode, 0) catch |e| switch (e) {
        error.BADF => @panic("Invalid dir handle"),
        error.FAULT => @panic("Invalid path pointer"),
        error.NODEV,
        error.FBIG,
        error.OVERFLOW,
        error.ISDIR,
        error.NXIO,
        error.OPNOTSUPP,
        error.ROFS,
        error.TXTBSY,
        error.WOULDBLOCK,
        => unreachable,

        error.INVAL => return error.BadPath,
        error.ACCES => return error.AccessDenied,
        error.PERM => return error.PermissionDenied,
        error.NOENT => return error.FileNotFound,
        error.BUSY => return error.DeviceBusy,
        error.DQUOT, error.NOSPC => return error.NoSpace,
        error.EXIST => return error.AlreadyExists,
        error.INTR => return error.Interrupted,
        error.LOOP => return error.TooManySymLinks,
        error.MFILE => return error.ProcessHandleQuotaExceeded,
        error.NAMETOOLONG => return error.NameTooLong,
        error.NFILE => return error.SystemHandleQuotaExceeded,
        error.NOMEM => return error.OutOfMemory,
        error.NOTDIR => return error.NotDir,

        else => return error.Unexpected,
    };

    return .{ .handle = result };
}

pub fn createDirAt(dir: fs.Dir, dir_name: [:0]const u8, options: fs.CreateDirAtOptions) fs.CreateDirAtError!void {
    linux.mkdirat(dir.handle, dir_name, @intFromEnum(options.permissions)) catch |e| switch (e) {
        error.BADF => @panic("Invalid dir handle"),
        error.FAULT => @panic("Invalid path pointer"),

        error.ACCES => return error.AccessDenied,
        error.PERM => return error.PermissionDenied,
        error.DQUOT, error.NOSPC => return error.NoSpace,
        error.EXIST => return error.AlreadyExists,
        error.INVAL => return error.BadPath,
        error.LOOP, error.MLINK => return error.TooManySymLinks,
        error.NAMETOOLONG => return error.NameTooLong,
        error.NOENT => return error.FileNotFound,
        error.NOMEM => return error.OutOfMemory,
        error.NOTDIR => return error.NotDir,
        error.ROFS => return error.ReadOnlyFileSystem,
        error.OVERFLOW => return error.MissingIdMapping,

        else => return error.Unexpected,
    };
}

pub const DirIterator = struct {
    fd: linux.dirfd_t,

    dents: []u8,
    buffer: [16 * (@sizeOf(linux.Dirent64) + linux.Dirent64.max_name_len)]u8 align(@alignOf(linux.Dirent64)),

    pub const Options = struct {
        reset_fd_pos: bool = true,
    };

    pub const Entry = struct {
        name: [:0]const u8,
        type: Type,

        pub const Type = enum {
            unknown,
            pipe,
            char,
            dir,
            block,
            file,
            link,
            socket,
            whiteout,
        };
    };

    pub const Error = fs.DirIteratorError;
    pub const InitError = fs.DirIteratorInitError;
    pub const NextError = fs.DirIteratorNextError;

    pub fn init(dir_fd: linux.dirfd_t, options: Options) InitError!DirIterator {
        if (options.reset_fd_pos) {
            _ = linux.lseek(dir_fd, 0, .SET) catch |e| switch (e) {
                error.BADF => return error.InvalidHandle,
                else => return error.SeekFailed,
            };
        }

        return .{
            .fd = dir_fd,
            .dents = &.{},
            .buffer = undefined,
        };
    }

    pub fn next(this: *DirIterator) NextError!?Entry {
        if (this.dents.len == 0) {
            const new_len = linux.getdents64(this.fd, &this.buffer) catch |e| switch (e) {
                error.BADF,
                error.NOENT,
                error.NOTDIR,
                error.IO,
                => return error.InvalidHandle,

                error.FAULT,
                error.INVAL,
                => unreachable,

                error.UnexpectedErrno => return error.Unexpected,
            };

            this.dents = this.buffer[0..new_len];
        }

        if (this.dents.len >= @sizeOf(linux.Dirent64)) {
            const dent: *linux.Dirent64 = @ptrCast(@alignCast(this.dents.ptr));

            if (dent.d_reclen == 0) return error.MalformedDirEntry;

            this.dents = this.dents[dent.d_reclen..];

            const name_len = dent.d_reclen - @offsetOf(linux.Dirent64, "d_name");
            const name_slice = @as([*]const u8, @ptrCast(&dent.d_name))[0..name_len];
            const name = mem.sliceToSentinel(name_slice, 0);

            return .{
                .name = name,
                .type = switch (dent.d_type) {
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
            };
        } else if (this.dents.len != 0) {
            return error.MalformedDirEntry;
        }

        return null;
    }
};
