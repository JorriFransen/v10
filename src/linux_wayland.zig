const std = @import("std");
const log = std.log.scoped(.linux_wayland);

const options = @import("options");

const core = @import("core");
const TimeStamp = core.time.TimeStamp;
const assert = core.assert;
const linux = core.os.linux;
const math = core.math;

const common = @import("v10_common");
const Input = common.Input;

const wayland = @import("wayland");
const wlc = wayland.client;
const wl = wayland.wayland;
const xdg_shell = wayland.xdg_shell;
const xdg_decoration = wayland.xdg_decoration_unstable_v1;

const linux_v10 = @import("linux_v10.zig");
const bytes_per_pixel = linux_v10.bytes_per_pixel;

const Context = @This();

// TODO: Check if (wayland) preferred_buffer_scale is relevant

closed: bool = false,
should_draw: bool = false,

input: *linux_v10.InputState,

pool: *wl.ShmPool = undefined,
buffers: [3]Buffer = undefined,

outputs: [8]Output = @splat(.{ .handle = undefined, .ctx = undefined }),

registry: *wl.Registry = undefined,
display: *wl.Display = undefined,
wl_shm: *wl.Shm = undefined,
wl_compositor: *wl.Compositor = undefined,
wl_seat: *wl.Seat = undefined,
surface: *wl.Surface = undefined,
xdg_wm_base: *xdg_shell.WmBase = undefined,
keyboard: *wl.Keyboard = undefined,

last_pointer_enter_serial: u32 = undefined,
pointer: *wl.Pointer = undefined,

xdg_surface: *xdg_shell.Surface = undefined,
xdg_toplevel: *xdg_shell.Toplevel = undefined,
xdg_toplevel_decoration: ?*xdg_decoration.ToplevelDecorationV1 = null,
xdg_decoration_manager: ?*xdg_decoration.DecorationManagerV1 = null,

pending_data_offer: ?*wl.DataOffer = null,
active_selection_offer: ?*wl.DataOffer = null,
active_dnd_offer: ?*wl.DataOffer = null,
active_dnd_source_actions: wl.DataDeviceManager.DndAction = .{},
active_dnd_action: wl.DataDeviceManager.DndAction = .{},

pending_offer_mime_weight: u8 = 0,
pending_offer_mime: ?[]const u8 = null,
selection_mime: ?[]const u8 = null,
dnd_mime: ?[]const u8 = null,

pending_offer_mime_buffer: [256]u8 = @splat(0),
selection_mime_buffer: [256]u8 = @splat(0),
dnd_mime_buffer: [256]u8 = @splat(0),

/// Window width
window_width: i32 = 0,
/// Window height
window_height: i32 = 0,

/// Max width of (non fullscreen) surface
bound_width: i32 = 0,
/// Max height of (non fullscreen) surface
bound_height: i32 = 0,
/// Max width of all outputs
max_width: i32 = 0,
/// Max height of all outputs
max_height: i32 = 0,

back_buffer_width: i32,
back_buffer_height: i32,

max_buffer_size: usize = undefined,
shm_fd: linux.fd_t = -1,
shm_data: []align(std.heap.page_size_min) u8 = &.{},

fullscreen: bool = false,
double_scale: bool = false,

pending_configure_serial: ?u32 = null,
pending_resize: ?PendingResize = null,

shared_state: *common.SharedState = undefined,

has_xrgb8888_format: bool = false,
seat_capabilities: wl.Seat.Capability = .{},
bound_interfaces: BoundInterfaces = .{},

const BoundInterfaces = packed struct(u4) {
    wl_shm: bool = false,
    wl_seat: bool = false,
    wl_compositor: bool = false,
    xdg_wm_base: bool = false,
};

const Output = struct {
    flags: Flags = .{},
    ctx: *Context,
    handle: *wl.Output,
    refresh_mhz: i32 = 0,

    const Flags = packed struct(u2) {
        connected: bool = false,
        active: bool = false,
    };
};

const Buffer = struct {
    handle: *wl.Buffer,
    offset: i32,
    free: bool,
    width: i32,
    height: i32,
    pitch: i32,
};

const PendingResize = struct {
    width: i32,
    height: i32,
};

// TODO: Use xkb!
pub const ModKeys = packed struct(u32) {
    shift: bool = false,
    __reveved1: u1 = 0,
    control: bool = false,
    alt: bool = false,
    num: bool = false,
    __reserved2: u27 = 0,
};

