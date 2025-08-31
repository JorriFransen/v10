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

pub fn generate(allocator: Allocator, protocol: *const Protocol) []const u8 {
    var generator = Generator{
        .allocator = allocator,
        .buf = std.ArrayList(u8){},
        .protocol = protocol,
    };

    generator.resolveEnumTypes();

    // generator.append("pub const ")
    generator.genInterfaceDefinitions(protocol);

    for (protocol.interfaces) |*interface| {
        generator.genInterface(interface);
    }

    return generator.buf.items;
}

fn genInterfaceDefinitions(this: *Generator, protocol: *const Protocol) void {
    this.append("const interfaces = struct {\n");
    for (protocol.interfaces) |interface| {
        this.appendf("    pub const {s} = undefined;\n", .{interface.name});
    }
    this.append(
        \\
        \\    pub fn load(lib: *std.DynLib) !void {
        \\        inline for (@typeInfo(@This()).@"struct".decls) |decl| {
        \\            const decl_type = @TypeOf(@field(@This(), decl.name));
        \\            if (decl_type == *wl.Interface) {
        \\                if (lib.lookup(decl_type, "wl_" ++ decl.name ++ "_interface")) |sym| {
        \\                    @field(interface, decl.name) = sym;
        \\                } else {
        \\                    log.err("Failed to load wayland symbol: wl_{s}", .{decl.name});
        \\                    return error.SymbolLoadFailed;
        \\                }
        \\            }
        \\        }
        \\    }
    );
    this.append("};\n");
}

fn genInterface(this: *Generator, interface: *const Interface) void {
    for (interface.enums) |*enm| {
        if (enm.bitfield) unreachable else this.genEnum(enm);
    }

    for (interface.requests) |*request| this.genRequest(request);
    for (interface.events) |*event| this.genEvent(event);
}

fn genEnum(this: *Generator, enm: *const Enum) void {
    log.debug("Generating enum: {s}", .{enm.name});
    const enum_type = enm.resolved_type orelse @panic("unresolved enum");
    this.appendf("pub const {s} = enum({}) {{\n", .{ enm.name, enum_type });
    this.append("};");
}

fn genRequest(this: *Generator, request: *const Request) void {
    _ = this;
    _ = request;
    unreachable;
}

fn genEvent(this: *Generator, event: *const Event) void {
    _ = this;
    _ = event;
    unreachable;
}

fn resolveEnumTypes(this: *Generator) void {
    _ = this;
    unreachable;
}

fn findEnum(this: *Generator, interface_name: []const u8, enum_name: []const u8) *Enum {
    for (this.protocol.interfaces) |interface| {
        if (std.mem.eql(u8, interface.name, interface_name)) {
            for (interface.enums) |*enm| {
                if (std.mem.eql(u8, enm.name, enum_name)) {
                    return enm;
                }
            }
        }
    }

    @panic("Unable to find enum");
}

inline fn append(this: *Generator, str: []const u8) void {
    return this.buf.appendSlice(this.allocator, str) catch @panic("OOM");
}

inline fn appendf(this: *Generator, comptime fmt: []const u8, args: anytype) void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    this.append(std.fmt.allocPrint(tmp.allocator(), fmt, args) catch @panic("OOM"));
}
