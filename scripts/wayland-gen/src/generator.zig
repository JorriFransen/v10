const std = @import("std");
const log = std.log.scoped(.@"wayland-gen.generator");
const types = @import("types.zig");
const mem = @import("mem");

const assert = std.debug.assert;

const Generator = @This();
const Allocator = std.mem.Allocator;

const Protocol = types.Protocol;
const Interface = types.Interface;
const Request = types.Request;
const Event = types.Event;
const Enum = types.Enum;
const Arg = types.Arg;
const Type = types.Type;

allocator: Allocator,
protocol: *const Protocol,
buf: std.ArrayList(u8),

pub fn generate(allocator: Allocator, protocol: *const Protocol) ![]const u8 {
    var generator = Generator{
        .allocator = allocator,
        .buf = std.ArrayList(u8){},
        .protocol = protocol,
    };

    generator.append(
        \\const std = @import("std");
        \\const log = std.log.scoped(.wayland);
        \\
        \\const Interface = extern struct {
        \\    name: [*:0]const u8,
        \\    version: c_int,
        \\    method_count: c_int,
        \\    methods: ?[*]const Message,
        \\    event_count: c_int,
        \\    events: ?[*]const Message,
        \\};
        \\
        \\const Message = extern struct {
        \\    name: [*:0]const u8,
        \\    signature: [*:0]const u8,
        \\    types: ?[*]const ?*const Interface,
        \\};
        \\
        \\const Fixed = enum(u32) {};
        \\
        \\const Array = extern struct {
        \\    size: usize,
        \\    alloc: usize,
        \\    data: *anyopaque,
        \\};
        \\
        \\const Argument = extern union {
        \\    i: i32,
        \\    u: u32,
        \\    f: Fixed,
        \\    s: ?[*]const u8,
        \\    o: ?*wl.Object,
        \\    n: u32,
        \\    a: ?*Array,
        \\    h: i32,
        \\};
        \\
        \\const DispatcherFunc = *const fn (user_data: *const anyopaque, target: *anyopaque, opcode: u32, message: *Message, args: [*]Argument) callconv(.c) c_int;
        \\const LogFunc = *const fn (fmt: [*]const u8, args: *anyopaque) callconv(.c) void;
        \\
        \\pub const wl = struct {
        \\    pub const EventQueue = opaque {};
        \\    pub const Proxy = opaque {};
        \\    pub const Timespec = opaque {};
        \\    pub const Object = opaque {};
        \\
        \\    pub var event_queue_destroy: *const fn (queue: *EventQueue) callconv(.c) void = undefined;
        \\    pub var proxy_marshal_flags: *const fn (proxy: *Proxy, opcode: u32, interface: *const Interface, version: u32, flags: u32, ...) callconv(.c) *Proxy = undefined;
        \\    pub var proxy_marshal_array_flags: *const fn (proxy: *Proxy, opcode: u32, interface: *const Interface, version: u32, flags: u32, args: ?[*]Argument) callconv(.c) *Proxy = undefined;
        \\    pub var proxy_marshal: *const fn (proxy: *Proxy, opcode: u32, ...) callconv(.c) void = undefined;
        \\    pub var proxy_marshal_array: *const fn (proxy: *Proxy, opcode: u32, args: ?[*]Argument) callconv(.c) void = undefined;
        \\    pub var proxy_create: *const fn (proxy: *Proxy, interface: *const Interface) callconv(.c) *Proxy = undefined;
        \\    pub var proxy_create_wrapper: *const fn (proxy: *anyopaque) callconv(.c) *anyopaque = undefined;
        \\    pub var proxy_wrapper_destroy: *const fn (proxy: *anyopaque) callconv(.c) void = undefined;
        \\    pub var proxy_marshal_constructor: *const fn (proxy: *Proxy, opcode: u32, interface: *const Interface, ...) callconv(.c) *Proxy = undefined;
        \\    pub var proxy_marshal_constructor_versioned: *const fn (proxy: *Proxy, opcode: u32, interface: *const Interface, version: u32, ...) callconv(.c) *Proxy = undefined;
        \\    pub var proxy_marshal_array_constructor: *const fn (proxy: *Proxy, opcode: u32, args: [*]Argument, interface: *const Interface) callconv(.c) ?*Proxy = undefined;
        \\    pub var proxy_marshal_array_constructor_versioned: *const fn (proxy: *Proxy, opcode: u32, args: [*]Argument, interface: *const Interface, version: u32) callconv(.c) *Proxy = undefined;
        \\    pub var proxy_destroy: *const fn (proxy: *Proxy) callconv(.c) void = undefined;
        \\    pub var proxy_add_listener: *const fn (proxy: *Proxy, implementation: **const fn () callconv(.c) void, data: ?*anyopaque) callconv(.c) void = undefined;
        \\    pub var proxy_get_listener: *const fn (proxy: *Proxy) callconv(.c) ?*anyopaque = undefined;
        \\    pub var proxy_add_dispatcher: *const fn (proxy: *Proxy, dispatcher_func: DispatcherFunc, dispatcher_data: *const anyopaque, data: *anyopaque) callconv(.c) c_int = undefined;
        \\    pub var proxy_set_user_data: *const fn (proxy: *Proxy, user_data: *anyopaque) callconv(.c) void = undefined;
        \\    pub var proxy_get_user_data: *const fn (proxy: *Proxy) callconv(.c) *anyopaque = undefined;
        \\    pub var proxy_get_version: *const fn (proxy: *Proxy) callconv(.c) u32 = undefined;
        \\    pub var proxy_get_id: *const fn (proxy: *Proxy) callconv(.c) u32 = undefined;
        \\    pub var proxy_set_tag: *const fn (proxy: *Proxy, tag: ?[*]const ?[*]const u8) callconv(.c) void = undefined;
        \\    pub var proxy_get_class: *const fn (proxy: *Proxy) callconv(.c) ?[*]const u8 = undefined;
        \\    pub var proxy_get_display: *const fn (proxy: *Proxy) callconv(.c) ?*Display = undefined;
        \\    pub var proxy_set_queue: *const fn (proxy: *Proxy, queue: *EventQueue) callconv(.c) void = undefined;
        \\    pub var proxy_get_queue: *const fn (proxy: *Proxy) callconv(.c) ?*EventQueue = undefined;
        \\    pub var event_queue_get_name: *const fn (queue: *const EventQueue) callconv(.c) ?[*]const u8 = undefined;
        \\    pub var display_connect: *const fn (name: ?[*]u8) callconv(.c) ?*Display = undefined;
        \\    pub var display_connect_to_fd: *const fn (fd: c_int) callconv(.c) ?*Display = undefined;
        \\    pub var display_disconnect: *const fn (display: *Display) callconv(.c) void = undefined;
        \\    pub var display_get_fd: *const fn (display: *Display) callconv(.c) c_int = undefined;
        \\    pub var display_dispatch: *const fn (display: *Display) callconv(.c) c_int = undefined;
        \\    pub var display_dispatch_queue: *const fn (display: *Display, queue: *EventQueue) callconv(.c) c_int = undefined;
        \\    pub var display_dispatch_timeout: *const fn (display: *Display, timeout: *const Timespec) callconv(.c) c_int = undefined;
        \\    pub var display_dispatch_queue_timeout: *const fn (display: *Display, queue: *EventQueue, timeout: *const Timespec) callconv(.c) c_int = undefined;
        \\    pub var display_dispatch_queue_pending: *const fn (display: *Display, queue: *EventQueue) callconv(.c) c_int = undefined;
        \\    pub var display_dispatch_pending: *const fn (display: *Display) callconv(.c) c_int = undefined;
        \\    pub var display_get_error: *const fn (display: *Display) callconv(.c) c_int = undefined;
        \\    pub var display_get_protocol_error: *const fn (display: *Display, interface: **const Interface, id: *u32) callconv(.c) u32 = undefined;
        \\    pub var display_flush: *const fn (display: *Display) callconv(.c) c_int = undefined;
        \\    pub var display_roundtrip_queue: *const fn (display: *Display, queue: *EventQueue) callconv(.c) c_int = undefined;
        \\    pub var display_roundtrip: *const fn (display: *Display) callconv(.c) c_int = undefined;
        \\    pub var display_create_queue: *const fn (display: *Display) callconv(.c) ?*EventQueue = undefined;
        \\    pub var display_create_queue_with_name: *const fn (display: *Display, name: [*:0]const u8) callconv(.c) ?*EventQueue = undefined;
        \\    pub var display_prepare_read_queue: *const fn (display: *Display, queue: *EventQueue) callconv(.c) c_int = undefined;
        \\    pub var display_prepare_read: *const fn (display: *Display) callconv(.c) c_int = undefined;
        \\    pub var display_cancel_read: *const fn (display: *Display) callconv(.c) void = undefined;
        \\    pub var display_read_events: *const fn (display: *Display) callconv(.c) c_int = undefined;
        \\    pub var log_set_handler_client: *const fn (handler: LogFunc) callconv(.c) void = undefined;
        \\    pub var display_set_max_buffer_size: *const fn (display: *Display, max_buffer_size: usize) callconv(.c) void = undefined;
        \\
        \\    pub fn load(lib: *std.DynLib) !void {
        \\        inline for (@typeInfo(@This()).@"struct".decls) |decl| {
        \\            const decl_type = @TypeOf(@field(@This(), decl.name));
        \\            const decl_type_info = @typeInfo(decl_type);
        \\            if (decl_type_info == .pointer and @typeInfo(decl_type_info.pointer.child) == .@"fn") {
        \\                if (lib.lookup(decl_type, "wl_" ++ decl.name ++ "_interface")) |sym| {
        \\                    @field(@This(), decl.name) = sym;
        \\                } else {
        \\                    log.err("Failed to load wayland symbol: wl_{s}", .{decl.name});
        \\                    return error.SymbolLoadFailed;
        \\                }
        \\            }
        \\        }
        \\
        \\        try interfaces.load(lib);
        \\    }
        \\
        \\    const WL_MARSHAL_FLAG_DESTROY = (1 << 0);
        \\    const NULL: usize = 0;
        \\
        \\
    );

    generator.genInterfaceDefinitions(protocol);

    for (protocol.interfaces) |*interface| {
        try generator.genInterface(interface);
    }

    generator.append("};");

    return generator.buf.items;
}

fn genInterfaceDefinitions(this: *Generator, protocol: *const Protocol) void {
    this.append("    pub const interfaces = struct {\n");
    for (protocol.interfaces) |interface| {
        assert(std.mem.startsWith(u8, interface.name, "wl_"));
        const name = interface.name[3..];
        this.appendf("        pub const {f} :*const Interface = undefined;\n", .{std.zig.fmtId(name)});
    }
    this.append(
        \\
        \\        pub fn load(lib: *std.DynLib) !void {
        \\            inline for (@typeInfo(@This()).@"struct".decls) |decl| {
        \\                const decl_type = @TypeOf(@field(@This(), decl.name));
        \\                if (decl_type == *Interface) {
        \\                    if (lib.lookup(decl_type, "wl_" ++ decl.name ++ "_interface")) |sym| {
        \\                        @field(interfaces, decl.name) = sym;
        \\                    } else {
        \\                        log.err("Failed to load wayland symbol: wl_{s}", .{decl.name});
        \\                        return error.SymbolLoadFailed;
        \\                    }
        \\                }
        \\            }
        \\        }
        \\
    );
    this.append("    };\n\n");
}

fn genInterface(this: *Generator, interface: *const Interface) !void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    this.appendf("    pub const {s} = opaque {{\n", .{zigInterfaceName(tmp.allocator(), interface.name)});
    for (interface.enums) |*enm| {
        if (enm.bitfield) try this.genBitfield(interface.name, enm) else this.genEnum(interface.name, enm);
    }

    this.genImplicitRequests(interface);
    for (interface.requests, 0..) |*request, i| {
        this.genRequest(interface, request, i);
        if (i != interface.requests.len - 1) this.append("\n");
    }
    //
    // for (interface.events) |*event| this.genEvent(event);

    this.append("    };\n\n");
}

