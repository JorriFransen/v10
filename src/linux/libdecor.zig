const std = @import("std");
const log = std.log.scoped(.libdecor);
const wayland = @import("wayland");
const wl = wayland.wl;
const xdg_shell = wayland.xdg_shell;

const LibDecor = @This();

pub const Context = opaque {};
pub const Frame = opaque {};
pub const Configuration = opaque {};
pub const State = opaque {};

pub const Error = enum(c_int) {
    COMPOSITOR_INCOMPATIBLE = 0,
    INVALIC_FRAME_CONFIGURATION = 1,
};

pub const WindowState = enum(c_int) {
    NONE = 0,
    ACTIVE = 1 << 0,
    MAXIMIZED = 1 << 1,
    FULLSCREEN = 1 << 2,
    TILED_LEFT = 1 << 3,
    TILED_RIGHT = 1 << 4,
    TILED_TOP = 1 << 5,
    TILED_BOTTOM = 1 << 6,
    SUSPENDED = 1 << 7,
};

pub const ResizeEdge = enum(c_int) {
    NONE = 0,
    TOP = 1,
    BOTTOM = 2,
    LEFT = 3,
    TOP_LEFT = 4,
    BOTTOM_LEFT = 5,
    RIGHT = 6,
    TOP_RIGHT = 7,
    BOTTOM_RIGHT = 8,
};

pub const Capabilities = enum(c_int) {
    MOVE = 1 << 0,
    RESIZE = 1 << 1,
    MINIMIZE = 1 << 2,
    FULLSCREEN = 1 << 3,
    CLOSE = 1 << 4,
};

pub const Interface = extern struct {
    @"error": *const fn (context: *Context, err: Error, msg: ?[*:0]const u8) callconv(.c) void,

    reserved1: *const fn () callconv(.c) void = undefined,
    reserved2: *const fn () callconv(.c) void = undefined,
    reserved3: *const fn () callconv(.c) void = undefined,
    reserved4: *const fn () callconv(.c) void = undefined,
    reserved5: *const fn () callconv(.c) void = undefined,
    reserved6: *const fn () callconv(.c) void = undefined,
    reserved7: *const fn () callconv(.c) void = undefined,
    reserved8: *const fn () callconv(.c) void = undefined,
    reserved9: *const fn () callconv(.c) void = undefined,
};

pub const FrameInterface = extern struct {
    configure: *const fn (frame: *Frame, config: *Configuration, user_data: ?*anyopaque) callconv(.c) void,
    close: *const fn (frame: *Frame, user_data: ?*anyopaque) callconv(.c) void,
    commit: *const fn (frame: *Frame, user_data: ?*anyopaque) callconv(.c) void,
    dismiss_popup: *const fn (frame: *Frame, seat_name: ?[*:0]const u8, user_data: ?*anyopaque) callconv(.c) void,

    reserved1: *const fn () callconv(.c) void = undefined,
    reserved2: *const fn () callconv(.c) void = undefined,
    reserved3: *const fn () callconv(.c) void = undefined,
    reserved4: *const fn () callconv(.c) void = undefined,
    reserved5: *const fn () callconv(.c) void = undefined,
    reserved6: *const fn () callconv(.c) void = undefined,
    reserved7: *const fn () callconv(.c) void = undefined,
    reserved8: *const fn () callconv(.c) void = undefined,
    reserved9: *const fn () callconv(.c) void = undefined,
};

pub const LoadError = error{
    LibDecorNotFound,
    LookupFailed,
};

pub fn load() LoadError!void {
    var lib = std.DynLib.open("libdecor-0.so") catch return error.LibDecorNotFound;
    errdefer lib.close();
    log.debug("Loaded libdecor-0.so", .{});

    const struct_info = @typeInfo(LibDecor).@"struct";
    inline for (struct_info.decls) |decl| {
        const decl_type = @TypeOf(@field(LibDecor, decl.name));
        const decl_info = @typeInfo(decl_type);
        if (decl_info == .pointer and @typeInfo(decl_info.pointer.child) == .@"fn") {
            @field(LibDecor, decl.name) = lib.lookup(decl_type, "libdecor_" ++ decl.name) orelse {
                log.err("lookup failed: '{s}'", .{decl.name});
                return error.LookupFailed;
            };
        }
    }
}