pub fn init(this: *Context, environ_opt: ?*const std.process.Environ, shared_state: *common.SharedState, window_width: i32, window_height: i32, back_buffer_width: i32, back_buffer_height: i32, title: []const u8, input: *linux_v10.InputState) !void {
    this.* = .{
        .input = input,
        .shared_state = shared_state,
        .back_buffer_width = back_buffer_width,
        .back_buffer_height = back_buffer_height,
    };

    this.display = wlc.displayConnect(null, environ_opt) orelse {
        log.err("wl_display_connect failed", .{});
        return error.UnexpectedWayland;
    };
    errdefer wlc.displayDisconnect(this.display);

    log.info("Wayland display connected", .{});

    this.registry = this.display.getRegistry();
    errdefer this.registry.destroy();

    _ = this.registry.addListener(&registry_listener, this);
    if (wlc.displayRoundtrip(this.display) == -1) {
        log.err("wl_display_roundtrip failed", .{});
        return error.UnexpectedWayland;
    }
    log.debug("Registry roundtrip done", .{});

    inline for (std.meta.fields(@TypeOf(this.bound_interfaces))) |field| {
        if (@field(this.bound_interfaces, field.name) == false) {
            log.err("Failed to bind wayland interface: '{s}'", .{field.name});
            return error.MissingWaylandInterface;
        }
    }

    errdefer {
        this.wl_shm.release();
        this.wl_compositor.destroy();
        this.wl_seat.release();
        this.xdg_wm_base.destroy();
        if (this.xdg_decoration_manager) |xdm| xdm.destroy();

        for (&this.outputs) |*output| if (output.flags.connected) {
            output.handle.release();
        };
    }

    for (&this.outputs) |*output| if (output.flags.connected) {
        _ = output.handle.addListener(&output_listener, output);
    };

    _ = wlc.displayRoundtrip(this.display); // Wait for max_width/height to be set

    log.debug("Wayland seat capabilities: {}", .{this.seat_capabilities});
    log.debug("Max size: {},{}", .{ this.max_width, this.max_height });

    this.window_width = window_width;
    this.window_height = window_height;

    log.debug("initial window size: {},{}", .{ this.window_width, this.window_height });

    if (this.seat_capabilities.keyboard == false) {
        log.debug("keyboard not available", .{});
        return error.UnexpectedWayland;
    }
    if (this.seat_capabilities.pointer == false) {
        log.debug("mouse not available", .{});
        return error.UnexpectedWayland;
    }

    if (this.has_xrgb8888_format == false) {
        log.err("xrgb8888 format not avaliable", .{});
        return error.UnexpectedWayland;
    }

    this.surface = this.wl_compositor.createSurface();
    errdefer this.surface.destroy();
    _ = this.surface.addListener(&surface_listener, this);

    try allocShm(this);
    errdefer freeShm(this);

    this.pool = this.wl_shm.createPool(this.shm_fd, @intCast(this.shm_data.len));
    errdefer this.pool.destroy();

    const buffer_width = this.window_width;
    const buffer_height = this.window_height;
    assert(buffer_width > 0 and buffer_height > 0);
    const pitch = buffer_width * bytes_per_pixel;

    var shm_offset: i32 = 0;
    for (&this.buffers) |*buffer| {
        const handle = this.pool.createBuffer(shm_offset, buffer_width, buffer_height, pitch, .xrgb8888);

        buffer.* = .{
            .handle = handle,
            .offset = shm_offset,
            .free = true,
            .width = buffer_width,
            .height = buffer_height,
            .pitch = pitch,
        };
        _ = handle.addListener(&buffer_listener, buffer);

        shm_offset += @intCast(this.max_buffer_size);
    }

    errdefer for (&this.buffers) |*buffer| {
        buffer.handle.destroy();
    };

    this.xdg_surface = this.xdg_wm_base.getXdgSurface(this.surface);
    errdefer this.xdg_surface.destroy();
    _ = this.xdg_surface.addListener(&xdg_surface_listener, this);

    this.xdg_toplevel = this.xdg_surface.getToplevel();
    errdefer this.xdg_toplevel.destroy();
    const toplevel_init_listener = this.xdg_toplevel.addListener(&xdg_toplevel_init_listener, this);
    defer {
        this.xdg_toplevel.removeListener(toplevel_init_listener);
        _ = this.xdg_toplevel.addListener(&xdg_toplevel_listener, this);
    }

    this.xdg_toplevel.setAppId(title);
    this.xdg_toplevel.setTitle(title);
    this.surface.commit();
    _ = wlc.displayRoundtrip(this.display);
    this.handlePendingResize();

    if (this.xdg_decoration_manager) |dec_manager| {
        const dec = dec_manager.getToplevelDecoration(this.xdg_toplevel);
        dec.setMode(.serverSide);

        var xdg_decoration_mode: ?xdg_decoration.ToplevelDecorationV1.Mode = null;
        const dec_mode_listener = dec.addListener(&xdg_decoration_listener, &xdg_decoration_mode);

        _ = wlc.displayRoundtrip(this.display);
        if (this.pending_configure_serial) |serial| {
            this.xdg_surface.ackConfigure(serial);
        }
        this.pending_configure_serial = null;

        dec.removeListener(dec_mode_listener);

        if (xdg_decoration_mode == .serverSide) {
            this.xdg_toplevel_decoration = dec;
        } else if (xdg_decoration_mode != .serverSide) {
            dec.destroy();
        }
    } else {
        log.debug("xdg_decoration not supported, falling back to no decorations", .{});
    }

    _ = wlc.displayRoundtrip(this.display);
    if (this.pending_configure_serial) |serial| {
        this.xdg_surface.ackConfigure(serial);
    }
    this.pending_configure_serial = null;
    this.handlePendingResize();

    this.keyboard = this.wl_seat.getKeyboard();
    errdefer this.keyboard.release();
    _ = this.keyboard.addListener(&keyboard_listener, this);

    this.pointer = this.wl_seat.getPointer();
    errdefer this.pointer.release();
    _ = this.pointer.addListener(&mouse_listener, this);

    const wl_buffer = this.acquireFreeBuffer().?;
    swapBuffers(this, wl_buffer);
}