fn genEnum(this: *Generator, interface_name: []const u8, enm: *const Enum) void {
    var enum_type: []const u8 = "c_uint";
    for (enm.entries) |e| {
        if (std.mem.startsWith(u8, e.value_str, "-")) {
            enum_type = "c_int";
            break;
        }
    }

    this.appendf("        pub const {s}_{s} = enum({s}) {{\n", .{ interface_name, enm.name, enum_type });
    for (enm.entries) |entry| {
        this.appendf("            {f} = {s},\n", .{ std.zig.fmtId(entry.name), entry.value_str });
    }
    this.append("        };\n\n");
}

fn genBitfield(this: *Generator, interface_name: []const u8, enm: *const Enum) !void {
    this.appendf("        pub const {s}_{s} = packed struct(c_int) {{\n", .{ interface_name, enm.name });

    var ei: usize = 0;
    if (enm.entries.len > 1 and try parseEnumEntryValue(enm.entries[0].value_str) == 0) {
        ei = 1;
    }

    var bv: usize = 1;
    var pad_count: usize = 0;
    var pad_size: usize = 0;

    for (0..@sizeOf(c_int) * 8) |_| {
        if (ei < enm.entries.len) {
            var value_str = enm.entries[ei].value_str;
            var value = try parseEnumEntryValue(value_str);

            while (value < bv) {
                // Skip, emitted after
                ei += 1;
                if (ei >= enm.entries.len) break;
                value_str = enm.entries[ei].value_str;
                value = try parseEnumEntryValue(value_str);
            }

            if (value == bv) {
                if (pad_size > 0) {
                    this.appendf("            _pad{}: u{} = 0,\n", .{ pad_count, pad_size });
                    pad_count += 1;
                    pad_size = 0;
                }
                this.appendf("            {f}: bool = false, // {s}\n", .{ std.zig.fmtId(enm.entries[ei].name), value_str });
                enm.entries[ei].generated = true;
                ei += 1;
            } else {
                pad_size += 1;
            }
        } else {
            pad_size += 1;
        }

        bv *= 2;
    }

    if (pad_size > 0) {
        this.appendf("            _pad{}: u{} = 0,\n", .{ pad_count, pad_size });
        pad_count += 1;
        pad_size = 0;
    }

    for (enm.entries) |entry| {
        if (!entry.generated) {
            this.appendf("            pub const {s}: @This() = @bitCast({s});\n", .{ entry.name, entry.value_str });
        }
    }

    this.append("        };\n\n");
}

