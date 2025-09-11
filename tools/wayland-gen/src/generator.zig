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

pub fn generate(allocator: Allocator, core_protocol: *const Protocol, protocols: []const Protocol) ![]const u8 {
    var generator = Generator{
        .allocator = allocator,
        .buf = std.ArrayList(u8){},
        .protocol = core_protocol,
    };

    generator.append(
        \\const std = @import("std");
        \\const log = std.log.scoped(.wayland);
        \\
        \\pub const wl = struct {
        \\
    );

    for (core_protocol.interfaces, 0..) |*interface, i| {
        try generator.genInterface(interface);
        if (i < core_protocol.interfaces.len - 1) generator.append("\n");
    }

    if (core_protocol.interfaces.len > 0) generator.append("\n");

    generator.append(
        \\    pub const EventQueue = opaque {};
        \\    pub const Proxy = opaque {};
        \\    pub const Timespec = opaque {};
        \\    pub const Object = opaque {};
        \\
        \\    pub var event_queue_destroy: *const fn (queue: *EventQueue) callconv(.c) void = undefined;
        \\    pub var proxy_marshal_flags: *const fn (proxy: *Proxy, opcode: u32, interface: ?*const Interface, version: u32, flags: u32, ...) callconv(.c) *Proxy = undefined;
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
        \\                if (lib.lookup(decl_type, "wl_" ++ decl.name)) |sym| {
        \\                    @field(@This(), decl.name) = sym;
        \\                } else {
        \\                    log.err("Failed to load wayland symbol: wl_{s}", .{decl.name});
        \\                    return error.SymbolLoadFailed;
        \\                }
        \\            }
        \\        }
        \\    }
        \\};
        \\
        \\
    );

    generator.append("pub const interfaces = struct {\n");
    generator.genInterfaceData(@as([*]const Protocol, @ptrCast(core_protocol))[0..1]);
    generator.genInterfaceData(protocols);
    generator.append("};\n");

    if (protocols.len > 0) generator.append("\n");

    for (protocols, 0..) |*protocol, i| {
        generator.appendf("pub const {s} = struct {{\n", .{protocol.name});
        for (protocol.interfaces, 0..) |*interface, ii| {
            try generator.genInterface(interface);
            if (ii < protocol.interfaces.len - 1) generator.append("\n");
        }
        generator.append("};\n");
        if (i < protocols.len - 1) generator.append("\n");
    }

    generator.append(
        \\
        \\const WL_MARSHAL_FLAG_DESTROY = (1 << 0);
        \\const NULL: usize = 0;
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
        \\pub const Array = extern struct {
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
    );

    return generator.buf.items;
}

