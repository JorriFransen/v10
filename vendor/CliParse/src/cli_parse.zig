const std = @import("std");
const log = std.log.scoped(.cli_parse);

const Allocator = std.mem.Allocator;

const CliParseError = error{};

pub fn parse(comptime OptionStructType: type, allocator: Allocator) CliParseError!OptionStructType {
    _ = allocator;

    checkOptionsType(OptionStructType);

    return .{};
}

fn checkOptionsType(comptime OptionStructType: type) void {
    const info = @typeInfo(OptionStructType);
    if (info != .@"struct") @compileError("OptionStructType must be a struct");

    const struct_info = info.@"struct";

    inline for (struct_info.fields) |field| {
        const field_info = @typeInfo(field.type);
        switch (field_info) {
            .@"enum" => {}, // ok
            else => {
                const err = std.fmt.comptimePrint("Invalid cli option type: '{s}' (for option: '{s}'), {s} not supported. Supported types are enum, bool, int, float.", .{
                    @typeName(field.type),
                    field.name,
                    @tagName(field_info),
                });
                @compileError(err);
            },
        }
    }
}