fn parseEnumEntryValue(value: []const u8) !c_uint {
    var base: u8 = 10;
    var str = value;
    if (std.mem.startsWith(u8, value, "0x")) {
        base = 16;
        str = value[2..];
    }
    return std.fmt.parseInt(c_uint, str, base);
}

fn genImplicitRequests(this: *Generator, interface: *const Interface) void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    const name = zigInterfaceName(tmp.allocator(), interface.name);

    this.appendf(
        \\        pub inline fn set_user_data(self: *{s}, user_data: *anyopaque) void {{
        \\            proxy_set_user_data(@ptrCast(self), user_data);
        \\        }}
        \\
        \\        pub inline fn get_user_data(self: *{s}) ?*anyopaque {{
        \\            return proxy_get_user_data(@ptrCast(self));
        \\        }}
        \\
        \\        pub inline fn get_version(self: *{s}) u32 {{
        \\            return proxy_get_version(@ptrCast(self));
        \\        }}
        \\
        \\
    , .{ name, name, name });

    // Another exception!
    if (std.mem.eql(u8, interface.name, "wl_callback")) {
        this.appendf(
            \\        pub inline fn destroy(self: *{s}) void {{
            \\            proxy_destroy(@ptrCast(self));
            \\        }}
            \\
            \\
        , .{name});
    }
}