pub fn deinit(this: *Context) void {
    this.pointer.release();
    this.keyboard.release();

    if (this.xdg_toplevel_decoration) |dec| {
        dec.destroy();
    }
    this.xdg_toplevel.destroy();
    this.xdg_surface.destroy();

    this.surface.destroy();

    for (&this.buffers) |*buffer| {
        buffer.handle.destroy();
    }

    this.pool.destroy();

    freeShm(this);

    if (this.pending_data_offer) |pdo| pdo.destroy();
    if (this.active_selection_offer) |aso| aso.destroy();
    if (this.active_dnd_offer) |ado| ado.destroy();

    for (&this.outputs) |*output| if (output.flags.connected) {
        output.handle.release();
    };

    this.wl_shm.release();
    this.wl_seat.release();
    this.wl_compositor.destroy();
    this.xdg_wm_base.destroy();
    if (this.xdg_decoration_manager) |xdm| xdm.destroy();

    this.registry.destroy();

    wlc.displayDisconnect(this.display);
}

pub fn poll(this: *Context) bool {
    const result = wlc.displayDispatchTimeout(this.display, .zero) != -1;
    return result;
}

pub fn pollTimeout(this: *Context, ns: u64) bool {
    const result = wlc.displayDispatchTimeout(this.display, .timeout(ns)) != -1;
    return result;
}

pub fn handlePendingResize(this: *Context) void {
    if (this.pending_resize) |r| {
        if (this.pending_configure_serial) |serial| {
            this.xdg_surface.ackConfigure(serial);
            this.pending_configure_serial = null;
        }
        try this.resize(r.width, r.height);
    }
}

pub fn minOutputHz(this: *const Context) f32 {
    var min: f32 = math.maxFloat(f32);
    for (&this.outputs) |*output| if (output.flags.connected) {
        min = @min(min, @as(f32, @floatFromInt(output.refresh_mhz)) / 1000);
    };
    return min;
}

pub fn hideCursor(this: *Context) void {
    this.pointer.setCursor(this.last_pointer_enter_serial, null, 0, 0);
}

