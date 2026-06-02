const std = @import("std");
const log = std.log.scoped(.@"wayland-gen.generator");
const types = @import("types.zig");
const mem = @import("mem");
const options = @import("options");

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

const RegisteredSignature = struct {
    id: usize,
    types: []Type,
};

allocator: Allocator,
protocol: *const Protocol,
buf: std.ArrayList(u8),
interface_protocol_map: std.StringHashMapUnmanaged(*Protocol),
unique_signatures_map: std.StringHashMapUnmanaged(RegisteredSignature),
next_sig_index: usize = 0,

pub const Error =
    std.fmt.ParseIntError ||
    Allocator.Error ||
    error{ ProtocolCollision, InvalidEnumName };

pub fn generate(allocator: Allocator, core_protocol: *Protocol, protocols: []Protocol) Error![]const u8 {
    var generator = Generator{
        .allocator = allocator,
        .protocol = core_protocol,
        .buf = std.ArrayList(u8){ .items = &.{}, .capacity = 0 },
        .interface_protocol_map = std.StringHashMapUnmanaged(*Protocol){},
        .unique_signatures_map = std.StringHashMapUnmanaged(RegisteredSignature){},
    };

    for (core_protocol.interfaces) |i| {
        try generator.interface_protocol_map.put(allocator, i.name, core_protocol);
    }
    for (protocols) |*p| for (p.interfaces) |i| {
        const r = try generator.interface_protocol_map.getOrPut(allocator, i.name);
        if (r.found_existing) {
            if (!p.skip_generation and !r.value_ptr.*.skip_generation) {
                log.warn("Interface collision: '{s}.{s}' and '{s}.{s}'", .{ p.name, i.name, r.value_ptr.*.name, i.name });
            }

            if (std.mem.indexOf(u8, r.value_ptr.*.name, "unstable") != null) {
                if (!r.value_ptr.*.skip_generation) {
                    log.info("Using '{s}.{s}'. Skipping generation for '{s}'.", .{ p.name, i.name, r.value_ptr.*.name });
                }
                r.value_ptr.*.skip_generation = true;
                r.value_ptr.* = p;
            } else if (std.mem.indexOf(u8, p.name, "unstable") != null) {
                if (!p.skip_generation) {
                    log.info("Using '{s}.{s}'. Skipping generation for '{s}'.", .{ r.value_ptr.*.name, i.name, p.name });
                }
                p.skip_generation = true;
            } else {
                log.err("Unable to resolve collision", .{});
                return error.ProtocolCollision;
            }
        } else {
            r.value_ptr.* = p;
        }
    };

    try generator.matchEnumArgs(core_protocol);
    for (protocols) |*protocol| try generator.matchEnumArgs(protocol);

    try generator.appendf(
        \\const std = @import("std");
        \\const assert = std.debug.assert;
        \\const log = std.log.scoped(.wayland);
        \\const linux = @import("linux");
        \\const wlc = @import("wlc");
        \\const options = @import("options");
        \\
        \\pub const RegisteredListener = struct {{
        \\    user_data: ?*anyopaque,
        \\    node: std.SinglyLinkedList.Node = .{{}},
        \\    implementation: []const *const fn () void,
        \\}};
        \\
        \\pub const wl = {s};
        \\pub const {s} = struct {{
        \\
    , .{ core_protocol.name, core_protocol.name });

    for (core_protocol.interfaces, 0..) |*interface, i| {
        try generator.genInterface(core_protocol, interface);
        if (i < core_protocol.interfaces.len - 1) try generator.append("\n");
    }

    if (core_protocol.interfaces.len > 0) try generator.append("\n");

    try generator.append(
        \\    pub const Proxy = struct {
        \\        id: u32,
        \\        version: u32,
        \\        display: *Display,
        \\        interface: *const Interface,
        \\        freelist_node: std.SinglyLinkedList.Node = .{},
        \\        listeners: std.SinglyLinkedList = .{},
        \\    };
        \\
        \\    pub const Object = struct { proxy: Proxy };
        \\};
        \\
        \\
    );

    for (protocols, 0..) |*protocol, i| {
        if (!protocol.skip_generation) {
            try generator.appendf("pub const {s} = struct {{\n", .{protocol.name});
            for (protocol.interfaces, 0..) |*interface, ii| {
                try generator.genInterface(protocol, interface);
                if (ii < protocol.interfaces.len - 1) try generator.append("\n");
            }
            try generator.append("};\n");
            if (i < protocols.len - 1) try generator.append("\n");
        }
    }

    try generator.append(
        \\
        \\pub const Interface = struct {
        \\    name: []const u8,
        \\    version: u32,
        \\    methods: []const Message,
        \\    events: []const Message,
        \\
        \\    pub const Message = struct {
        \\        name: []const u8,
        \\        signature: []const ArgumentType,
        \\        signature_tag: Signature,
        \\    };
        \\
        \\};
        \\
        \\pub const Fixed = extern struct {
        \\    value: i32,
        \\
        \\    pub fn toDouble(fixed: Fixed) f64 {
        \\        return @as(f64, @floatFromInt(fixed.value)) / 256;
        \\    }
        \\
        \\    pub fn toInt(fixed: Fixed) c_int {
        \\        return @divTrunc(@as(c_int, @intCast(fixed.value)), 256);
        \\    }
        \\};
        \\
        \\pub const Array = []const u32;
        \\
        \\pub const ArgumentType = enum(u8) {
        \\    i,
        \\    u,
        \\    f,
        \\    s,
        \\    @"?s",
        \\    o,
        \\    @"?o",
        \\    n,
        \\    a,
        \\    h,
        \\};
        \\
        \\pub const Argument = union(ArgumentType) {
        \\    i: i32,
        \\    u: u32,
        \\    f: Fixed,
        \\    s: []const u8,
        \\    @"?s": ?[]const u8,
        \\    o: *wl.Object,
        \\    @"?o": ?*wl.Object,
        \\    n: u32,
        \\    a: Array,
        \\    h: i32,
        \\};
        \\
        \\pub const Signature = enum(u8) {
        \\
    );

    var it = generator.unique_signatures_map.iterator();
    while (it.next()) |entry| {
        try generator.appendf("    {f} = {},\n", .{ std.zig.fmtId(entry.key_ptr.*), entry.value_ptr.*.id });
    }

    try generator.append("};\n\n");

    var tmp = mem.getScratch(@ptrCast(@alignCast(generator.allocator.ptr)));
    it = generator.unique_signatures_map.iterator();
    while (it.next()) |entry| {
        const name = if (std.mem.eql(u8, entry.key_ptr.*, "_"))
            "trampoline_"
        else
            try tmpPrint(&tmp, "trampoline_{s}", .{entry.key_ptr.*});

        try generator.appendf("pub inline fn {f}(display: *wl.Display, object: *wl.Object, first_listener_node: ?*const std.SinglyLinkedList.Node, message: *const wlc.Message) u32 {{\n", .{std.zig.fmtId(name)});
        try generator.append("    _ = .{display};\n");

        const info = entry.value_ptr;
        var regular_arg_count: usize = 0;
        var fd_arg_count: usize = 0;
        try generator.append("    const HandlerType = *const fn (?*anyopaque, *wl.Proxy");
        for (info.types) |arg_type| {
            try generator.appendf(", {s}", .{try generator.zigType(&tmp, arg_type, null, null)});
            if (arg_type.tag == .fd) fd_arg_count += 1 else regular_arg_count += 1;
        }
        try generator.append(") void;\n");

        if (regular_arg_count > 0) try generator.append("    var arg_offset: usize = 0;\n");
        if (fd_arg_count > 0) try generator.append("    var fd_offset: usize = 0;\n");

        if (regular_arg_count > 0 or fd_arg_count > 0) try generator.append("\n");

        for (info.types, 1..) |arg_type, n| {
            try generator.appendf("    const arg{} = message.{s};\n", .{
                n,
                switch (arg_type.tag) {
                    .int => try tmpPrint(&tmp, "getIntArg(&arg_offset)", .{}),
                    .uint => try tmpPrint(&tmp, "getUIntArg(&arg_offset)", .{}),
                    .fixed => try tmpPrint(&tmp, "getFixedArg(&arg_offset)", .{}),
                    .string => try tmpPrint(&tmp, "getStringArg(&arg_offset)", .{}),
                    .array => try tmpPrint(&tmp, "getArrayArg(&arg_offset)", .{}),
                    .object => try tmpPrint(&tmp, "getObjectArg(&arg_offset, display)", .{}),
                    .new_id => try tmpPrint(&tmp, "getNewIdArg(&arg_offset, display, object.proxy.interface)", .{}),
                    .fd => try tmpPrint(&tmp, "getFDArg(&fd_offset)", .{}),
                },
            });
        }

        if (regular_arg_count > 0 or fd_arg_count > 0) try generator.append("\n");

        if (options.verbose_wayland) {
            try generator.append(
                \\    var print_buf: [1024]u8 = undefined;
                \\    var used: usize = 0;
                \\
                \\    const interface = object.proxy.interface;
                \\
                \\    var p = std.fmt.bufPrint(print_buf[used..], "<-   {s}.{s}(id = {}", .{
                \\        interface.name,
                \\        interface.events[message.header.op].name,
                \\        object.proxy.id,
                \\    }) catch unreachable;
                \\    used += p.len;
                \\
                \\
            );

            for (info.types, 1..) |arg_type, n| {
                try generator.append("    p = std.fmt.bufPrint(print_buf[used..], ");
                switch (arg_type.tag) {
                    .int, .uint => try generator.appendf("\", {{}}\", .{{ arg{} }})", .{n}),
                    .fixed => try generator.appendf("\", {{}}\", .{{ arg{}.toDouble() }})", .{n}),
                    .string => try generator.appendf("\", '{{s}}'\", .{{ arg{} }})", .{n}),
                    .object => try generator.appendf("\", o = {{}}\", .{{ if (arg{}) |a| a.proxy.id else 0 }})", .{n}),
                    .new_id => try generator.appendf("\", n = {{}}\", .{{ if (arg{}) |a| a.proxy.id else 0 }})", .{n}),
                    .array => try generator.appendf("\", {{any}}\", .{{ arg{} }})", .{n}),
                    .fd => try generator.appendf("\", h = {{}}\", .{{ arg{} }})", .{n}),
                }
                try generator.append(" catch unreachable;\n        used += p.len;\n");
            }

            try generator.append(
                \\    p = std.fmt.bufPrint(print_buf[used..], ")", .{}) catch unreachable;
                \\    used += p.len;
                \\
                \\    wlc.verbose("{s}", .{print_buf[0..used]});
                \\
                \\
            );
        }

        try generator.append(
            \\    var listener_count: u32 = 0;
            \\    var cnode = first_listener_node;
            \\
            \\    while (cnode) |node| {
            \\        const next = node.next;
            \\        const listener: *const RegisteredListener = @fieldParentPtr("node", node);
            \\        assert(message.header.op < listener.implementation.len);
            \\        const handler: HandlerType = @ptrCast(listener.implementation[message.header.op]);
            \\
            \\        listener_count += 1;
            \\        handler(listener.user_data, @ptrCast(object)
        );

        for (info.types, 1..) |arg_type, n| {
            const arg_name = try tmpPrint(&tmp, "arg{}", .{n});

            if (!arg_type.allow_null) {
                switch (arg_type.tag) {
                    .object, .new_id => try generator.appendf(", @ptrCast({s})", .{arg_name}),
                    else => try generator.appendf(", {s}", .{arg_name}),
                }
            } else {
                try generator.appendf(", {s}", .{arg_name});
            }
        }

        try generator.append(
            \\);
            \\        cnode = next;
            \\    }
            \\
            \\    return listener_count;
            \\}
            \\
        );

        tmp.release();
    }

    try generator.append(
        \\pub inline fn dispatch(display: *wl.Display, message: *const wlc.Message, object: *wl.Object) void {
        \\    const interface = object.proxy.interface;
        \\    const event = &interface.events[message.header.op];
        \\    const sig_tag = event.signature_tag;
        \\
        \\    const first_listener_node = object.proxy.listeners.first;
        \\
    );

    if (options.verbose_wayland) {
        try generator.append("\n    const listener_count = switch (sig_tag) {\n");
    } else {
        try generator.append(
            \\    if (first_listener_node == null) return;
            \\
            \\    _ = switch (sig_tag) {
            \\
        );
    }

    it = generator.unique_signatures_map.iterator();
    while (it.next()) |entry| {
        const enum_name = std.zig.fmtId(entry.key_ptr.*);
        const trampoline_name = std.zig.fmtId(try tmpPrint(&tmp, "trampoline_{s}", .{if (std.mem.eql(u8, entry.key_ptr.*, "_")) "" else entry.key_ptr.*}));
        try generator.appendf("        .{f} => {f}(display, object, first_listener_node, message),\n", .{ enum_name, trampoline_name });
    }
    try generator.append("    };\n");

    if (options.verbose_wayland) {
        try generator.append(
            \\
            \\    wlc.verbose("     {s}.{s}(id = {}) listeners = {}", .{
            \\        interface.name,
            \\        interface.events[message.header.op].name,
            \\        object.proxy.id,
            \\        listener_count,
            \\    });
            \\
        );
    }

    try generator.append("}\n");

    return generator.buf.items;
}

fn matchEnumArgs(this: *Generator, protocol: *const Protocol) Error!void {
    for (protocol.interfaces) |*interface| {
        for (interface.requests) |*request| {
            for (request.args) |*arg| {
                try this.matchEnumArg(protocol, interface, arg);
            }
        }

        for (interface.events) |*event| {
            for (event.args) |*arg| {
                try this.matchEnumArg(protocol, interface, arg);
            }
        }
    }
}

fn matchEnumArg(this: *Generator, protocol: *const Protocol, interface: *const Interface, arg: *Arg) Error!void {
    _ = this;

    if (arg.enum_name) |fullname| {
        var enum_interface: *const Interface = undefined;
        var enum_name: []const u8 = undefined;

        if (std.mem.findScalar(u8, fullname, '.')) |dot_idx| {
            const interface_name = fullname[0..dot_idx];
            enum_name = fullname[dot_idx + 1 ..];

            enum_interface = for (protocol.interfaces) |*iface| {
                if (std.mem.eql(u8, iface.name, interface_name)) {
                    break iface;
                }
            } else {
                return error.InvalidEnumName;
            };
        } else {
            enum_interface = interface;
            enum_name = fullname;
        }

        var found = false;
        for (enum_interface.enums) |*enum_type| {
            if (std.mem.eql(u8, enum_type.name, enum_name)) {
                found = true;

                arg.enum_type = enum_type;
            }
        }
        if (!found) {
            log.err("Failed to find enum type: {s}", .{fullname});
            @panic("Failed to find enum type");
        }
    }
}

fn genInterfaceData(this: *Generator, protocol: *const Protocol, interface: *const Interface) Error!void {
    _ = protocol;
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    try this.appendf(
        \\        pub const interface: Interface = .{{
        \\            .name = "{s}",
        \\            .version = {},
        \\            .methods = &.{{
    , .{
        interface.name,
        interface.version,
    });

    for (interface.requests, 0..) |*request, i| {
        if (i > 0) try this.append(",");
        try this.appendf(
            \\ .{{
            \\                .name = "{s}",
            \\                .signature = &.{{
        , .{request.name});

        const registry_bind = (std.mem.eql(u8, interface.name, "wl_registry") and std.mem.eql(u8, request.name, "bind"));
        const tag = if (registry_bind) blk: {
            try this.append(" .u, .s, .u, .n");
            break :blk try this.registerSignature("usun");
        } else try this.genSignature(request.args);

        try this.appendf(" }},\n                .signature_tag = .{f},\n            }}", .{std.zig.fmtId(tag)});
    }

    try this.append(
        \\ },
        \\            .events = &.{
    );

    for (interface.events, 0..) |*event, i| {
        if (i > 0) try this.append(",");
        try this.appendf(
            \\ .{{
            \\                .name = "{s}",
            \\                .signature = &.{{
        , .{event.name});

        const tag = try this.genSignature(event.args);
        try this.appendf(" }},\n               .signature_tag = .{f},\n            }}", .{std.zig.fmtId(tag)});
    }
    try this.append(
        \\ },
        \\        };
        \\
    );
}

fn genSignature(this: *Generator, args: []const Arg) Allocator.Error![]const u8 {
    var str_buf: [64]u8 = undefined;
    var str_used: usize = 0;

    for (args, 0..) |arg, i| {
        if (i > 0) try this.append(", ") else try this.append(" ");

        if (arg.type.allow_null) {
            switch (arg.type.tag) {
                .object => {
                    try this.append(".@\"?o\"");
                    str_buf[str_used] = '?';
                    str_buf[str_used + 1] = 'o';
                },
                .string => {
                    try this.append(".@\"?s\"");
                    str_buf[str_used] = '?';
                    str_buf[str_used + 1] = 's';
                },
                else => {
                    log.warn("Unexpected nullable type: {}", .{arg.type});
                    @panic("Unexpected nullable type");
                },
            }

            str_used += 2;
        } else {
            switch (arg.type.tag) {
                .int => {
                    try this.append(".i");
                    str_buf[str_used] = 'i';
                },
                .uint => {
                    try this.append(".u");
                    str_buf[str_used] = 'u';
                },
                .fixed => {
                    try this.append(".f");
                    str_buf[str_used] = 'f';
                },
                .string => {
                    try this.append(".s");
                    str_buf[str_used] = 's';
                },
                .object => {
                    try this.append(".o");
                    str_buf[str_used] = 'o';
                },
                .new_id => {
                    try this.append(".n");
                    str_buf[str_used] = 'n';
                },
                .array => {
                    try this.append(".a");
                    str_buf[str_used] = 'a';
                },
                .fd => {
                    try this.append(".h");
                    str_buf[str_used] = 'h';
                },
            }
            str_used += 1;
        }
    }

    return try this.registerSignature(str_buf[0..str_used]);
}

fn registerSignature(this: *Generator, sig_: []const u8) ![]const u8 {
    const sig = if (sig_.len > 0) sig_ else "_";

    var result: []const u8 = "";

    // Don't use getOrPut to avoid duplicate copies
    if (this.unique_signatures_map.getEntry(sig)) |entry| {
        result = entry.key_ptr.*;
    } else {
        result = try this.allocator.dupe(u8, sig);
        const sig_types = try this.allocator.alloc(Type, sig_.len);
        var ti: usize = 0;

        var next_nullable = false;
        for (sig_) |sig_char| {
            const nullable = next_nullable;
            next_nullable = false;

            switch (sig_char) {
                'u' => sig_types[ti] = .{ .tag = .uint, .allow_null = nullable },
                'i' => sig_types[ti] = .{ .tag = .int, .allow_null = nullable },
                'f' => sig_types[ti] = .{ .tag = .fixed, .allow_null = nullable },
                'n' => sig_types[ti] = .{ .tag = .new_id, .allow_null = nullable },
                'o' => sig_types[ti] = .{ .tag = .object, .allow_null = nullable },
                'h' => sig_types[ti] = .{ .tag = .fd, .allow_null = nullable },
                's' => sig_types[ti] = .{ .tag = .string, .allow_null = nullable },
                'a' => sig_types[ti] = .{ .tag = .array, .allow_null = nullable },
                '?' => {
                    next_nullable = true;
                },
                else => {
                    log.warn("Unhandled signature char: {c}", .{sig_char});
                    unreachable;
                },
            }

            if (!next_nullable) {
                ti += 1;
            }
        }

        try this.unique_signatures_map.put(this.allocator, result, .{ .id = this.next_sig_index, .types = sig_types[0..ti] });
        this.next_sig_index += 1;
    }

    return result;
}

fn genInterface(this: *Generator, protocol: *const Protocol, interface: *const Interface) Error!void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();
    const ta = tmp.allocator();

    try this.appendf("    pub const {s} = struct {{\n", .{try this.zigInterfaceTypeName(&tmp, protocol, interface.name)});
    if (std.mem.eql(u8, interface.name, "wl_display")) {
        try this.append("        /// Read-only!\n");
    }
    try this.append("        proxy: wl.Proxy,\n");
    if (std.mem.eql(u8, interface.name, "wl_display")) {
        try this.append(
            \\        fd: linux.fd_t,
            \\
            \\        objects: [64]Object = undefined,
            \\        free_objects: std.SinglyLinkedList = .{},
            \\
            \\        server_object_ids: [16]u32 = undefined,
            \\        server_objects: [16]Object = undefined,
            \\
            \\        listeners: [32]RegisteredListener = std.mem.zeroes([32]RegisteredListener),
            \\        free_listeners: std.SinglyLinkedList = .{},
            \\
            \\        send_payload_used: usize = 0,
            \\        send_payload_buf: [2048]u8 = undefined,
            \\        send_fds_used: usize = 0,
            \\        send_fds_buf: [32]linux.fd_t = undefined,
            \\
            \\        receive_payload_used: usize = 0,
            \\        receive_payload_buf: [4096]u8 = undefined,
            \\        receive_fds_used: usize = 0,
            \\        receive_fds_buf: [32]linux.fd_t = undefined,
            \\
            \\
        );
    }

    try this.genInterfaceData(protocol, interface);

    if (interface.enums.len > 0 or interface.events.len > 0 or interface.requests.len > 0) try this.append("\n");
    for (interface.enums, 0..) |*enm, i| {
        if (enm.bitfield) {
            try this.genBitfield(enm);
        } else {
            try this.genEnum(enm);
        }
        if (i < interface.enums.len - 1) try this.append("\n");
    }

    if (interface.enums.len > 0 and (interface.events.len > 0)) try this.append("\n");

    if (interface.events.len > 0) try this.genListener(protocol, interface);

    if (interface.enums.len > 0 or (interface.events.len > 0)) try this.append("\n");
    try this.genImplicitRequests(protocol, interface);
    if (interface.requests.len > 0) try this.append("\n");

    var fn_names = std.StringHashMapUnmanaged(void){};
    try fn_names.ensureTotalCapacity(ta, @intCast(interface.requests.len));
    for (interface.requests) |r| try fn_names.putNoClobber(ta, r.name, {});

    for (interface.requests, 0..) |*request, i| {
        try this.genRequest(protocol, interface, request, i, &fn_names);
        if (i < interface.requests.len - 1) try this.append("\n");
    }

    try this.append("    };\n");
}

fn genEnum(this: *Generator, enm: *const Enum) Allocator.Error!void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    var enum_type: []const u8 = "c_uint";
    for (enm.entries) |e| {
        if (std.mem.startsWith(u8, e.value_str, "-")) {
            enum_type = "c_int";
            break;
        }
    }

    try this.appendf("        pub const {s} = enum({s}) {{\n", .{ try zigTypeName(&tmp, enm.name), enum_type });
    for (enm.entries) |entry| {
        try this.appendf("            {f} = {s},\n", .{ std.zig.fmtId(entry.name), entry.value_str });
    }
    try this.append("        };\n");
}

fn genBitfield(this: *Generator, enm: *const Enum) Error!void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    try this.appendf("        pub const {s} = packed struct(u32) {{\n", .{try zigTypeName(&tmp, enm.name)});

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
                    try this.appendf("            _pad{}: u{} = 0,\n", .{ pad_count, pad_size });
                    pad_count += 1;
                    pad_size = 0;
                }
                try this.appendf("            {f}: bool = false, // {s}\n", .{ std.zig.fmtId(enm.entries[ei].name), value_str });
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
        try this.appendf("            _pad{}: u{} = 0,\n", .{ pad_count, pad_size });
        pad_count += 1;
        pad_size = 0;
    }

    for (enm.entries) |entry| {
        if (!entry.generated) {
            try this.appendf("            pub const {s}: @This() = @bitCast({s});\n", .{ entry.name, entry.value_str });
        }
    }

    try this.append("        };\n");
}

fn parseEnumEntryValue(value: []const u8) Error!c_uint {
    var base: u8 = 10;
    var str = value;
    if (std.mem.startsWith(u8, value, "0x")) {
        base = 16;
        str = value[2..];
    }
    return try std.fmt.parseInt(c_uint, str, base);
}

fn genImplicitRequests(this: *Generator, protocol: *const Protocol, interface: *const Interface) Error!void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    const name = try this.zigInterfaceTypeName(&tmp, protocol, interface.name);

    try this.appendf(
        \\        pub inline fn getVersion(self: *{s}) u32 {{
        \\            return self.proxy.version;
        \\        }}
        \\
    , .{name});

    if (!interface.has_destructor and !std.mem.eql(u8, interface.name, "wl_callback")) {
        try this.appendf(
            \\        pub inline fn destroy(self: *{s}) void {{
            \\            wlc.proxyDestroy(@ptrCast(self));
            \\        }}
            \\
        , .{name});
    }
}

fn genRequest(this: *Generator, protocol: *const Protocol, interface: *const Interface, request: *const Request, index: usize, fn_names: *std.StringHashMapUnmanaged(void)) Error!void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    try this.genDocComment("        ", request.description);
    try this.appendf("        pub inline fn {f}(self: *{s}", .{
        std.zig.fmtId(try zigFunctionName(&tmp, request.name)),
        try this.zigInterfaceTypeName(&tmp, protocol, interface.name),
    });

    var constructor = false;
    var registry_bind = false;
    var wl_data_offer_destroy = false;
    var constructor_interface: []const u8 = undefined;

    // wl_registry_bind is a special case!
    if (std.mem.eql(u8, interface.name, "wl_registry") and std.mem.eql(u8, request.name, "bind")) {
        registry_bind = true;
        try this.append(", name: u32, comptime IType: type, version: u32) ?*IType {\n");
    } else if (std.mem.eql(u8, interface.name, "wl_data_offer") and std.mem.eql(u8, request.name, "destroy")) {
        wl_data_offer_destroy = true;
        try this.append(") void {\n");
    } else {
        var return_type: []const u8 = "void";

        for (request.args) |arg| {
            if (arg.type.tag == .new_id) {
                constructor_interface = arg.interface orelse interface.name;
                return_type = try this.zigType(&tmp, arg.type, constructor_interface, protocol);
                constructor = true;
            } else {
                const arg_type = if (arg.enum_name) |ename|
                    try this.zigEnumName(&tmp, ename, protocol)
                else
                    try this.zigType(&tmp, arg.type, arg.interface, protocol);

                try this.appendf(", {s}: {s}", .{ try safeArgName(&tmp, fn_names, arg.name), arg_type });
            }
        }

        try this.appendf(") {s} {{\n", .{return_type});
    }

    const opcode = index;

    if (constructor) {
        const interface_def = try tmpPrint(&tmp, "&{s}.interface", .{try this.zigInterfaceTypeName(&tmp, protocol, constructor_interface)});
        try this.appendf(
            \\            const result = wlc.proxyMarshalArrayFlags(@ptrCast(self), {}, {s}, self.proxy.version, &.{{
            \\                .{{ .n = 0 }},
            \\
        , .{ opcode, interface_def });
        for (request.args) |arg| if (arg.type.tag != .new_id) {
            try this.appendf("                {s},\n", .{try makeArg(&tmp, fn_names, arg)});
        };
        try this.append("            });\n");
        try this.append("            return @ptrCast(result);\n");
    } else if (registry_bind) {
        try this.appendf(
            \\            const result = wlc.proxyMarshalArrayFlags(@ptrCast(self), {}, &IType.interface, version, &.{{
            \\                .{{ .u = name }},
            \\                .{{ .s = IType.interface.name }},
            \\                .{{ .u = version }},
            \\                .{{ .n = 0 }},
            \\            }});
            \\
        , .{opcode});
        try this.append("            return @ptrCast(result);\n");
    } else {
        try this.appendf("            _ = wlc.proxyMarshalArrayFlags(@ptrCast(self), {}, null, self.proxy.version, &.{{", .{opcode});
        if (request.args.len != 0) try this.append("\n");
        for (request.args) |arg| {
            try this.appendf("                {s},\n", .{try makeArg(&tmp, fn_names, arg)});
        }

        if (request.args.len != 0) try this.append("             ");
        try this.append("});\n");

        if (wl_data_offer_destroy) {
            try this.append("            wlc.proxyDestroy(@ptrCast(self));\n");
        }
    }
    try this.append("        }\n");
}

fn makeArg(tmp: *mem.TempArena, fn_names: *std.StringHashMapUnmanaged(void), arg: Arg) ![]const u8 {
    const t: []const u8 = if (arg.type.allow_null) switch (arg.type.tag) {
        // .int => 'i',
        // .uint => 'u',
        // .fixed => 'f',
        .string => "?s",
        .object => "?o",
        .new_id => "?n",
        // .array => 'a',
        // .fd => 'h',
        else => @panic("Unexpected optional type"),
    } else switch (arg.type.tag) {
        .int => "i",
        .uint => "u",
        .fixed => "f",
        .string => "s",
        .object => "o",
        .new_id => "n",
        .array => "a",
        .fd => "h",
    };

    const name = try safeArgName(tmp, fn_names, arg.name);

    const arg_str = if (arg.enum_name) |_|
        if (arg.enum_type.?.bitfield)
            try tmpPrint(tmp, "@bitCast({s})", .{name})
        else
            try tmpPrint(tmp, "@intFromEnum({s})", .{name})
    else if (arg.type.tag == .object)
        try tmpPrint(tmp, "@ptrCast({s})", .{name})
    else
        name;

    return try tmpPrint(tmp, ".{{ .{f} = {s} }}", .{ std.zig.fmtId(t), arg_str });
}

fn safeArgName(tmp: *mem.TempArena, fn_names: *std.StringHashMapUnmanaged(void), name: []const u8) Allocator.Error![]const u8 {
    if (fn_names.contains(name)) {
        return try tmpPrint(tmp, "{s}_arg", .{name});
    }

    return name;
}

fn genListener(this: *Generator, protocol: *const Protocol, interface: *const Interface) Error!void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    const iface_arg = std.zig.fmtId(zigInterfaceArgName(interface.name));
    const iface_type = try this.zigInterfaceTypeName(&tmp, protocol, interface.name);

    try this.append("        pub const Listener = extern struct {\n");
    for (interface.events, 0..) |event, i| {
        try this.genDocComment("            ", event.description);
        try this.appendf("            {f}: ?*const fn (data: ?*anyopaque, {f}: *{s}", .{
            std.zig.fmtId(try zigFunctionName(&tmp, event.name)),
            iface_arg,
            iface_type,
        });

        for (event.args) |arg| {
            try this.appendf(", {f}: {s}", .{
                std.zig.fmtId(arg.name),
                if (arg.enum_name) |ename|
                    try this.zigEnumName(&tmp, ename, protocol)
                else
                    try this.zigType(&tmp, arg.type, null, protocol),
            });
        }

        try this.append(")  void,\n");
        if (i < interface.events.len - 1) try this.append("\n");
    }
    try this.append("        };\n");

    try this.appendf(
        \\
        \\        pub inline fn addListener(self: *{s}, listener: *const Listener, data: ?*anyopaque) void {{
        \\            wlc.proxyAddListener(@ptrCast(self), @ptrCast(listener), data);
        \\        }}
        \\
    , .{iface_type});
}

fn zigEnumName(this: *Generator, tmp: *mem.TempArena, name: []const u8, protocol: *const Protocol) Allocator.Error![]const u8 {
    const ta = tmp.allocator();
    var result = std.ArrayList(u8){ .items = &.{}, .capacity = 0 };

    if (std.mem.indexOfScalar(u8, name, '.')) |idx| {
        const enum_interface = name[0..idx];
        try result.appendSlice(ta, try this.zigInterfaceTypeName(tmp, protocol, enum_interface));
        try result.append(ta, '.');
        try result.appendSlice(ta, try zigTypeName(tmp, name[idx + 1 ..]));
    } else {
        return try zigTypeName(tmp, name);
    }

    return result.items;
}

fn zigFunctionName(tmp: *mem.TempArena, name: []const u8) Allocator.Error![]const u8 {
    const ta = tmp.allocator();
    var result = std.ArrayList(u8){ .items = &.{}, .capacity = 0 };

    try result.append(ta, name[0]);

    var cap_next = false;
    for (name[1..]) |c| {
        if (c == '_') {
            cap_next = true;
            continue;
        }

        if (cap_next) {
            try result.append(ta, std.ascii.toUpper(c));
            cap_next = false;
        } else {
            try result.append(ta, c);
        }
    }

    return result.items;
}

fn zigTypeName(tmp: *mem.TempArena, name: []const u8) Allocator.Error![]const u8 {
    const ta = tmp.allocator();
    var result = std.ArrayList(u8){ .items = &.{}, .capacity = 0 };

    try result.append(ta, std.ascii.toUpper(name[0]));
    var cap_next = false;
    for (name[1..]) |c| {
        if (c == '_') {
            cap_next = true;
            continue;
        }

        if (cap_next) {
            try result.append(ta, std.ascii.toUpper(c));
            cap_next = false;
        } else {
            try result.append(ta, c);
        }
    }

    return result.items;
}

/// in_protocol is the protocol where this name will be used.
fn zigInterfaceTypeName(this: *Generator, tmp: *mem.TempArena, in_protocol: *const Protocol, interface_name: []const u8) Allocator.Error![]const u8 {
    const ta = tmp.allocator();
    var result = std.ArrayList(u8){ .items = &.{}, .capacity = 0 };

    const interface_protocol = this.interface_protocol_map.get(interface_name).?;
    if ((in_protocol != interface_protocol) and
        !(std.mem.eql(u8, in_protocol.name, "wayland") and std.mem.eql(u8, interface_protocol.name, "wl")))
    {
        try result.appendSlice(ta, interface_protocol.name);
        try result.append(ta, '.');
    }

    const idx = std.mem.indexOfScalar(u8, interface_name, '_') orelse @panic("Unexpected interface name format");
    assert(interface_name.len > idx);
    const name = interface_name[idx + 1 ..];

    try result.append(ta, std.ascii.toUpper(name[0]));
    var cap_next = false;
    for (name[1..]) |c| {
        if (c == '_') {
            cap_next = true;
            continue;
        }

        if (cap_next) {
            try result.append(ta, std.ascii.toUpper(c));
            cap_next = false;
        } else {
            try result.append(ta, c);
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

fn zigType(this: *Generator, tmp: *mem.TempArena, wl_type: Type, interface_name_opt: ?[]const u8, protocol: ?*const Protocol) Allocator.Error![]const u8 {
    const prefix = if (wl_type.allow_null) "?" else "";
    const type_str = switch (wl_type.tag) {
        .int => "i32",
        .uint => "u32",
        .fixed => "Fixed",
        .string => "[]const u8",
        .object, .new_id => blk: {
            if (interface_name_opt) |interface_name| {
                const iname = try this.zigInterfaceTypeName(tmp, protocol.?, interface_name);
                break :blk try tmpPrint(tmp, "*{s}", .{iname});
            } else if (protocol != null and std.mem.eql(u8, protocol.?.name, "wayland")) {
                break :blk "*Object";
            } else {
                break :blk "*wl.Object";
            }
        },
        .array => "Array",
        .fd => "linux.fd_t",
    };

    return try tmpPrint(tmp, "{s}{s}", .{ prefix, type_str });
}

fn genDocComment(this: *Generator, indent: []const u8, desc: []const u8) Allocator.Error!void {
    var it = std.mem.splitAny(u8, desc, &.{ '\r', '\n' });

    while (it.next()) |line| {
        const trimmed = std.mem.trimStart(u8, line, &std.ascii.whitespace);
        try this.appendf("{s}///{s}{s}\n", .{
            indent,
            if (trimmed.len > 0) " " else "",
            trimmed,
        });
    }
}

inline fn append(this: *Generator, str: []const u8) Allocator.Error!void {
    return try this.buf.appendSlice(this.allocator, str);
}

inline fn appendf(this: *Generator, comptime fmt: []const u8, args: anytype) Allocator.Error!void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();
    try this.append(try tmpPrint(&tmp, fmt, args));
}

inline fn tmpPrint(tmp: *mem.TempArena, comptime fmt: []const u8, args: anytype) Allocator.Error![]const u8 {
    return try std.fmt.allocPrint(tmp.allocator(), fmt, args);
}
