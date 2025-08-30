const std = @import("std");
const log = std.log.scoped(.@"wayland-protocol");
const wl = @import("wayland_client_core.zig");

pub const Buffer = opaque {};
pub const Callback = opaque {};
pub const Compositor = opaque {};
pub const DataDevice = opaque {};
pub const DataDeviceManager = opaque {};
pub const DataOffer = opaque {};
pub const DataSource = opaque {};
pub const Display = opaque {};
pub const Fixes = opaque {};
pub const Keyboard = opaque {};
pub const Output = opaque {};
pub const Pointer = opaque {};
pub const Region = opaque {};
pub const Registry = opaque {};
pub const Seat = opaque {};
pub const Shell = opaque {};
pub const ShellSurface = opaque {};
pub const Shm = opaque {};
pub const ShmPool = opaque {};
pub const Subcompositor = opaque {};
pub const Subsurface = opaque {};
pub const Surface = opaque {};
pub const Touch = opaque {};

pub const interface = struct {
    pub var registry: *wl.Interface = undefined;
    pub var callback: *wl.Interface = undefined;

    pub fn load(lib: *std.DynLib) !void {
        inline for (@typeInfo(@This()).@"struct".decls) |decl| {
            const decl_type = @TypeOf(@field(@This(), decl.name));
            if (decl_type == *wl.Interface) {
                if (lib.lookup(decl_type, "wl_" ++ decl.name ++ "_interface")) |sym| {
                    @field(interface, decl.name) = sym;
                } else {
                    log.err("Failed to load wayland symbol: wl_{s}", .{decl.name});
                    return error.SymbolLoadFailed;
                }
            }
        }
    }
};

pub const DISPLAY_ERROR_INVALID_OBJECT = 0;
pub const DISPLAY_ERROR_INVALID_METHOD = 1;
pub const DISPLAY_ERROR_NO_MEMORY = 2;
pub const DISPLAY_ERROR_IMPLEMENTATION = 3;

pub const DisplayListener = extern struct {
    @"error": ?*const fn (data: *anyopaque, display: *wl.Display, object_id: *anyopaque, code: u32, message: ?[*]const u8) callconv(.c) void,
    delete_id: ?*const fn (data: *anyopaque, display: *wl.Display, id: u32) callconv(.c) void,
};

pub inline fn display_add_listener(display: *wl.Display, listener: *const DisplayListener, data: *anyopaque) c_int {
    return wl.proxy_add_listener(@ptrCast(display), @ptrCast(@constCast(listener)), data);
}

pub const DISPLAY_SYNC = 0;
pub const DISPLAY_GET_REGISTRY = 1;
pub const DISPLAY_ERROR_SINCE_VERSION = 1;
pub const DISPLAY_DELETE_ID_SINCE_VERSION = 1;
pub const DISPLAY_SYNC_SINCE_VERSION = 1;
pub const DISPLAY_GET_REGISTRY_SINCE_VERSION = 1;

pub inline fn display_set_user_data(display: *wl.Display, user_data: *anyopaque) void {
    wl.proxy_set_user_data(@ptrCast(display), user_data);
}

pub inline fn display_get_user_data(display: *wl.Display) *anyopaque {
    return wl.proxy_get_user_data(@ptrCast(display));
}

pub inline fn display_get_version(display: *wl.Display) u32 {
    return wl.proxy_get_version(@ptrCast(display));
}

pub inline fn display_sync(display: *wl.Display) *Callback {
    const version = display_get_version(display);
    return @ptrCast(wl.proxy_marshal_flags(@ptrCast(display), DISPLAY_SYNC, interface.callback_interface, version, 0, null));
}

pub const RegistryListener = extern struct {
    global: ?*const fn (data: ?*anyopaque, registry: *wl.Registry, name: u32, interface: [*:0]const u8, version: u32) callconv(.c) void,
    global_remove: ?*const fn (registry: *wl.Registry, name: u32) callconv(.c) void,
};

pub inline fn get_registry(display: *wl.Display) ?*wl.Registry {
    const proxy: *wl.Proxy = @ptrCast(display);
    var args = [_]wl.Argument{
        .{ .o = null },
    };
    return @ptrCast(wl.proxy_marshal_array_constructor(proxy, 1, &args, interface.registry));
}

pub inline fn registry_destroy(registry: *wl.Registry) void {
    wl.proxy_destroy(@ptrCast(registry));
}

pub inline fn registry_add_listener(registry: *wl.Registry, listener: *const RegistryListener, data: ?*anyopaque) void {
    return wl.proxy_add_listener(@ptrCast(registry), @ptrCast(@constCast(listener)), data);
}