pub var unref: *const fn (context: *Context) callconv(.c) void = undefined;
pub var new: *const fn (display: *wl.Display, iface: ?*Interface) callconv(.c) ?*Context = undefined;
pub var get_fd: *const fn (context: *Context) callconv(.c) c_int = undefined;
pub var dispatch: *const fn (context: *Context, timeout: c_int) callconv(.c) c_int = undefined;
pub var decorate: *const fn (context: *Context, surface: *wl.Surface, iface: *FrameInterface, user_data: *anyopaque) callconv(.c) ?*Frame = undefined;
pub var frame_ref: *const fn (frame: *Frame) callconv(.c) void = undefined;
pub var frame_unref: *const fn (frame: *Frame) callconv(.c) void = undefined;
pub var frame_set_visibility: *const fn (frame: *Frame, visible: bool) callconv(.c) void = undefined;
pub var frame_is_visible: *const fn (frame: *Frame) callconv(.c) bool = undefined;
pub var frame_set_parent: *const fn (frame: *Frame, parent: *Frame) callconv(.c) void = undefined;
pub var frame_set_title: *const fn (frame: *Frame, title: [*:0]const u8) callconv(.c) void = undefined;
pub var frame_get_title: *const fn (frame: *Frame) callconv(.c) ?[*:0]const u8 = undefined;
pub var frame_set_app_id: *const fn (frame: *Frame, app_id: ?[*:0]const u8) callconv(.c) void = undefined;
pub var frame_set_capabilities: *const fn (frame: *Frame, capabilities: Capabilities) callconv(.c) void = undefined;
pub var frame_unset_capabilities: *const fn (frame: *Frame, capabilities: Capabilities) callconv(.c) void = undefined;
pub var frame_has_capability: *const fn (frame: *Frame, capability: Capabilities) callconv(.c) bool = undefined;
pub var frame_show_window_menu: *const fn (frame: *Frame, seat: *wl.Seat, serial: u32, x: c_int, y: c_int) callconv(.c) void = undefined;
pub var frame_popup_grab: *const fn (frame: *Frame, seat_name: ?[*:0]const u8) callconv(.c) void = undefined;
pub var frame_popup_ungrab: *const fn (frame: *Frame, seat_name: ?[*:0]const u8) callconv(.c) void = undefined;
pub var frame_translate_coordinate: *const fn (frame: *Frame, surface_x: c_int, surface_y: c_int, frame_x: *c_int, frame_y: *c_int) callconv(.c) void = undefined;
pub var frame_set_min_content_size: *const fn (frame: *Frame, content_width: c_int, content_height: c_int) callconv(.c) void = undefined;
pub var frame_set_max_content_size: *const fn (frame: *Frame, content_width: c_int, content_height: c_int) callconv(.c) void = undefined;
pub var frame_get_min_content_size: *const fn (frame: *Frame, content_width: *c_int, content_height: *c_int) callconv(.c) void = undefined;
pub var frame_get_max_content_size: *const fn (frame: *Frame, content_width: *c_int, content_height: *c_int) callconv(.c) void = undefined;
pub var frame_resize: *const fn (frame: *Frame, seat: *wl.Seat, serial: u32, edge: ResizeEdge) callconv(.c) void = undefined;
pub var frame_move: *const fn (frame: *Frame, seat: *wl.Seat, serial: u32) callconv(.c) void = undefined;
pub var frame_commit: *const fn (frame: *Frame, state: *State, configuration: *Configuration) callconv(.c) void = undefined;
pub var frame_set_minimized: *const fn (frame: *Frame) callconv(.c) void = undefined;
pub var frame_set_maximized: *const fn (frame: *Frame) callconv(.c) void = undefined;
pub var frame_unset_maximized: *const fn (frame: *Frame) callconv(.c) void = undefined;
pub var frame_set_fullscreen: *const fn (frame: *Frame, output: *wl.Output) callconv(.c) void = undefined;
pub var frame_unset_fullscreen: *const fn (frame: *Frame) callconv(.c) void = undefined;
pub var frame_is_floating: *const fn (frame: *Frame) callconv(.c) bool = undefined;
pub var frame_close: *const fn (frame: *Frame) callconv(.c) void = undefined;
pub var frame_map: *const fn (frame: *Frame) callconv(.c) void = undefined;
pub var frame_get_xdg_surface: *const fn (frame: *Frame) callconv(.c) ?*xdg_shell.Surface = undefined;
pub var frame_get_xdg_toplevel: *const fn (frame: *Frame) callconv(.c) ?*xdg_shell.Toplevel = undefined;
pub var state_new: *const fn (width: c_int, height: c_int) callconv(.c) ?*State = undefined;
pub var state_free: *const fn (state: *State) callconv(.c) void = undefined;
pub var configuration_get_content_size: *const fn (configuration: *Configuration, frame: *Frame, width: *c_int, height: *c_int) callconv(.c) bool = undefined;
pub var configuration_get_window_state: *const fn (configuration: *Configuration, window_state: WindowState) callconv(.c) bool = undefined;
