const std = @import("std");
const builtin = @import("builtin");

const win32 = @import("win32/win32.zig");

const DynLib = @This();

const Inner = switch (builtin.os.tag) {
    .windows => struct {
        const Error = error{ FileNotFound, BadFormat, AccessDenied, DLLInitFailed, ModNotFound } ||
            std.Io.UnexpectedError ||
            std.fmt.BufPrintError;

        handle: win32.HMODULE,

        pub fn open(path: []const u8) Error!Inner {
            var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
            const path_z = try std.fmt.bufPrintSentinel(&path_buf, "{s}", .{path}, 0);

            if (win32.LoadLibraryA(path_z)) |handle| {
                return .{ .handle = handle };
            } else {
                const err = std.os.windows.GetLastError();
                switch (err) {
                    .FILE_NOT_FOUND => return error.FileNotFound,
                    .BAD_FORMAT => return error.BadFormat,
                    .ACCESS_DENIED => return error.AccessDenied,
                    .DLL_INIT_FAILED => return error.DLLInitFailed,
                    .MOD_NOT_FOUND => return error.ModNotFound,
                    else => return std.os.windows.unexpectedError(err),
                }
            }
        }

        pub fn close(this: *Inner) void {
            _ = win32.FreeLibrary(this.handle);
        }

        pub fn lookup(this: *Inner, comptime T: type, name: [:0]const u8) ?T {
            if (win32.GetProcAddress(this.handle, name)) |ptr| {
                return @ptrCast(ptr);
            }
            return null;
        }
    },
    else => std.DynLib,
};

inner: Inner,

pub fn open(path: []const u8) Inner.Error!DynLib {
    return .{ .inner = try Inner.open(path) };
}

pub fn close(this: *DynLib) void {
    this.inner.close();
}

pub fn lookup(this: *DynLib, comptime T: type, name: [:0]const u8) ?T {
    return this.inner.lookup(T, name);
}
