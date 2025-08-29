const std = @import("std");
const log = std.log.scoped(.wayland);

pub const Object = opaque {};
pub const Timespec = opaque {};
pub const Proxy = opaque {};
pub const Display = opaque {};
pub const EventQueue = opaque {};
pub const Registry = opaque {};

pub const MARSHAL_FLAG_DESTROY = 1;
pub const MAX_MESSAGE_SIZE = 4096;

pub const Message = extern struct {
    name: [*:0]const u8,
    signature: [*:0]const u8,
    types: ?[*]const ?*const Interface,
};

pub const Interface = extern struct {
    name: [*:0]const u8,
    version: c_int,
    method_count: c_int,
    methods: ?[*]const Message,
    event_count: c_int,
    events: ?[*]const Message,
};

pub const Fixed = enum(u32) {};

pub const Array = extern struct {
    size: usize,
    alloc: usize,
    data: *anyopaque,
};

pub const Argument = extern union {
    i: i32,
    u: u32,
    f: Fixed,
    s: ?[*]const u8,
    o: ?*Object,
    n: u32,
    a: ?*Array,
    h: i32,
};

pub const RegistryListener = extern struct {
    global: ?*const fn (data: ?*anyopaque, registry: *Registry, name: u32, interface: [*:0]const u8, version: u32) callconv(.c) void,
    global_remove: ?*const fn (registry: *Registry, name: u32) callconv(.c) void,
};

pub fn load(lib: *std.DynLib) !void {

    // This relies on the fact the only function pointer declarations in this struct are the ones being loaded
    inline for (@typeInfo(@This()).@"struct".decls) |decl| {
        const decl_type = @TypeOf(@field(@This(), decl.name));
        const decl_type_info = @typeInfo(decl_type);
        if (decl_type_info == .pointer and @typeInfo(decl_type_info.pointer.child) == .@"fn") {
            if (lib.lookup(decl_type, "wl_" ++ decl.name)) |sym| {
                @field(@This(), decl.name) = sym;
            } else {
                log.err("Failed to load wayland symbol: wl_{s}", .{decl.name});
                return error.SymbolLoadFailed;
            }
        }
    }
}

pub var event_queue_destroy: *const fn (*EventQueue) callconv(.c) void = undefined;
pub var proxy_marshal_flags: *const fn (*Proxy, u32, *const Interface, u32, u32, ...) callconv(.c) *Proxy = undefined;

pub var display_connect: *const fn (?[*:0]u8) callconv(.c) ?*Display = undefined;
pub var display_disconnect: *const fn (*Display) callconv(.c) void = undefined;
pub var display_roundtrip: *const fn (*Display) callconv(.c) c_int = undefined;
pub var proxy_destroy: *const fn (*Proxy) callconv(.c) void = undefined;
pub var proxy_add_listener: *const fn (*Proxy, **const fn () callconv(.c) void, data: ?*anyopaque) callconv(.c) void = undefined;
pub var proxy_marshal_array_constructor: *const fn (*Proxy, u32, [*]Argument, *const Interface) callconv(.c) ?*Proxy = undefined;

pub inline fn get_registry(display: *Display) ?*Registry {
    const proxy: *Proxy = @ptrCast(display);
    var args = [_]Argument{
        .{ .o = null },
    };
    return @ptrCast(proxy_marshal_array_constructor(proxy, 1, &args, &registry_interface));
}

pub inline fn registry_destroy(registry: *Registry) void {
    proxy_destroy(@ptrCast(registry));
}

pub inline fn registry_add_listener(registry: *Registry, listener: *const RegistryListener, data: ?*anyopaque) void {
    return proxy_add_listener(@ptrCast(registry), @ptrCast(@constCast(listener)), data);
}

const registry_interface: Interface = .{
    .name = "wl_registry",
    .version = 1,
    .method_count = 1,
    .methods = &.{
        .{
            .name = "bind",
            .signature = "usun",
            .types = &.{
                null,
                null,
                null,
                null,
            },
        },
    },
    .event_count = 2,
    .events = &.{
        .{
            .name = "global",
            .signature = "usu",
            .types = &.{
                null,
                null,
                null,
            },
        },
        .{
            .name = "global_remove",
            .signature = "u",
            .types = &.{
                null,
            },
        },
    },
};