/// Return value indicates if a wl_buffer was available, and thus if the offscreenbuffer was actually displayed
pub fn blitBuffer(this: *Context, buffer: *const linux_v10.LinuxOffscreenBuffer) bool {
    if (!this.should_draw) {
        log.warn("Failed to display buffer, should_draw=false", .{});
        return false;
    }

    if (this.acquireFreeBuffer()) |wl_buffer| {
        const wl_buffer_ptr: [*]u8 = this.shm_data.ptr + @as(usize, @intCast(wl_buffer.offset));
        const wl_buffer_mem: []u8 = wl_buffer_ptr[0..@intCast(wl_buffer.pitch * wl_buffer.height)];

        // TODO: Clear gutters in release?
        if (options.internal_build) {
            @memset(@as([]u32, @ptrCast(@alignCast(wl_buffer_mem))), 0);
        }

        if (this.double_scale) {
            const dest_line_length: usize = @intCast(@min(buffer.width * 2, wl_buffer.width) * bytes_per_pixel);
            const source_line_length: usize = @intCast(@min(buffer.width, @divTrunc(wl_buffer.width, 2)) * bytes_per_pixel);

            const source_row_count: usize = @intCast(@min(buffer.height, @divTrunc(wl_buffer.height, 2)));

            for (0..source_row_count) |src_y| {
                const source_offset = src_y * @as(usize, @intCast(buffer.pitch));
                const source_line: []u32 = @ptrCast(@alignCast(buffer.memory[source_offset .. source_offset + source_line_length]));

                const dst_y = src_y * 2;
                const dest_offset1 = dst_y * @as(usize, @intCast(wl_buffer.pitch));
                const dest_line1: []u32 = @ptrCast(@alignCast(wl_buffer_mem[dest_offset1 .. dest_offset1 + dest_line_length]));
                const dest_offset2 = dest_offset1 + @as(usize, @intCast(wl_buffer.pitch));
                const dest_line2: []u32 = @ptrCast(@alignCast(wl_buffer_mem[dest_offset2 .. dest_offset2 + dest_line_length]));

                for (0..source_line.len) |src_x| {
                    const dst_x = src_x * 2;

                    dest_line1[dst_x] = source_line[src_x];
                    dest_line1[dst_x + 1] = source_line[src_x];
                }

                @memcpy(dest_line2, dest_line1);
            }
        } else {

            // TODO: Offset mouse position by this
            const x_offset = 10;
            const y_offset = 10;

            const line_length: usize = @intCast(@min(buffer.width, wl_buffer.width - x_offset) * bytes_per_pixel);
            const row_count: usize = @intCast(@min(buffer.height, wl_buffer.height - y_offset));

            // NOTE: This could be a single memcopy if:
            //  - We reallocate the offscreen_buffer in the same way as the wayland buffers (same size).
            //  - UpdateAndRender is passed an offscreen buffer where width and height are static (logical back buffer size).
            //  - UpdateAndRender is passed an offscreen buffer where the pitch matches the size of a line in the actual buffers.
            //  - We enforce the logical back buffer size as the minimum window size (orelse the game will write out of bounds).
            //
            //  I might actually prefer that, but for now this matches hh on win32.
            const y_off: usize = @intCast(y_offset);
            const x_off: usize = @intCast(x_offset);
            for (y_off..y_off + row_count, 0..row_count) |dst_y, src_y| {
                const dest_offset = (dst_y * @as(usize, @intCast(wl_buffer.pitch))) + (x_off * bytes_per_pixel);
                const dest_line = wl_buffer_mem[dest_offset .. dest_offset + line_length];

                const source_offset = src_y * @as(usize, @intCast(buffer.pitch));
                const source_line = buffer.memory[source_offset .. source_offset + line_length];

                @memcpy(dest_line, source_line);
            }
        }

        this.swapBuffers(wl_buffer);
        return true;
    } else {
        log.warn("Failed to acquire wayland buffer!", .{});
        return false;
    }
}

const ShmError = error{
    ShmOpenFailed,
    ShmCloseFailed,
    ShmUnlinkFailed,
    FtruncateFailed,
    MmapFailed,
    WlShmCreatePoolFailed,
    WlPoolCreateBufferFailed,
};

