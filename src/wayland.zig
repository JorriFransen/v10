const std = @import("std");
const log = std.log.scoped(.wayland);

pub const wl = struct {
    pub const Display = opaque {
        pub const wl_display_error = enum(c_uint) {
            invalid_object = 0,
            invalid_method = 1,
            no_memory = 2,
            implementation = 3,
        };

        pub const Listener = extern struct {
            @"error": *const fn (data: ?*anyopaque, display: ?*Display, object_id: ?*Object, code: u32, message: [*:0]const u8) callconv(.c) void,
            delete_id: *const fn (data: ?*anyopaque, display: ?*Display, id: u32) callconv(.c) void,
        };

        pub inline fn add_listener(display: *Display, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(display), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *Display, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Display) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Display) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn sync(self: *Display) ?*Callback {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 0, interfaces.callback, version, 0, NULL);
            return @ptrCast(result);
        }

        pub inline fn get_registry(self: *Display) ?*Registry {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 1, interfaces.registry, version, 0, NULL);
            return @ptrCast(result);
        }
    };

    pub const Registry = opaque {
        pub const Listener = extern struct {
            global: *const fn (data: ?*anyopaque, registry: ?*Registry, name: u32, interface: [*:0]const u8, version: u32) callconv(.c) void,
            global_remove: *const fn (data: ?*anyopaque, registry: ?*Registry, name: u32) callconv(.c) void,
        };

        pub inline fn add_listener(registry: *Registry, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(registry), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *Registry, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Registry) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Registry) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn destroy(self: *Registry) void {
            proxy_destroy(@ptrCast(self));
        }

        pub inline fn bind(self: *Registry, name: u32, interface: *const Interface, version: u32) *opaque {} {
            const result = proxy_marshal_flags(@ptrCast(self), 0, interface, version, 0, name, interface.name.ptr, version, NULL);
            return @ptrCast(result);
        }
    };

    pub const Callback = opaque {
        pub const Listener = extern struct {
            done: *const fn (data: ?*anyopaque, callback: ?*Callback, callback_data: u32) callconv(.c) void,
        };

        pub inline fn add_listener(callback: *Callback, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(callback), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *Callback, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Callback) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Callback) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn destroy(self: *Callback) void {
            proxy_destroy(@ptrCast(self));
        }

    };

    pub const Compositor = opaque {
        pub inline fn set_user_data(self: *Compositor, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Compositor) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Compositor) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn create_surface(self: *Compositor) ?*Surface {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 0, interfaces.surface, version, 0, NULL);
            return @ptrCast(result);
        }

        pub inline fn create_region(self: *Compositor) ?*Region {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 1, interfaces.region, version, 0, NULL);
            return @ptrCast(result);
        }
    };

    pub const ShmPool = opaque {
        pub inline fn set_user_data(self: *ShmPool, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *ShmPool) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *ShmPool) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn create_buffer(self: *ShmPool, offset: i32, width: i32, height: i32, stride: i32, format: u32) ?*Buffer {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 0, interfaces.buffer, version, 0, NULL, offset, width, height, stride, format);
            return @ptrCast(result);
        }

        pub inline fn destroy(self: *ShmPool) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 1, null, version, WL_MARSHAL_FLAG_DESTROY);
        }

        pub inline fn resize(self: *ShmPool, size: i32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 2, null, version, 0, size);
        }
    };

    pub const Shm = opaque {
        pub const wl_shm_error = enum(c_uint) {
            invalid_format = 0,
            invalid_stride = 1,
            invalid_fd = 2,
        };

        pub const wl_shm_format = enum(c_uint) {
            argb8888 = 0,
            xrgb8888 = 1,
            c8 = 0x20203843,
            rgb332 = 0x38424752,
            bgr233 = 0x38524742,
            xrgb4444 = 0x32315258,
            xbgr4444 = 0x32314258,
            rgbx4444 = 0x32315852,
            bgrx4444 = 0x32315842,
            argb4444 = 0x32315241,
            abgr4444 = 0x32314241,
            rgba4444 = 0x32314152,
            bgra4444 = 0x32314142,
            xrgb1555 = 0x35315258,
            xbgr1555 = 0x35314258,
            rgbx5551 = 0x35315852,
            bgrx5551 = 0x35315842,
            argb1555 = 0x35315241,
            abgr1555 = 0x35314241,
            rgba5551 = 0x35314152,
            bgra5551 = 0x35314142,
            rgb565 = 0x36314752,
            bgr565 = 0x36314742,
            rgb888 = 0x34324752,
            bgr888 = 0x34324742,
            xbgr8888 = 0x34324258,
            rgbx8888 = 0x34325852,
            bgrx8888 = 0x34325842,
            abgr8888 = 0x34324241,
            rgba8888 = 0x34324152,
            bgra8888 = 0x34324142,
            xrgb2101010 = 0x30335258,
            xbgr2101010 = 0x30334258,
            rgbx1010102 = 0x30335852,
            bgrx1010102 = 0x30335842,
            argb2101010 = 0x30335241,
            abgr2101010 = 0x30334241,
            rgba1010102 = 0x30334152,
            bgra1010102 = 0x30334142,
            yuyv = 0x56595559,
            yvyu = 0x55595659,
            uyvy = 0x59565955,
            vyuy = 0x59555956,
            ayuv = 0x56555941,
            nv12 = 0x3231564e,
            nv21 = 0x3132564e,
            nv16 = 0x3631564e,
            nv61 = 0x3136564e,
            yuv410 = 0x39565559,
            yvu410 = 0x39555659,
            yuv411 = 0x31315559,
            yvu411 = 0x31315659,
            yuv420 = 0x32315559,
            yvu420 = 0x32315659,
            yuv422 = 0x36315559,
            yvu422 = 0x36315659,
            yuv444 = 0x34325559,
            yvu444 = 0x34325659,
            r8 = 0x20203852,
            r16 = 0x20363152,
            rg88 = 0x38384752,
            gr88 = 0x38385247,
            rg1616 = 0x32334752,
            gr1616 = 0x32335247,
            xrgb16161616f = 0x48345258,
            xbgr16161616f = 0x48344258,
            argb16161616f = 0x48345241,
            abgr16161616f = 0x48344241,
            xyuv8888 = 0x56555958,
            vuy888 = 0x34325556,
            vuy101010 = 0x30335556,
            y210 = 0x30313259,
            y212 = 0x32313259,
            y216 = 0x36313259,
            y410 = 0x30313459,
            y412 = 0x32313459,
            y416 = 0x36313459,
            xvyu2101010 = 0x30335658,
            xvyu12_16161616 = 0x36335658,
            xvyu16161616 = 0x38345658,
            y0l0 = 0x304c3059,
            x0l0 = 0x304c3058,
            y0l2 = 0x324c3059,
            x0l2 = 0x324c3058,
            yuv420_8bit = 0x38305559,
            yuv420_10bit = 0x30315559,
            xrgb8888_a8 = 0x38415258,
            xbgr8888_a8 = 0x38414258,
            rgbx8888_a8 = 0x38415852,
            bgrx8888_a8 = 0x38415842,
            rgb888_a8 = 0x38413852,
            bgr888_a8 = 0x38413842,
            rgb565_a8 = 0x38413552,
            bgr565_a8 = 0x38413542,
            nv24 = 0x3432564e,
            nv42 = 0x3234564e,
            p210 = 0x30313250,
            p010 = 0x30313050,
            p012 = 0x32313050,
            p016 = 0x36313050,
            axbxgxrx106106106106 = 0x30314241,
            nv15 = 0x3531564e,
            q410 = 0x30313451,
            q401 = 0x31303451,
            xrgb16161616 = 0x38345258,
            xbgr16161616 = 0x38344258,
            argb16161616 = 0x38345241,
            abgr16161616 = 0x38344241,
            c1 = 0x20203143,
            c2 = 0x20203243,
            c4 = 0x20203443,
            d1 = 0x20203144,
            d2 = 0x20203244,
            d4 = 0x20203444,
            d8 = 0x20203844,
            r1 = 0x20203152,
            r2 = 0x20203252,
            r4 = 0x20203452,
            r10 = 0x20303152,
            r12 = 0x20323152,
            avuy8888 = 0x59555641,
            xvuy8888 = 0x59555658,
            p030 = 0x30333050,
        };

        pub const Listener = extern struct {
            format: *const fn (data: ?*anyopaque, shm: ?*Shm, format: u32) callconv(.c) void,
        };

        pub inline fn add_listener(shm: *Shm, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(shm), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *Shm, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Shm) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Shm) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn create_pool(self: *Shm, fd: u32, size: i32) ?*ShmPool {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 0, interfaces.shm_pool, version, 0, NULL, fd, size);
            return @ptrCast(result);
        }

        pub inline fn release(self: *Shm) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 1, null, version, WL_MARSHAL_FLAG_DESTROY);
        }
    };

    pub const Buffer = opaque {
        pub const Listener = extern struct {
            release: *const fn (data: ?*anyopaque, buffer: ?*Buffer) callconv(.c) void,
        };

        pub inline fn add_listener(buffer: *Buffer, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(buffer), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *Buffer, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Buffer) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Buffer) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn destroy(self: *Buffer) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, WL_MARSHAL_FLAG_DESTROY);
        }
    };

    pub const DataOffer = opaque {
        pub const wl_data_offer_error = enum(c_uint) {
            invalid_finish = 0,
            invalid_action_mask = 1,
            invalid_action = 2,
            invalid_offer = 3,
        };

        pub const Listener = extern struct {
            offer: *const fn (data: ?*anyopaque, data_offer: ?*DataOffer, mime_type: [*:0]const u8) callconv(.c) void,
            source_actions: *const fn (data: ?*anyopaque, data_offer: ?*DataOffer, source_actions: u32) callconv(.c) void,
            action: *const fn (data: ?*anyopaque, data_offer: ?*DataOffer, dnd_action: u32) callconv(.c) void,
        };

        pub inline fn add_listener(data_offer: *DataOffer, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(data_offer), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *DataOffer, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *DataOffer) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *DataOffer) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn accept(self: *DataOffer, serial: u32, mime_type: [*:0]const u8) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, 0, serial, mime_type);
        }

        pub inline fn receive(self: *DataOffer, mime_type: [*:0]const u8, fd: u32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 1, null, version, 0, mime_type, fd);
        }

        pub inline fn destroy(self: *DataOffer) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 2, null, version, WL_MARSHAL_FLAG_DESTROY);
        }

        pub inline fn finish(self: *DataOffer) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 3, null, version, 0, NULL);
        }

        pub inline fn set_actions(self: *DataOffer, dnd_actions: u32, preferred_action: u32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 4, null, version, 0, dnd_actions, preferred_action);
        }
    };

    pub const DataSource = opaque {
        pub const wl_data_source_error = enum(c_uint) {
            invalid_action_mask = 0,
            invalid_source = 1,
        };

        pub const Listener = extern struct {
            target: *const fn (data: ?*anyopaque, data_source: ?*DataSource, mime_type: [*:0]const u8) callconv(.c) void,
            send: *const fn (data: ?*anyopaque, data_source: ?*DataSource, mime_type: [*:0]const u8, fd: u32) callconv(.c) void,
            cancelled: *const fn (data: ?*anyopaque, data_source: ?*DataSource) callconv(.c) void,
            dnd_drop_performed: *const fn (data: ?*anyopaque, data_source: ?*DataSource) callconv(.c) void,
            dnd_finished: *const fn (data: ?*anyopaque, data_source: ?*DataSource) callconv(.c) void,
            action: *const fn (data: ?*anyopaque, data_source: ?*DataSource, dnd_action: u32) callconv(.c) void,
        };

        pub inline fn add_listener(data_source: *DataSource, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(data_source), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *DataSource, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *DataSource) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *DataSource) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn offer(self: *DataSource, mime_type: [*:0]const u8) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, 0, mime_type);
        }

        pub inline fn destroy(self: *DataSource) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 1, null, version, WL_MARSHAL_FLAG_DESTROY);
        }

        pub inline fn set_actions(self: *DataSource, dnd_actions: u32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 2, null, version, 0, dnd_actions);
        }
    };

    pub const DataDevice = opaque {
        pub const wl_data_device_error = enum(c_uint) {
            role = 0,
            used_source = 1,
        };

        pub const Listener = extern struct {
            data_offer: *const fn (data: ?*anyopaque, data_device: ?*DataDevice, id: ?*Object) callconv(.c) void,
            enter: *const fn (data: ?*anyopaque, data_device: ?*DataDevice, serial: u32, surface: ?*Object, x: Fixed, y: Fixed, id: ?*Object) callconv(.c) void,
            leave: *const fn (data: ?*anyopaque, data_device: ?*DataDevice) callconv(.c) void,
            motion: *const fn (data: ?*anyopaque, data_device: ?*DataDevice, time: u32, x: Fixed, y: Fixed) callconv(.c) void,
            drop: *const fn (data: ?*anyopaque, data_device: ?*DataDevice) callconv(.c) void,
            selection: *const fn (data: ?*anyopaque, data_device: ?*DataDevice, id: ?*Object) callconv(.c) void,
        };

        pub inline fn add_listener(data_device: *DataDevice, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(data_device), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *DataDevice, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *DataDevice) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *DataDevice) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn start_drag(self: *DataDevice, source: ?*DataSource, origin: ?*Surface, icon: ?*Surface, serial: u32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, 0, source, origin, icon, serial);
        }

        pub inline fn set_selection(self: *DataDevice, source: ?*DataSource, serial: u32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 1, null, version, 0, source, serial);
        }

        pub inline fn release(self: *DataDevice) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 2, null, version, WL_MARSHAL_FLAG_DESTROY);
        }
    };

    pub const DataDeviceManager = opaque {
        pub const wl_data_device_manager_dnd_action = packed struct(u32) {
            copy: bool = false, // 1
            move: bool = false, // 2
            ask: bool = false, // 4
            _pad0: u29 = 0,
            pub const none: @This() = @bitCast(0);
        };


        pub inline fn set_user_data(self: *DataDeviceManager, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *DataDeviceManager) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *DataDeviceManager) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn create_data_source(self: *DataDeviceManager) ?*DataSource {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 0, interfaces.data_source, version, 0, NULL);
            return @ptrCast(result);
        }

        pub inline fn get_data_device(self: *DataDeviceManager, seat: ?*Seat) ?*DataDevice {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 1, interfaces.data_device, version, 0, NULL, seat);
            return @ptrCast(result);
        }
    };

    pub const Shell = opaque {
        pub const wl_shell_error = enum(c_uint) {
            role = 0,
        };

        pub inline fn set_user_data(self: *Shell, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Shell) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Shell) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn get_shell_surface(self: *Shell, surface: ?*Surface) ?*ShellSurface {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 0, interfaces.shell_surface, version, 0, NULL, surface);
            return @ptrCast(result);
        }
    };

    pub const ShellSurface = opaque {
        pub const wl_shell_surface_resize = packed struct(u32) {
            top: bool = false, // 1
            bottom: bool = false, // 2
            left: bool = false, // 4
            right: bool = false, // 8
            _pad0: u28 = 0,
            pub const none: @This() = @bitCast(0);
            pub const top_left: @This() = @bitCast(5);
            pub const bottom_left: @This() = @bitCast(6);
            pub const top_right: @This() = @bitCast(9);
            pub const bottom_right: @This() = @bitCast(10);
        };


        pub const wl_shell_surface_transient = packed struct(u32) {
            inactive: bool = false, // 0x1
            _pad0: u31 = 0,
        };


        pub const wl_shell_surface_fullscreen_method = enum(c_uint) {
            default = 0,
            scale = 1,
            driver = 2,
            fill = 3,
        };

        pub const Listener = extern struct {
            ping: *const fn (data: ?*anyopaque, shell_surface: ?*ShellSurface, serial: u32) callconv(.c) void,
            configure: *const fn (data: ?*anyopaque, shell_surface: ?*ShellSurface, edges: u32, width: i32, height: i32) callconv(.c) void,
            popup_done: *const fn (data: ?*anyopaque, shell_surface: ?*ShellSurface) callconv(.c) void,
        };

        pub inline fn add_listener(shell_surface: *ShellSurface, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(shell_surface), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *ShellSurface, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *ShellSurface) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *ShellSurface) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn pong(self: *ShellSurface, serial: u32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, 0, serial);
        }

        pub inline fn move(self: *ShellSurface, seat: ?*Seat, serial: u32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 1, null, version, 0, seat, serial);
        }

        pub inline fn resize(self: *ShellSurface, seat: ?*Seat, serial: u32, edges: u32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 2, null, version, 0, seat, serial, edges);
        }

        pub inline fn set_toplevel(self: *ShellSurface) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 3, null, version, 0, NULL);
        }

        pub inline fn set_transient(self: *ShellSurface, parent: ?*Surface, x: i32, y: i32, flags: u32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 4, null, version, 0, parent, x, y, flags);
        }

        pub inline fn set_fullscreen(self: *ShellSurface, method: u32, framerate: u32, output: ?*Output) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 5, null, version, 0, method, framerate, output);
        }

        pub inline fn set_popup(self: *ShellSurface, seat: ?*Seat, serial: u32, parent: ?*Surface, x: i32, y: i32, flags: u32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 6, null, version, 0, seat, serial, parent, x, y, flags);
        }

        pub inline fn set_maximized(self: *ShellSurface, output: ?*Output) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 7, null, version, 0, output);
        }

        pub inline fn set_title(self: *ShellSurface, title: [*:0]const u8) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 8, null, version, 0, title);
        }

        pub inline fn set_class(self: *ShellSurface, class_: [*:0]const u8) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 9, null, version, 0, class_);
        }
    };

    pub const Surface = opaque {
        pub const wl_surface_error = enum(c_uint) {
            invalid_scale = 0,
            invalid_transform = 1,
            invalid_size = 2,
            invalid_offset = 3,
            defunct_role_object = 4,
        };

        pub const Listener = extern struct {
            enter: *const fn (data: ?*anyopaque, surface: ?*Surface, output: ?*Object) callconv(.c) void,
            leave: *const fn (data: ?*anyopaque, surface: ?*Surface, output: ?*Object) callconv(.c) void,
            preferred_buffer_scale: *const fn (data: ?*anyopaque, surface: ?*Surface, factor: i32) callconv(.c) void,
            preferred_buffer_transform: *const fn (data: ?*anyopaque, surface: ?*Surface, transform: u32) callconv(.c) void,
        };

        pub inline fn add_listener(surface: *Surface, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(surface), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *Surface, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Surface) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Surface) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn destroy(self: *Surface) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, WL_MARSHAL_FLAG_DESTROY);
        }

        pub inline fn attach(self: *Surface, buffer: ?*Buffer, x: i32, y: i32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 1, null, version, 0, buffer, x, y);
        }

        pub inline fn damage(self: *Surface, x: i32, y: i32, width: i32, height: i32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 2, null, version, 0, x, y, width, height);
        }

        pub inline fn frame(self: *Surface) ?*Callback {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 3, interfaces.callback, version, 0, NULL);
            return @ptrCast(result);
        }

        pub inline fn set_opaque_region(self: *Surface, region: ?*Region) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 4, null, version, 0, region);
        }

        pub inline fn set_input_region(self: *Surface, region: ?*Region) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 5, null, version, 0, region);
        }

        pub inline fn commit(self: *Surface) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 6, null, version, 0, NULL);
        }

        pub inline fn set_buffer_transform(self: *Surface, transform: i32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 7, null, version, 0, transform);
        }

        pub inline fn set_buffer_scale(self: *Surface, scale: i32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 8, null, version, 0, scale);
        }

        pub inline fn damage_buffer(self: *Surface, x: i32, y: i32, width: i32, height: i32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 9, null, version, 0, x, y, width, height);
        }

        pub inline fn offset(self: *Surface, x: i32, y: i32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 10, null, version, 0, x, y);
        }
    };

    pub const Seat = opaque {
        pub const wl_seat_capability = packed struct(u32) {
            pointer: bool = false, // 1
            keyboard: bool = false, // 2
            touch: bool = false, // 4
            _pad0: u29 = 0,
        };


        pub const wl_seat_error = enum(c_uint) {
            missing_capability = 0,
        };

        pub const Listener = extern struct {
            capabilities: *const fn (data: ?*anyopaque, seat: ?*Seat, capabilities: u32) callconv(.c) void,
            name: *const fn (data: ?*anyopaque, seat: ?*Seat, name: [*:0]const u8) callconv(.c) void,
        };

        pub inline fn add_listener(seat: *Seat, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(seat), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *Seat, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Seat) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Seat) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn get_pointer(self: *Seat) ?*Pointer {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 0, interfaces.pointer, version, 0, NULL);
            return @ptrCast(result);
        }

        pub inline fn get_keyboard(self: *Seat) ?*Keyboard {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 1, interfaces.keyboard, version, 0, NULL);
            return @ptrCast(result);
        }

        pub inline fn get_touch(self: *Seat) ?*Touch {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 2, interfaces.touch, version, 0, NULL);
            return @ptrCast(result);
        }

        pub inline fn release(self: *Seat) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 3, null, version, WL_MARSHAL_FLAG_DESTROY);
        }
    };

    pub const Pointer = opaque {
        pub const wl_pointer_error = enum(c_uint) {
            role = 0,
        };

        pub const wl_pointer_button_state = enum(c_uint) {
            released = 0,
            pressed = 1,
        };

        pub const wl_pointer_axis = enum(c_uint) {
            vertical_scroll = 0,
            horizontal_scroll = 1,
        };

        pub const wl_pointer_axis_source = enum(c_uint) {
            wheel = 0,
            finger = 1,
            continuous = 2,
            wheel_tilt = 3,
        };

        pub const wl_pointer_axis_relative_direction = enum(c_uint) {
            identical = 0,
            inverted = 1,
        };

        pub const Listener = extern struct {
            enter: *const fn (data: ?*anyopaque, pointer: ?*Pointer, serial: u32, surface: ?*Object, surface_x: Fixed, surface_y: Fixed) callconv(.c) void,
            leave: *const fn (data: ?*anyopaque, pointer: ?*Pointer, serial: u32, surface: ?*Object) callconv(.c) void,
            motion: *const fn (data: ?*anyopaque, pointer: ?*Pointer, time: u32, surface_x: Fixed, surface_y: Fixed) callconv(.c) void,
            button: *const fn (data: ?*anyopaque, pointer: ?*Pointer, serial: u32, time: u32, button: u32, state: u32) callconv(.c) void,
            axis: *const fn (data: ?*anyopaque, pointer: ?*Pointer, time: u32, axis: u32, value: Fixed) callconv(.c) void,
            frame: *const fn (data: ?*anyopaque, pointer: ?*Pointer) callconv(.c) void,
            axis_source: *const fn (data: ?*anyopaque, pointer: ?*Pointer, axis_source: u32) callconv(.c) void,
            axis_stop: *const fn (data: ?*anyopaque, pointer: ?*Pointer, time: u32, axis: u32) callconv(.c) void,
            axis_value120: *const fn (data: ?*anyopaque, pointer: ?*Pointer, axis: u32, value120: i32) callconv(.c) void,
            axis_relative_direction: *const fn (data: ?*anyopaque, pointer: ?*Pointer, axis: u32, direction: u32) callconv(.c) void,
        };

        pub inline fn add_listener(pointer: *Pointer, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(pointer), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *Pointer, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Pointer) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Pointer) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn set_cursor(self: *Pointer, serial: u32, surface: ?*Surface, hotspot_x: i32, hotspot_y: i32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, 0, serial, surface, hotspot_x, hotspot_y);
        }

        pub inline fn release(self: *Pointer) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 1, null, version, WL_MARSHAL_FLAG_DESTROY);
        }
    };

    pub const Keyboard = opaque {
        pub const wl_keyboard_keymap_format = enum(c_uint) {
            no_keymap = 0,
            xkb_v1 = 1,
        };

        pub const wl_keyboard_key_state = enum(c_uint) {
            released = 0,
            pressed = 1,
            repeated = 2,
        };

        pub const Listener = extern struct {
            keymap: *const fn (data: ?*anyopaque, keyboard: ?*Keyboard, format: u32, fd: u32, size: u32) callconv(.c) void,
            enter: *const fn (data: ?*anyopaque, keyboard: ?*Keyboard, serial: u32, surface: ?*Object, keys: Array) callconv(.c) void,
            leave: *const fn (data: ?*anyopaque, keyboard: ?*Keyboard, serial: u32, surface: ?*Object) callconv(.c) void,
            key: *const fn (data: ?*anyopaque, keyboard: ?*Keyboard, serial: u32, time: u32, key: u32, state: u32) callconv(.c) void,
            modifiers: *const fn (data: ?*anyopaque, keyboard: ?*Keyboard, serial: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, group: u32) callconv(.c) void,
            repeat_info: *const fn (data: ?*anyopaque, keyboard: ?*Keyboard, rate: i32, delay: i32) callconv(.c) void,
        };

        pub inline fn add_listener(keyboard: *Keyboard, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(keyboard), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *Keyboard, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Keyboard) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Keyboard) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn release(self: *Keyboard) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, WL_MARSHAL_FLAG_DESTROY);
        }
    };

    pub const Touch = opaque {
        pub const Listener = extern struct {
            down: *const fn (data: ?*anyopaque, touch: ?*Touch, serial: u32, time: u32, surface: ?*Object, id: i32, x: Fixed, y: Fixed) callconv(.c) void,
            up: *const fn (data: ?*anyopaque, touch: ?*Touch, serial: u32, time: u32, id: i32) callconv(.c) void,
            motion: *const fn (data: ?*anyopaque, touch: ?*Touch, time: u32, id: i32, x: Fixed, y: Fixed) callconv(.c) void,
            frame: *const fn (data: ?*anyopaque, touch: ?*Touch) callconv(.c) void,
            cancel: *const fn (data: ?*anyopaque, touch: ?*Touch) callconv(.c) void,
            shape: *const fn (data: ?*anyopaque, touch: ?*Touch, id: i32, major: Fixed, minor: Fixed) callconv(.c) void,
            orientation: *const fn (data: ?*anyopaque, touch: ?*Touch, id: i32, orientation: Fixed) callconv(.c) void,
        };

        pub inline fn add_listener(touch: *Touch, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(touch), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *Touch, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Touch) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Touch) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn release(self: *Touch) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, WL_MARSHAL_FLAG_DESTROY);
        }
    };

    pub const Output = opaque {
        pub const wl_output_subpixel = enum(c_uint) {
            unknown = 0,
            none = 1,
            horizontal_rgb = 2,
            horizontal_bgr = 3,
            vertical_rgb = 4,
            vertical_bgr = 5,
        };

        pub const wl_output_transform = enum(c_uint) {
            normal = 0,
            @"90" = 1,
            @"180" = 2,
            @"270" = 3,
            flipped = 4,
            flipped_90 = 5,
            flipped_180 = 6,
            flipped_270 = 7,
        };

        pub const wl_output_mode = packed struct(u32) {
            current: bool = false, // 0x1
            preferred: bool = false, // 0x2
            _pad0: u30 = 0,
        };


        pub const Listener = extern struct {
            geometry: *const fn (data: ?*anyopaque, output: ?*Output, x: i32, y: i32, physical_width: i32, physical_height: i32, subpixel: i32, make: [*:0]const u8, model: [*:0]const u8, transform: i32) callconv(.c) void,
            mode: *const fn (data: ?*anyopaque, output: ?*Output, flags: u32, width: i32, height: i32, refresh: i32) callconv(.c) void,
            done: *const fn (data: ?*anyopaque, output: ?*Output) callconv(.c) void,
            scale: *const fn (data: ?*anyopaque, output: ?*Output, factor: i32) callconv(.c) void,
            name: *const fn (data: ?*anyopaque, output: ?*Output, name: [*:0]const u8) callconv(.c) void,
            description: *const fn (data: ?*anyopaque, output: ?*Output, description: [*:0]const u8) callconv(.c) void,
        };

        pub inline fn add_listener(output: *Output, listener: *const Listener, data: ?*anyopaque) void {
            proxy_add_listener(@ptrCast(output), @ptrCast(@constCast(listener)), data);
        }

        pub inline fn set_user_data(self: *Output, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Output) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Output) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn release(self: *Output) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, WL_MARSHAL_FLAG_DESTROY);
        }
    };

    pub const Region = opaque {
        pub inline fn set_user_data(self: *Region, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Region) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Region) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn destroy(self: *Region) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, WL_MARSHAL_FLAG_DESTROY);
        }

        pub inline fn add(self: *Region, x: i32, y: i32, width: i32, height: i32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 1, null, version, 0, x, y, width, height);
        }

        pub inline fn subtract(self: *Region, x: i32, y: i32, width: i32, height: i32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 2, null, version, 0, x, y, width, height);
        }
    };

    pub const Subcompositor = opaque {
        pub const wl_subcompositor_error = enum(c_uint) {
            bad_surface = 0,
            bad_parent = 1,
        };

        pub inline fn set_user_data(self: *Subcompositor, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Subcompositor) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Subcompositor) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn destroy(self: *Subcompositor) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, WL_MARSHAL_FLAG_DESTROY);
        }

        pub inline fn get_subsurface(self: *Subcompositor, surface: ?*Surface, parent: ?*Surface) ?*Subsurface {
            const version = proxy_get_version(@ptrCast(self));
            const result = proxy_marshal_flags(@ptrCast(self), 1, interfaces.subsurface, version, 0, NULL, surface, parent);
            return @ptrCast(result);
        }
    };

    pub const Subsurface = opaque {
        pub const wl_subsurface_error = enum(c_uint) {
            bad_surface = 0,
        };

        pub inline fn set_user_data(self: *Subsurface, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Subsurface) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Subsurface) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn destroy(self: *Subsurface) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, WL_MARSHAL_FLAG_DESTROY);
        }

        pub inline fn set_position(self: *Subsurface, x: i32, y: i32) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 1, null, version, 0, x, y);
        }

        pub inline fn place_above(self: *Subsurface, sibling: ?*Surface) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 2, null, version, 0, sibling);
        }

        pub inline fn place_below(self: *Subsurface, sibling: ?*Surface) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 3, null, version, 0, sibling);
        }

        pub inline fn set_sync(self: *Subsurface) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 4, null, version, 0, NULL);
        }

        pub inline fn set_desync(self: *Subsurface) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 5, null, version, 0, NULL);
        }
    };

    pub const Fixes = opaque {
        pub inline fn set_user_data(self: *Fixes, user_data: *anyopaque) void {
            proxy_set_user_data(@ptrCast(self), user_data);
        }

        pub inline fn get_user_data(self: *Fixes) ?*anyopaque {
            return proxy_get_user_data(@ptrCast(self));
        }

        pub inline fn get_version(self: *Fixes) u32 {
            return proxy_get_version(@ptrCast(self));
        }

        pub inline fn destroy(self: *Fixes) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 0, null, version, WL_MARSHAL_FLAG_DESTROY);
        }

        pub inline fn destroy_registry(self: *Fixes, registry: ?*Registry) void {
            const version = proxy_get_version(@ptrCast(self));
            _ = proxy_marshal_flags(@ptrCast(self), 1, null, version, 0, registry);
        }
    };
    pub const EventQueue = opaque {};
    pub const Proxy = opaque {};
    pub const Timespec = opaque {};
    pub const Object = opaque {};

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

        try interfaces.load(lib);
    }

    const WL_MARSHAL_FLAG_DESTROY = (1 << 0);
    const NULL: usize = 0;

};

