const std = @import("std");
const log = std.log.scoped(.@"wayland-core");

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

pub fn load(lib: *std.DynLib) !void {
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

pub const DispatcherFunc = *const fn (user_data: *const anyopaque, target: *anyopaque, opcode: u32, message: *Message, args: [*]Argument) callconv(.c) c_int;
pub const LogFunc = *const fn (fmt: [*]const u8, args: *anyopaque) callconv(.c) void;

pub var event_queue_destroy: *const fn (queue: *EventQueue) callconv(.c) void = undefined;
pub var proxy_marshal_flags: *const fn (proxy: *Proxy, opcode: u32, interface: *const Interface, version: u32, flags: u32, ...) callconv(.c) *Proxy = undefined;
pub var proxy_marshal_array_flags: *const fn (proxy: *Proxy, opcode: u32, interface: *const Interface, version: u32, flags: u32, args: ?[*]Argument) callconv(.c) *Proxy = undefined;
pub var proxy_marshal: *const fn (proxy: *Proxy, opcode: u32, ...) callconv(.c) void = undefined;
pub var proxy_marshal_array: *const fn (proxy: *Proxy, opcode: u32, args: ?[*]Argument) callconv(.c) void = undefined;
pub var proxy_create: *const fn (proxy: *Proxy, interface: *const Interface) callconv(.c) *Proxy = undefined;
pub var proxy_create_wrapper: *const fn (proxy: *anyopaque) callconv(.c) *anyopaque = undefined;
pub var proxy_wrapper_destroy: *const fn (proxy: *anyopaque) callconv(.c) void = undefined;
pub var proxy_marshal_constructor: *const fn (proxy: *Proxy, opcode: u32, interface: *const Interface, ...) callconv(.c) *Proxy = undefined;
pub var proxy_marshal_constructor_versioned: *const fn (proxy: *Proxy, opcode: u32, interface: *const Interface, version: u32, ...) callconv(.c) *Proxy = undefined;
pub var proxy_marshal_array_constructor: *const fn (proxy: *Proxy, opcode: u32, args: [*]Argument, interface: *const Interface) callconv(.c) ?*Proxy = undefined;
pub var proxy_marshal_array_constructor_versioned: *const fn (proxy: *Proxy, opcode: u32, args: [*]Argument, interface: *const Interface, version: u32) callconv(.c) *Proxy = undefined;
pub var proxy_destroy: *const fn (proxy: *Proxy) callconv(.c) void = undefined;
pub var proxy_add_listener: *const fn (proxy: *Proxy, implementation: **const fn () callconv(.c) void, data: ?*anyopaque) callconv(.c) void = undefined;
pub var proxy_get_listener: *const fn (proxy: *Proxy) callconv(.c) ?*anyopaque = undefined;
pub var proxy_add_dispatcher: *const fn (proxy: *Proxy, dispatcher_func: DispatcherFunc, dispatcher_data: *const anyopaque, data: *anyopaque) callconv(.c) c_int = undefined;
pub var proxy_set_user_data: *const fn (proxy: *Proxy, user_data: *anyopaque) callconv(.c) void = undefined;
pub var proxy_get_user_data: *const fn (proxy: *Proxy) callconv(.c) *anyopaque = undefined;
pub var proxy_get_version: *const fn (proxy: *Proxy) callconv(.c) u32 = undefined;
pub var proxy_get_id: *const fn (proxy: *Proxy) callconv(.c) u32 = undefined;
pub var proxy_set_tag: *const fn (proxy: *Proxy, tag: ?[*]const ?[*]const u8) callconv(.c) void = undefined;
pub var proxy_get_class: *const fn (proxy: *Proxy) callconv(.c) ?[*]const u8 = undefined;
pub var proxy_get_display: *const fn (proxy: *Proxy) callconv(.c) ?*Display = undefined;
pub var proxy_set_queue: *const fn (proxy: *Proxy, queue: *EventQueue) callconv(.c) void = undefined;
pub var proxy_get_queue: *const fn (proxy: *Proxy) callconv(.c) ?*EventQueue = undefined;
pub var event_queue_get_name: *const fn (queue: *const EventQueue) callconv(.c) ?[*]const u8 = undefined;
pub var display_connect: *const fn (name: ?[*]u8) callconv(.c) ?*Display = undefined;
pub var display_connect_to_fd: *const fn (fd: c_int) callconv(.c) ?*Display = undefined;
pub var display_disconnect: *const fn (display: *Display) callconv(.c) void = undefined;
pub var display_get_fd: *const fn (display: *Display) callconv(.c) c_int = undefined;
pub var display_dispatch: *const fn (display: *Display) callconv(.c) c_int = undefined;
pub var display_dispatch_queue: *const fn (display: *Display, queue: *EventQueue) callconv(.c) c_int = undefined;
pub var display_dispatch_timeout: *const fn (display: *Display, timeout: *const Timespec) callconv(.c) c_int = undefined;
pub var display_dispatch_queue_timeout: *const fn (display: *Display, queue: *EventQueue, timeout: *const Timespec) callconv(.c) c_int = undefined;
pub var display_dispatch_queue_pending: *const fn (display: *Display, queue: *EventQueue) callconv(.c) c_int = undefined;
pub var display_dispatch_pending: *const fn (display: *Display) callconv(.c) c_int = undefined;
pub var display_get_error: *const fn (display: *Display) callconv(.c) c_int = undefined;
pub var display_get_protocol_error: *const fn (display: *Display, interface: **const Interface, id: *u32) callconv(.c) u32 = undefined;
pub var display_flush: *const fn (display: *Display) callconv(.c) c_int = undefined;
pub var display_roundtrip_queue: *const fn (display: *Display, queue: *EventQueue) callconv(.c) c_int = undefined;
pub var display_roundtrip: *const fn (display: *Display) callconv(.c) c_int = undefined;
pub var display_create_queue: *const fn (display: *Display) callconv(.c) ?*EventQueue = undefined;
pub var display_create_queue_with_name: *const fn (display: *Display, name: [*:0]const u8) callconv(.c) ?*EventQueue = undefined;
pub var display_prepare_read_queue: *const fn (display: *Display, queue: *EventQueue) callconv(.c) c_int = undefined;
pub var display_prepare_read: *const fn (display: *Display) callconv(.c) c_int = undefined;
pub var display_cancel_read: *const fn (display: *Display) callconv(.c) void = undefined;
pub var display_read_events: *const fn (display: *Display) callconv(.c) c_int = undefined;
pub var log_set_handler_client: *const fn (handler: LogFunc) callconv(.c) void = undefined;
pub var display_set_max_buffer_size: *const fn (display: *Display, max_buffer_size: usize) callconv(.c) void = undefined;