fn allocShm(this: *Context) ShmError!void {
    const S = linux.S;

    assert(this.shm_data.len == 0);

    const prng_seed = TimeStamp.now(.real);
    var prng_impl = std.Random.DefaultPrng.init(@intCast(prng_seed.ns()));
    const prng = prng_impl.random();

    var name_buf: [18]u8 = undefined;
    name_buf[0] = '/';
    name_buf[name_buf.len - 1] = 0;

    for (name_buf[1 .. name_buf.len - 1]) |*char| {
        switch (prng.intRangeLessThan(u8, 0, 3)) {
            0 => char.* = prng.intRangeAtMost(u8, '0', '9'),
            1 => char.* = prng.intRangeAtMost(u8, 'a', 'z'),
            2 => char.* = prng.intRangeAtMost(u8, 'A', 'Z'),
            else => unreachable,
        }
    }
    const name = name_buf[0 .. name_buf.len - 1 :0];
    log.debug("shm name: {s}", .{name});

    // TODO: Use mem_fd!
    const open_flags = linux.O{ .ACCMODE = .RDWR, .CREAT = true, .EXCL = true };
    const mode: linux.mode_t = S.IWUSR | S.IRUSR | S.IWOTH | S.IROTH;
    this.shm_fd = linux.shm_open(name, open_flags, mode) catch |e| {
        log.err("shm_open failed, error: {}", .{e});
        return error.ShmOpenFailed;
    };
    errdefer linux.close(this.shm_fd);

    linux.shm_unlink(name) catch |e| {
        log.err("shm_unlink failed, error: {}", .{e});
        return error.ShmUnlinkFailed;
    };

    const pixel_count: usize = @intCast(this.max_width * this.max_height);
    this.max_buffer_size = pixel_count * bytes_per_pixel;
    log.debug("shm per buffer size: {}", .{this.max_buffer_size});
    const shm_size = this.max_buffer_size * this.buffers.len;
    log.debug("Allocating shm: {}", .{shm_size});

    linux.ftruncate(this.shm_fd, @intCast(shm_size)) catch {
        log.err("ftruncate failed", .{});
        return error.FtruncateFailed;
    };

    const prot = linux.PROT{ .READ = true, .WRITE = true };
    const map = linux.MAP{ .TYPE = .SHARED };

    assert(shm_size > 0);
    if (linux.mmap(null, shm_size, prot, map, this.shm_fd, 0)) |mapped| {
        this.shm_data = mapped;
    } else |_| {
        log.err("mmap call failed during shm buffer alloc", .{});
        return error.MmapFailed;
    }
}

fn freeShm(this: *Context) void {
    linux.munmap(this.shm_data) catch {};
    linux.close(this.shm_fd);
}

fn resize(this: *Context, new_width: i32, new_height: i32) !void {
    if (new_width != this.window_width or new_height != this.window_height) {
        log.info("resize: {},{} (double_scale:{})", .{ new_width, new_height, this.double_scale });
    }

    if (new_width != 0) {
        this.window_width = new_width;
    }
    if (new_height != 0) {
        this.window_height = new_height;
    }

    this.double_scale = new_width >= this.back_buffer_width * 2 and new_height >= this.back_buffer_height * 2;
    this.should_draw = true;
    this.pending_resize = null;
}

fn acquireFreeBuffer(this: *Context) ?*Buffer {
    for (&this.buffers) |*buffer| {
        if (buffer.free) {
            if (buffer.width != this.window_width or buffer.height != this.window_height) {
                buffer.handle.destroy();

                const pitch = this.window_width * bytes_per_pixel;

                const new_buf = this.pool.createBuffer(buffer.offset, this.window_width, this.window_height, pitch, .xrgb8888);

                buffer.* = .{
                    .handle = new_buf,
                    .offset = buffer.offset,
                    .width = this.window_width,
                    .height = this.window_height,
                    .pitch = pitch,
                    .free = false,
                };

                _ = new_buf.addListener(&buffer_listener, buffer);
            }

            buffer.free = false;
            return buffer;
        }
    }

    return null;
}

fn swapBuffers(this: *Context, buffer: *Buffer) void {
    assert(buffer.width == this.window_width);
    assert(buffer.height == this.window_height);

    this.surface.attach(buffer.handle, 0, 0);

    if (options.internal_build) {
        this.surface.damage(0, 0, buffer.width, buffer.height);
    } else {
        const width, const height = if (this.double_scale)
            .{ buffer.width * 2, buffer.height * 2 }
        else
            .{ buffer.width, buffer.height };

        this.surface.damage(0, 0, @min(buffer.width, width), @min(buffer.height, height));
    }

    const callback = this.surface.frame();
    this.should_draw = false;
    _ = callback.addListener(&frame_callback_listener, this);

    this.surface.commit();
    _ = wlc.displayFlush(this.display);
}

