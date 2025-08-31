const std = @import("std");
const types = @import("types.zig");

const Generator = @This();

const Protocol = types.Protocol;
const Interface = types.Interface;
const Request = types.Request;
const Event = types.Event;
const Enum = types.Enum;
const Arg = types.Arg;
const Type = types.Type;

pub fn generate(protocol: *Protocol) void {
    generateInterface(&protocol.interfaces[0]);
}

fn generateInterface(interface: *Interface) void {
    _ = interface;
    unreachable;
}