pub const interfaces = struct {
    pub var display :*const Interface = undefined;
    pub var registry :*const Interface = undefined;
    pub var callback :*const Interface = undefined;
    pub var compositor :*const Interface = undefined;
    pub var shm_pool :*const Interface = undefined;
    pub var shm :*const Interface = undefined;
    pub var buffer :*const Interface = undefined;
    pub var data_offer :*const Interface = undefined;
    pub var data_source :*const Interface = undefined;
    pub var data_device :*const Interface = undefined;
    pub var data_device_manager :*const Interface = undefined;
    pub var shell :*const Interface = undefined;
    pub var shell_surface :*const Interface = undefined;
    pub var surface :*const Interface = undefined;
    pub var seat :*const Interface = undefined;
    pub var pointer :*const Interface = undefined;
    pub var keyboard :*const Interface = undefined;
    pub var touch :*const Interface = undefined;
    pub var output :*const Interface = undefined;
    pub var region :*const Interface = undefined;
    pub var subcompositor :*const Interface = undefined;
    pub var subsurface :*const Interface = undefined;
    pub var fixes :*const Interface = undefined;

    pub fn load(lib: *std.DynLib) !void {
        inline for (@typeInfo(@This()).@"struct".decls) |decl| {
            const decl_type = @TypeOf(@field(@This(), decl.name));
            if (decl_type == *const Interface) {
                if (lib.lookup(decl_type, "wl_" ++ decl.name ++ "_interface")) |sym| {
                    @field(interfaces, decl.name) = sym;
                } else {
                    log.err("Failed to load wayland symbol: wl_{s}", .{decl.name});
                    return error.SymbolLoadFailed;
                }
            }
        }
    }
};

const Interface = extern struct {
    name: [*:0]const u8,
    version: c_int,
    method_count: c_int,
    methods: ?[*]const Message,
    event_count: c_int,
    events: ?[*]const Message,
};

const Message = extern struct {
    name: [*:0]const u8,
    signature: [*:0]const u8,
    types: ?[*]const ?*const Interface,
};

const Fixed = enum(u32) {};

const Array = extern struct {
    size: usize,
    alloc: usize,
    data: *anyopaque,
};

const Argument = extern union {
    i: i32,
    u: u32,
    f: Fixed,
    s: ?[*]const u8,
    o: ?*wl.Object,
    n: u32,
    a: ?*Array,
    h: i32,
};

const DispatcherFunc = *const fn (user_data: *const anyopaque, target: *anyopaque, opcode: u32, message: *Message, args: [*]Argument) callconv(.c) c_int;
const LogFunc = *const fn (fmt: [*]const u8, args: *anyopaque) callconv(.c) void;