const registry_listener = wl.Registry.Listener{
    .global = handleRegisterGlobal,
    .globalRemove = handleRemoveGlobal,
};

fn handleRegisterGlobal(data: ?*anyopaque, registry: *wl.Registry, name: u32, interface_name: []const u8, version: u32) void {
    const ctx: *Context = @ptrCast(@alignCast(data));

    const Mapping = struct {
        []const u8,
        type,
        ?*const anyopaque,
    };

    const mappings = [_]Mapping{
        .{ "wl_shm", wl.Shm, &shm_listener },
        .{ "wl_seat", wl.Seat, &seat_listener },
        .{ "wl_compositor", wl.Compositor, null },
        .{ "xdg_wm_base", xdg_shell.WmBase, &xdg_wm_base_listener },
        .{ "xdg_decoration_manager", xdg_decoration.DecorationManagerV1, null },
    };

    var found = false;
    inline for (mappings) |map| {
        const target_field_name: []const u8 = map[0];
        const Interface: type = map[1];

        if (std.mem.eql(u8, interface_name, Interface.interface.name)) {
            const proxy = registry.bindTyped(Interface, name, version);
            @field(ctx, target_field_name) = proxy;

            if (@hasField(@TypeOf(ctx.bound_interfaces), target_field_name)) {
                @field(ctx.bound_interfaces, target_field_name) = true;
            }
            found = true;

            if (map[2]) |listener| {
                _ = proxy.addListener(@ptrCast(@alignCast(listener)), ctx);
            }
            break;
        }
    }

    if (!found) {
        if (std.mem.eql(u8, "wl_output", interface_name)) {
            var free_slot_found = false;
            for (&ctx.outputs) |*output| {
                if (!output.flags.connected) {
                    const wl_output = registry.bindTyped(wl.Output, name, version);
                    output.* = .{
                        .ctx = ctx,
                        .handle = wl_output,
                        .flags = .{ .connected = true },
                    };
                    free_slot_found = true;

                    break;
                }
            }

            if (!free_slot_found) {
                log.warn("Monitor capacity reached (8)! Ignoring monitor.", .{});
            }
        }
    }
}

fn handleRemoveGlobal(data: ?*anyopaque, registry: *wl.Registry, name: u32) void {
    _ = data;
    _ = registry;

    // TODO: Handle monitor hotplug?
    log.debug("Remove global: {}", .{name});
}

const shm_listener = wl.Shm.Listener{
    .format = handleShmFormat,
};

fn handleShmFormat(data: ?*anyopaque, shm: *wl.Shm, format: wl.Shm.Format) void {
    _ = shm;
    const ctx: *Context = @ptrCast(@alignCast(data));

    if (format == .xrgb8888) ctx.has_xrgb8888_format = true;
}

const surface_listener = wl.Surface.Listener{
    .enter = handleSurfaceEnter,
    .leave = handleSurfaceLeave,
    .preferredBufferScale = null,
    .preferredBufferTransform = null,
};

fn handleSurfaceEnter(data: ?*anyopaque, surface: *wl.Surface, current_output: *wl.Output) void {
    _ = surface;
    const ctx: *Context = @ptrCast(@alignCast(data));

    var found = false;
    for (&ctx.outputs) |*output| if (output.flags.connected) {
        if (output.handle == current_output) {
            output.flags.active = true;
            found = true;
            break;
        }
    };

    if (!found) {
        log.warn("Failed to find matching output: {*}", .{current_output});
    }
}

fn handleSurfaceLeave(data: ?*anyopaque, surface: *wl.Surface, current_output: *wl.Output) void {
    _ = surface;
    const ctx: *Context = @ptrCast(@alignCast(data));

    log.debug("Surface leave: {}", .{current_output});

    var found = false;
    for (&ctx.outputs) |*output| if (output.flags.connected) {
        if (output.handle == current_output) {
            output.flags.active = false;
            found = true;
            break;
        }
    };

    if (!found) {
        log.warn("Failed to find matching output: {*}", .{current_output});
    }
}

const xdg_wm_base_listener = xdg_shell.WmBase.Listener{
    .ping = handleXdgPing,
};

fn handleXdgPing(data: ?*anyopaque, wm_base: *xdg_shell.WmBase, serial: u32) void {
    _ = data;
    wm_base.pong(serial);
}

