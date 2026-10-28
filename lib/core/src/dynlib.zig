const std = @import("std");

const os_tag = @import("builtin").target.os.tag;

const assert = @import("assert.zig").assert;
const fs = @import("fs.zig");
const win32 = @import("os/os.zig").win32;

const DynLib = @This();

const Inner = switch (os_tag) {
    .windows => struct {
        const Error = error{ FileNotFound, BadFormat, AccessDenied, DLLInitFailed, ModNotFound, InvalidWtf8, NameTooLong, Unexpected };

        handle: win32.HMODULE,

        pub fn open(path: [:0]const u8) Error!Inner {
            var dll_handle: win32.HANDLE = undefined;

            var wide_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
            const wide_len = std.unicode.calcWtf16LeLen(path) catch return error.InvalidWtf8;
            if (wide_len > wide_buf.len) return error.NameTooLong;
            const actual_wide_len = std.unicode.wtf8ToWtf16Le(&wide_buf, path) catch unreachable;
            assert(wide_len == actual_wide_len);
            wide_buf[wide_len] = 0;
            const wide_path = wide_buf[0..wide_len :0];

            const load_status = win32.NT.LdrLoadDll(null, null, &.init(wide_path), &dll_handle);
            switch (load_status) {
                .SUCCESS => return .{ .handle = dll_handle },
                .DLL_NOT_FOUND => return error.ModNotFound,
                .INVALID_IMAGE_FORMAT => return error.BadFormat,
                .ACCESS_DENIED => return error.AccessDenied,
                .DLL_INIT_FAILED => return error.DLLInitFailed,
                .OBJECT_NAME_NOT_FOUND => return error.FileNotFound,
                else => return error.Unexpected,
            }
        }

        pub fn close(this: *Inner) void {
            _ = win32.NT.LdrUnloadDll(this.handle);
        }

        pub fn lookup(this: *Inner, comptime T: type, name: [:0]const u8) ?T {
            var proc_addr: *anyopaque = undefined;
            if (win32.NT.LdrGetProcedureAddress(this.handle, &.init(name), 0, &proc_addr) == .SUCCESS) {
                return @ptrCast(proc_addr);
            }
            return null;
        }
    },
    else => std.DynLib,
};

inner: Inner,

pub fn open(path: [:0]const u8) Inner.Error!DynLib {
    return .{ .inner = try Inner.open(path) };
}

pub fn close(this: *DynLib) void {
    this.inner.close();
}

pub fn lookup(this: *DynLib, comptime T: type, name: [:0]const u8) ?T {
    return this.inner.lookup(T, name);
}