fn genRequest(this: *Generator, interface: *const Interface, request: *const Request, index: usize) void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    this.appendf("        pub inline fn {s}(self: *{s}", .{ request.name, zigInterfaceName(tmp.allocator(), interface.name) });

    var constructor = false;
    var registry_bind = false;
    var constructor_interface: []const u8 = undefined;

    // wl_registry_bind is a special case!
    if (std.mem.eql(u8, interface.name, "wl_registry") and std.mem.eql(u8, request.name, "bind")) {
        registry_bind = true;
        this.append(", name: u32, interface: *const Interface, version: u32) *opaque {} {\n");
    } else {
        var return_type: []const u8 = "void";

        for (request.args) |arg| {
            if (arg.type == .new_id) {
                constructor_interface = arg.interface orelse interface.name;
                return_type = this.zigType(arg.type, constructor_interface);
                constructor = true;
            } else {
                this.appendf(", {s}: {s}", .{ arg.name, this.zigType(arg.type, arg.interface) });
            }
        }

        this.appendf(") {s} {{\n", .{return_type});
    }

    const opcode = index;

    if (constructor) {
        assert(std.mem.startsWith(u8, constructor_interface, "wl_"));
        const interface_def = tmpPrint(&tmp, "interfaces.{s}", .{constructor_interface[3..]});
        this.append("            const version = proxy_get_version(@ptrCast(self));\n");
        this.appendf("            const result = proxy_marshal_flags(@ptrCast(self), {}, {s}, version, 0, NULL", .{ opcode, interface_def });
        for (request.args[1..]) |arg| {
            this.appendf(", {s}", .{arg.name});
        }
        this.append(");\n");
        this.append("            return @ptrCast(result);\n");
    } else if (registry_bind) {
        this.appendf("            const result = proxy_marshal_flags(@ptrCast(self), {}, interface, version, 0, name, interface.name.ptr, version, NULL);\n", .{opcode});
        this.append("            return @ptrCast(result);\n");
    } else {
        this.append("            const version = proxy_get_version(@ptrCast(self));\n");
        const flags = if (request.destructor) "WL_MARSHAL_FLAG_DESTROY" else "0";
        const optional_null = if (request.args.len == 0 and !request.destructor) ", NULL" else "";
        this.appendf("            _ = proxy_marshal_flags(@ptrCast(self), {}, null, version, {s}{s}", .{ opcode, flags, optional_null });
        for (request.args) |arg| {
            this.appendf(", {s}", .{arg.name});
        }
        this.append(");\n");
    }
    this.append("        }\n");
}