const xdg_surface_listener = xdg_shell.Surface.Listener{
    .configure = handleXdgSurfaceConfigure,
};

fn handleXdgSurfaceConfigure(data: ?*anyopaque, surface: *xdg_shell.Surface, serial: u32) void {
    _ = surface;
    const ctx: *Context = @ptrCast(@alignCast(data));

    ctx.pending_configure_serial = serial;
}

const xdg_toplevel_init_listener = xdg_shell.Toplevel.Listener{
    .configure = handleXdgToplevelConfigureInit,
    .configureBounds = handleXdgToplevelConfigureBounds,
    .wmCapabilities = handleXdgToplevelWmCapabilities,
    .close = handleXdgToplevelClose,
};

fn handleXdgToplevelConfigureInit(data: ?*anyopaque, toplevel: *xdg_shell.Toplevel, width: i32, height: i32, states_: []const u32) void {
    _ = toplevel;
    const ctx: *Context = @ptrCast(@alignCast(data));

    log.debug("xdg toplevel init configure: {},{}", .{ width, height });

    const E = xdg_shell.Toplevel.State;
    const states: []const E = @ptrCast(states_);
    _ = states;

    if (width != 0 or height != 0) {
        ctx.pending_resize = .{ .width = width, .height = height };
    }
}

const xdg_toplevel_listener = xdg_shell.Toplevel.Listener{
    .configure = handleXdgToplevelConfigure,
    .configureBounds = handleXdgToplevelConfigureBounds,
    .wmCapabilities = handleXdgToplevelWmCapabilities,
    .close = handleXdgToplevelClose,
};

fn handleXdgToplevelConfigure(data: ?*anyopaque, toplevel: *xdg_shell.Toplevel, width: i32, height: i32, states_: []const u32) void {
    _ = toplevel;
    const ctx: *Context = @ptrCast(@alignCast(data));

    log.debug("xdg toplevel configure: {},{}", .{ width, height });

    const E = xdg_shell.Toplevel.State;
    const states: []const E = @ptrCast(states_);
    _ = states;

    ctx.pending_resize = .{ .width = width, .height = height };
}

fn handleXdgToplevelConfigureBounds(data: ?*anyopaque, toplevel: *xdg_shell.Toplevel, width: i32, height: i32) void {
    _ = toplevel;
    const ctx: *Context = @ptrCast(@alignCast(data));

    ctx.bound_width = width;
    ctx.bound_height = height;
    log.debug("xdg toplevel configure bounds {},{}", .{ width, height });
}

fn handleXdgToplevelWmCapabilities(data: ?*anyopaque, toplevel: *xdg_shell.Toplevel, capabilities: []const u32) void {
    _ = data;
    _ = toplevel;

    const E = xdg_shell.Toplevel.WmCapabilities;
    const caps: []const E = @ptrCast(capabilities);
    _ = caps;
}

fn handleXdgToplevelClose(data: ?*anyopaque, toplevel: *xdg_shell.Toplevel) void {
    _ = toplevel;
    const ctx: *Context = @ptrCast(@alignCast(data));

    ctx.closed = true;
}

const frame_callback_listener = wl.Callback.Listener{
    .done = handleCallbackFrameDone,
};

fn handleCallbackFrameDone(data: ?*anyopaque, _: *wl.Callback, _: u32) void {
    const ctx: *Context = @ptrCast(@alignCast(data));
    ctx.should_draw = true;
}

const buffer_listener = wl.Buffer.Listener{
    .release = handleBufferRelease,
};

fn handleBufferRelease(data: ?*anyopaque, wl_buffer: *wl.Buffer) void {
    const buffer: *Buffer = @ptrCast(@alignCast(data));

    assert(buffer.handle == wl_buffer);
    buffer.free = true;
}

const seat_listener = wl.Seat.Listener{
    .capabilities = handleSeatCapabilities,
    .name = null,
};

fn handleSeatCapabilities(data: ?*anyopaque, seat: *wl.Seat, capabilities: wl.Seat.Capability) void {
    _ = seat;

    const ctx: *Context = @ptrCast(@alignCast(data));
    ctx.seat_capabilities = capabilities;
}

const keyboard_listener = wl.Keyboard.Listener{
    .key = handleKey,
    .enter = null,
    .leave = null,
    .modifiers = null,
    .repeatInfo = null,
    .keymap = null,
};

