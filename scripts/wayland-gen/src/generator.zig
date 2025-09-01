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

    // generator.append("pub const ")
    generator.genInterfaceDefinitions(protocol);

    for (protocol.interfaces) |*interface| {
        try generator.genInterface(interface);
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
        \\
    );
    this.append("};\n\n");
}

fn genInterface(this: *Generator, interface: *const Interface) !void {
    for (interface.enums) |*enm| {
        if (enm.bitfield) try this.genBitfield(interface.name, enm) else this.genEnum(interface.name, enm);
    }

    // for (interface.requests) |*request| this.genRequest(request);
    // for (interface.events) |*event| this.genEvent(event);
}

fn genEnum(this: *Generator, interface_name: []const u8, enm: *const Enum) void {
    this.appendf("pub const {s}_{s} = enum {{\n", .{ interface_name, enm.name });
    for (enm.entries) |entry| {
        this.appendf("    {s} = {s},\n", .{ entry.name, entry.value_str });
    }
    this.append("};\n\n");
}

fn genBitfield(this: *Generator, interface_name: []const u8, enm: *const Enum) !void {
    this.appendf("pub const {s}_{s} = packed struct(c_int) {{\n", .{ interface_name, enm.name });

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
                    this.appendf("    _pad{}: u{} = 0,\n", .{ pad_count, pad_size });
                    pad_count += 1;
                    pad_size = 0;
                }
                this.appendf("    {s}: bool = false, // {s}\n", .{ enm.entries[ei].name, value_str });
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
        this.appendf("    _pad{}: u{} = 0,\n", .{ pad_count, pad_size });
        pad_count += 1;
        pad_size = 0;
    }

    for (enm.entries) |entry| {
        if (!entry.generated) {
            this.appendf("    pub const {s}: @This() = @bitCast({s});\n", .{ entry.name, entry.value_str });
        }
    }

    this.append("};\n\n");
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

inline fn append(this: *Generator, str: []const u8) void {
    return this.buf.appendSlice(this.allocator, str) catch @panic("OOM");
}

inline fn appendf(this: *Generator, comptime fmt: []const u8, args: anytype) void {
    var tmp = mem.getScratch(@ptrCast(@alignCast(this.allocator.ptr)));
    defer tmp.release();

    this.append(std.fmt.allocPrint(tmp.allocator(), fmt, args) catch @panic("OOM"));
}