fn genEvent(this: *Generator, event: *const Event) void {
    _ = this;
    _ = event;
    unreachable;
}

fn zigInterfaceName(allocator: Allocator, name_: []const u8) []const u8 {
    var result = std.ArrayList(u8){};
    const name = if (std.mem.startsWith(u8, name_, "wl_")) name_[3..] else name_;

    result.append(allocator, std.ascii.toUpper(name[0])) catch @panic("OOM");
    var cap_next = false;
    for (name[1..]) |c| {
        if (c == '_') {
            cap_next = true;
            continue;
        }

        if (cap_next) {
            result.append(allocator, std.ascii.toUpper(c)) catch @panic("OOM");
            cap_next = false;
        } else {
            result.append(allocator, c) catch @panic("OOM");
        }
    }

    return result.items;
}

fn zigType(this: *Generator, wl_type: Type, interface_name_opt: ?[]const u8) []const u8 {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    return switch (wl_type) {
        .int => "c_int",
        .uint => "c_uint",
        .fixed => unreachable,
        .string => "[*:0]const u8",
        .object, .new_id => {
            const interface_name = interface_name_opt orelse @panic("Expected interface name");
            const iname = zigInterfaceName(tmp.allocator(), interface_name);
            return tmpPrint(&tmp, "?*{s}", .{iname});
        },
        .array => unreachable,
        .fd => "c_int",
    };
}

inline fn append(this: *Generator, str: []const u8) void {
    return this.buf.appendSlice(this.allocator, str) catch @panic("OOM");
}

inline fn appendf(this: *Generator, comptime fmt: []const u8, args: anytype) void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();
    this.append(tmpPrint(&tmp, fmt, args));
}

inline fn tmpPrint(tmp: *mem.TempArena, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(tmp.allocator(), fmt, args) catch @panic("OOM");
}