fn genInterfaceData(this: *Generator, protocols: []const Protocol) void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    if (protocols.len > 0) this.append("\n");

    for (protocols) |*protocol| {
        for (protocol.interfaces) |*interface| {
            this.appendf(
                \\    pub const {s}: Interface = .{{
                \\        .name = "{s}",
                \\        .version = {},
                \\        .method_count = {},
                \\        .methods = &.{{
                \\
            , .{
                interface.name,
                interface.name,
                interface.version,
                interface.requests.len,
            });

            for (interface.requests) |*request| {
                this.appendf(
                    \\            .{{
                    \\                .name = "{s}",
                    \\                .signature = "
                , .{request.name});

                const registry_bind = (std.mem.eql(u8, interface.name, "wl_registry") and std.mem.eql(u8, request.name, "bind"));
                if (registry_bind) {
                    this.append("usun");
                } else {
                    this.genSignature(request.args);
                }

                this.append(
                    \\",
                    \\                .types =
                );

                if (registry_bind) {
                    this.append(
                        \\ &.{
                        \\                    null,
                        \\                    null,
                        \\                    null,
                        \\                    null,
                        \\                },
                    );
                } else {
                    this.genArgTypes(request.args, interface.name);
                }

                this.append(
                    \\
                    \\            },
                    \\
                );
            }

            this.append("        },\n");

            this.appendf(
                \\        .event_count = {},
                \\        .events = &.{{
                \\
            , .{interface.events.len});

            for (interface.events) |*event| {
                this.appendf(
                    \\            .{{
                    \\                .name = "{s}",
                    \\                .signature = "
                , .{event.name});

                this.genSignature(event.args);

                this.append(
                    \\",
                    \\                .types =
                );

                this.genArgTypes(event.args, interface.name);

                this.append("\n            },\n");
            }
            this.append("        },\n");

            this.append("    };\n");

            if (protocol.interfaces.len > 0) this.append("\n");
        }
    }
}

fn genSignature(this: *Generator, args: []const Arg) void {
    for (args) |arg| switch (arg.type) {
        .int => this.append("i"),
        .uint => this.append("u"),
        .fixed => this.append("f"),
        .string => this.append("s"),
        .object => this.append("o"),
        .new_id => this.append("n"),
        .array => this.append("a"),
        .fd => this.append("h"),
    };
}

fn genArgTypes(this: *Generator, args: []const Arg, interface_name: []const u8) void {
    if (args.len > 0) {
        this.append(" &.{\n");
        for (args) |arg| switch (arg.type) {
            else => this.append("                    null,\n"),
            .object, .new_id => {
                this.appendf("                    &{s},\n", .{arg.interface orelse interface_name});
            },
        };
        this.append("                },");
    } else {
        this.append(" null,");
    }
}

fn genInterface(this: *Generator, interface: *const Interface) !void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    this.appendf("    pub const {s} = opaque {{\n", .{zigInterfaceTypeName(&tmp, interface.name, interface)});
    this.appendf("        pub const interface: *const Interface = &interfaces.{s};\n", .{interface.name});
    if (interface.enums.len > 0 or interface.events.len > 0 or interface.requests.len > 0) this.append("\n");
    for (interface.enums, 0..) |*enm, i| {
        if (enm.bitfield) {
            try this.genBitfield(enm);
        } else {
            this.genEnum(enm);
        }
        if (i < interface.enums.len - 1) this.append("\n");
    }

    if (interface.enums.len > 0 and (interface.events.len > 0)) this.append("\n");

    if (interface.events.len > 0) try this.genListener(interface);

    if (interface.enums.len > 0 or (interface.events.len > 0)) this.append("\n");
    this.genImplicitRequests(interface);
    if (interface.requests.len > 0) this.append("\n");
    for (interface.requests, 0..) |*request, i| {
        this.genRequest(interface, request, i);
        if (i < interface.requests.len - 1) this.append("\n");
    }

    this.append("    };\n");
}

fn genEnum(this: *Generator, enm: *const Enum) void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    var enum_type: []const u8 = "c_uint";
    for (enm.entries) |e| {
        if (std.mem.startsWith(u8, e.value_str, "-")) {
            enum_type = "c_int";
            break;
        }
    }

    this.appendf("        pub const {s} = enum({s}) {{\n", .{ zigTypeName(&tmp, enm.name), enum_type });
    for (enm.entries) |entry| {
        this.appendf("            {f} = {s},\n", .{ std.zig.fmtId(entry.name), entry.value_str });
    }
    this.append("        };\n");
}

fn genBitfield(this: *Generator, enm: *const Enum) !void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    this.appendf("        pub const {s} = packed struct(u32) {{\n", .{zigTypeName(&tmp, enm.name)});

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

    this.append("        };\n");
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

    const name = zigInterfaceTypeName(&tmp, interface.name, interface);

    this.appendf(
        \\        pub inline fn set_user_data(self: *{s}, user_data: *anyopaque) void {{
        \\            wl.proxy_set_user_data(@ptrCast(self), user_data);
        \\        }}
        \\
        \\        pub inline fn get_user_data(self: *{s}) ?*anyopaque {{
        \\            return wl.proxy_get_user_data(@ptrCast(self));
        \\        }}
        \\
        \\        pub inline fn get_version(self: *{s}) u32 {{
        \\            return wl.proxy_get_version(@ptrCast(self));
        \\        }}
        \\
    , .{ name, name, name });

    // More exceptions!
    if (std.mem.eql(u8, interface.name, "wl_callback") or
        std.mem.eql(u8, interface.name, "wl_registry"))
    {
        this.appendf(
            \\        pub inline fn destroy(self: *{s}) void {{
            \\            wl.proxy_destroy(@ptrCast(self));
            \\        }}
            \\
        , .{name});
    }
}

fn genRequest(this: *Generator, interface: *const Interface, request: *const Request, index: usize) void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    this.genDocComment("        ", request.description);
    this.appendf("        pub inline fn {s}(self: *{s}", .{ request.name, zigInterfaceTypeName(&tmp, interface.name, interface) });

    var constructor = false;
    var registry_bind = false;
    var constructor_interface: []const u8 = undefined;

    // wl_registry_bind is a special case!
    if (std.mem.eql(u8, interface.name, "wl_registry") and std.mem.eql(u8, request.name, "bind")) {
        registry_bind = true;
        this.append(", name: u32, comptime IType: type, version: u32) ?*IType {\n");
    } else {
        var return_type: []const u8 = "void";

        for (request.args) |arg| {
            if (arg.type == .new_id) {
                constructor_interface = arg.interface orelse interface.name;
                return_type = zigType(&tmp, arg.type, constructor_interface, interface);
                constructor = true;
            } else {
                const arg_type = if (arg.enum_name) |ename|
                    zigEnumName(&tmp, ename, interface)
                else
                    zigType(&tmp, arg.type, arg.interface, interface);

                this.appendf(", {s}: {s}", .{ arg.name, arg_type });
            }
        }

        this.appendf(") {s} {{\n", .{return_type});
    }

    const opcode = index;

    if (constructor) {
        const interface_def = tmpPrint(&tmp, "{s}.interface", .{zigInterfaceTypeName(&tmp, constructor_interface, interface)});
        this.append("            const version = wl.proxy_get_version(@ptrCast(self));\n");
        this.appendf("            const result = wl.proxy_marshal_flags(@ptrCast(self), {}, {s}, version, 0, NULL", .{ opcode, interface_def });
        for (request.args) |arg| if (arg.type != .new_id) {
            if (arg.enum_name != null) {
                this.appendf(", @intFromEnum({s})", .{arg.name});
            } else {
                this.appendf(", {s}", .{arg.name});
            }
        };
        // for (request.args[1..]) |arg| {
        //     if (arg.enum_name != null) {
        //         this.appendf(", @intFromEnum({s})", .{arg.name});
        //     } else {
        //         this.appendf(", {s}", .{arg.name});
        //     }
        // }
        this.append(");\n");
        this.append("            return @ptrCast(result);\n");
    } else if (registry_bind) {
        this.appendf("            const result = wl.proxy_marshal_flags(@ptrCast(self), {}, IType.interface, version, 0, name, IType.interface.name, version, NULL);\n", .{opcode});
        this.append("            return @ptrCast(result);\n");
    } else {
        this.append("            const version = wl.proxy_get_version(@ptrCast(self));\n");
        const flags = if (request.destructor) "WL_MARSHAL_FLAG_DESTROY" else "0";
        const optional_null = if (request.args.len == 0 and !request.destructor) ", NULL" else "";
        this.appendf("            _ = wl.proxy_marshal_flags(@ptrCast(self), {}, null, version, {s}{s}", .{ opcode, flags, optional_null });
        for (request.args) |arg| {
            if (arg.enum_name != null) {
                this.appendf(", @intFromEnum({s})", .{arg.name});
            } else {
                this.appendf(", {s}", .{arg.name});
            }
        }
        this.append(");\n");
    }
    this.append("        }\n");
}

fn genListener(this: *Generator, interface: *const Interface) !void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    const iface_arg = std.zig.fmtId(zigInterfaceArgName(interface.name));
    const iface_type = zigInterfaceTypeName(&tmp, interface.name, interface);

    this.append("       pub const Listener = extern struct {\n");
    for (interface.events, 0..) |event, i| {
        this.genDocComment("            ", event.description);
        this.appendf("            {f}: ?*const fn (data: ?*anyopaque, {f}: ?*{s}", .{
            std.zig.fmtId(event.name),
            iface_arg,
            iface_type,
        });

        for (event.args) |arg| {
            this.appendf(", {f}: {s}", .{
                std.zig.fmtId(arg.name),
                if (arg.enum_name) |ename|
                    zigEnumName(&tmp, ename, interface)
                else
                    zigType(&tmp, arg.type, null, interface),
            });
        }

        this.append(") callconv(.c) void,\n");
        if (i < interface.events.len - 1) this.append("\n");
    }
    this.append("        };\n");

    this.appendf(
        \\
        \\        pub inline fn add_listener(self: *{s}, listener: *const Listener, data: ?*anyopaque) void {{
        \\            wl.proxy_add_listener(@ptrCast(self), @ptrCast(@constCast(listener)), data);
        \\        }}
        \\
    , .{iface_type});
}

fn zigEnumName(tmp: *mem.TempArena, name: []const u8, from_interface: *const Interface) []const u8 {
    const ta = tmp.allocator();
    var result = std.ArrayList(u8){};

    if (std.mem.indexOfScalar(u8, name, '.')) |idx| {
        result.appendSlice(ta, zigInterfaceTypeName(tmp, name[0..idx], from_interface)) catch @panic("OOM");
        result.append(ta, '.') catch @panic("OOM");
        result.appendSlice(ta, zigTypeName(tmp, name[idx + 1 ..])) catch @panic("OOM");
    } else {
        return zigTypeName(tmp, name);
    }

    return result.items;
}

fn zigTypeName(tmp: *mem.TempArena, name: []const u8) []const u8 {
    const ta = tmp.allocator();
    var result = std.ArrayList(u8){};

    result.append(ta, std.ascii.toUpper(name[0])) catch @panic("OOM");
    var cap_next = false;
    for (name[1..]) |c| {
        if (c == '_') {
            cap_next = true;
            continue;
        }

        if (cap_next) {
            result.append(ta, std.ascii.toUpper(c)) catch @panic("OOM");
            cap_next = false;
        } else {
            result.append(ta, c) catch @panic("OOM");
        }
    }

    return result.items;
}

fn zigInterfaceTypeName(tmp: *mem.TempArena, name_: []const u8, from_interface: *const Interface) []const u8 {
    const ta = tmp.allocator();
    var result = std.ArrayList(u8){};

    const idx = std.mem.indexOfScalar(u8, name_, '_') orelse @panic("Unexpected interface name format");
    assert(name_.len > idx);
    const prefix = name_[0..idx];
    const name = name_[idx + 1 ..];

    if (!std.mem.startsWith(u8, from_interface.name, prefix)) {
        result.appendSlice(ta, prefix) catch @panic("OOM");
        result.append(ta, '.') catch @panic("OOM");
    }

    result.append(ta, std.ascii.toUpper(name[0])) catch @panic("OOM");
    var cap_next = false;
    for (name[1..]) |c| {
        if (c == '_') {
            cap_next = true;
            continue;
        }

        if (cap_next) {
            result.append(ta, std.ascii.toUpper(c)) catch @panic("OOM");
            cap_next = false;
        } else {
            result.append(ta, c) catch @panic("OOM");
        }
    }

    return result.items;
}

fn zigInterfaceArgName(name_: []const u8) []const u8 {
    // strip prefix
    const idx = std.mem.indexOfScalar(u8, name_, '_') orelse @panic("Unexpected interface name format");
    assert(name_.len > idx);
    var name = name_[idx + 1 ..];

    // optionally strip version postfix
    if (std.mem.lastIndexOfScalar(u8, name, '_')) |last_idx| {
        if (name.len - 1 > last_idx + 1 and name[last_idx + 1] == 'v') {
            const version = name[last_idx + 2 ..];
            assert(version.len > 0);

            var is_version = true;
            for (version) |c| {
                if (!std.ascii.isDigit(c)) {
                    is_version = false;
                    break;
                }
            }

            if (is_version) {
                name = name[0 .. name.len - (version.len + 2)];
            }
        }
    }

    return name;
}

fn zigType(tmp: *mem.TempArena, wl_type: Type, interface_name_opt: ?[]const u8, from_interface: *const Interface) []const u8 {
    return switch (wl_type) {
        .int => "i32",
        .uint => "u32",
        .fixed => "Fixed",
        .string => "[*:0]const u8",
        .object, .new_id => blk: {
            if (interface_name_opt) |interface_name| {
                const iname = zigInterfaceTypeName(tmp, interface_name, from_interface);
                break :blk tmpPrint(tmp, "?*{s}", .{iname});
            } else if (std.mem.startsWith(u8, from_interface.name, "wl_")) {
                break :blk "?*Object";
            } else {
                break :blk "?*wl.Object";
            }
        },
        .array => "Array",
        .fd => "std.c.fd_t",
    };
}

fn genDocComment(this: *Generator, indent: []const u8, desc: []const u8) void {
    var it = std.mem.splitAny(u8, desc, &.{ '\r', '\n' });

    while (it.next()) |line| {
        this.appendf("{s}/// {s}\n", .{ indent, std.mem.trimStart(u8, line, &std.ascii.whitespace) });
    }
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