fn handleKey(data: ?*anyopaque, keyboard: *wl.Keyboard, serial: u32, time: u32, raw_key: u32, state: wl.Keyboard.KeyState) void {
    _ = keyboard;
    _ = time;
    _ = serial;
    const ctx: *Context = @ptrCast(@alignCast(data));

    // TODO: Do this via the keymap with xkb!
    const key: linux.KEY = @enumFromInt(raw_key);
    const was_down = state != .pressed;
    const is_down = state != .released;

    linux_v10.handleKey(ctx, ctx.input.new, key, was_down, is_down);
}

const mouse_listener = wl.Pointer.Listener{
    .enter = handlePointerEnter,
    .leave = null,
    .motion = handleMouseMotion,
    .button = handleMouseButton,
    .axis = handleMouseAxis,
    .frame = null, // TODO: Use this to handle incoming data correctly in relation to frame boundaries
    .axisDiscrete = null,
    .axisSource = null,
    .axisStop = null,
    .axisValue120 = null,
    .axisRelativeDirection = null,
};

fn handlePointerEnter(data: ?*anyopaque, pointer: *wl.Pointer, serial: u32, surface: *wl.Surface, surface_x: wl.Fixed, surface_y: wl.Fixed) void {
    const ctx: *Context = @ptrCast(@alignCast(data));
    assert(pointer == ctx.pointer);
    assert(surface == ctx.surface);

    ctx.last_pointer_enter_serial = serial;
    linux_v10.handleMouseEnter(ctx, ctx.input.new, surface_x.toInt(), surface_y.toInt());
}

fn handleMouseMotion(data: ?*anyopaque, pointer: *wl.Pointer, time: u32, surface_x: wl.Fixed, surface_y: wl.Fixed) void {
    _ = time;
    _ = pointer;
    const ctx: *Context = @ptrCast(@alignCast(data));

    linux_v10.handleMouseMotion(ctx, ctx.input.new, surface_x.toInt(), surface_y.toInt());
}

fn handleMouseButton(data: ?*anyopaque, pointer: *wl.Pointer, serial: u32, time: u32, raw_button: u32, state: wl.Pointer.ButtonState) void {
    _ = pointer;
    _ = serial;
    _ = time;
    const ctx: *Context = @ptrCast(@alignCast(data));

    const button: linux.KEY = @enumFromInt(raw_button);
    const was_down = state != .pressed;
    const is_down = state != .released;
    linux_v10.handleMouseButton(ctx, button, was_down, is_down);
}

fn handleMouseAxis(data: ?*anyopaque, pointer: *wl.Pointer, time: u32, axis: wl.Pointer.Axis, value: wl.Fixed) void {
    _ = pointer;
    _ = time;
    _ = axis;
    _ = value;
    const ctx: *Context = @ptrCast(@alignCast(data));
    _ = ctx;
    // log.debug("mouse axis: {}:{}", .{ axis, value.toDouble() });
}

const xdg_decoration_listener = xdg_decoration.ToplevelDecorationV1.Listener{
    .configure = handleXdgDecorationConfigure,
};

fn handleXdgDecorationConfigure(data: ?*anyopaque, toplevel_decoration: *xdg_decoration.ToplevelDecorationV1, mode: xdg_decoration.ToplevelDecorationV1.Mode) void {
    _ = toplevel_decoration;
    log.info("xdg_decoration configure: {}", .{mode});

    const mode_ptr: *?xdg_decoration.ToplevelDecorationV1.Mode = @ptrCast(@alignCast(data));
    mode_ptr.* = mode;
}

const output_listener = wl.Output.Listener{
    .geometry = null,
    .mode = handleOutputMode,
    .done = null,
    .scale = null,
    .name = null,
    .description = null,
};

fn handleOutputMode(data: ?*anyopaque, output: *wl.Output, flags: wl.Output.Mode, width: i32, height: i32, refresh: i32) void {
    _ = flags;

    const output_data: *Output = @ptrCast(@alignCast(data));
    const ctx = output_data.ctx;

    assert(output_data.handle == output);
    output_data.refresh_mhz = refresh;

    // log.debug("handleOutputMode: {},{},{},{}", .{ flags, width, height, refresh });

    const new_pixel_count = width * height;
    const max_pixel_count = ctx.max_width * ctx.max_height;
    if (new_pixel_count > max_pixel_count) {
        ctx.max_width = width;
        ctx.max_height = height;
    }
}
