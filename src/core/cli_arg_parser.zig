const std = @import("std");
const log = std.log.scoped(.cli_arg_parse);
const Allocator = std.mem.Allocator;

const core = @import("core.zig");
const assert = @import("assert.zig").assert;

const String = struct {
    slice: []const u8,
};

/// Defines a command line option.
/// All supported types have dedicated constructor functions.
pub const OptionDefinition = struct {
    /// Long option name, without leading dashes.
    /// Must be a valid zig identifier.
    /// Used as field name in the parsed result ('Options' struct).
    name: []const u8,

    /// Optional short option alias.
    short_name_opt: ?u8,

    /// Type used for parser generation/parsing.
    Type: type,

    /// Type of the field in the parsed result ('Options' struct).
    OptionType: type,

    default_value_ptr: *const anyopaque,

    /// Optional description
    desc_opt: ?[]const u8,

    fn def(comptime T: type, comptime OT: type, default: OT, name: []const u8, short_opt: ?u8, desc_opt: ?[]const u8) OptionDefinition {
        return .{
            .name = name,
            .short_name_opt = short_opt,
            .Type = T,
            .OptionType = OT,
            .default_value_ptr = @ptrCast(&default),
            .desc_opt = desc_opt,
        };
    }

    /// Define a boolean option.
    pub fn @"bool"(comptime default: bool, name: []const u8, short_opt: ?u8, desc_opt: ?[]const u8) OptionDefinition {
        return def(bool, bool, default, name, short_opt, desc_opt);
    }

    /// Define a string option.
    pub fn string(comptime default: []const u8, name: []const u8, short_opt: ?u8, desc_opt: ?[]const u8) OptionDefinition {
        return def(String, []const u8, default, name, short_opt, desc_opt);
    }

    /// Define an integer option.
    pub fn int(comptime T: type, default: T, name: []const u8, short_opt: ?u8, desc_opt: ?[]const u8) OptionDefinition {
        core.meta.expectIntType(T);
        return def(T, T, default, name, short_opt, desc_opt);
    }

    /// Define a float option.
    pub fn float(comptime T: type, default: T, name: []const u8, short_opt: ?u8, desc_opt: ?[]const u8) OptionDefinition {
        core.meta.expectFloatType(T);
        return def(T, T, default, name, short_opt, desc_opt);
    }

    /// Define an enum option.
    pub fn @"enum"(comptime T: type, default: T, name: []const u8, short_opt: ?u8, desc_opt: ?[]const u8) OptionDefinition {
        core.meta.expectEnumType(T);
        return def(T, T, default, name, short_opt, desc_opt);
    }

    /// Define a string array option.
    pub fn stringArray(default: []const []const u8, name: []const u8, short_opt: ?u8, desc_opt: ?[]const u8) OptionDefinition {
        return def([]const String, []const []const u8, default, name, short_opt, desc_opt);
    }

    /// Define an integer array option.
    pub fn intArray(comptime Elem: type, default: []const Elem, name: []const u8, short_opt: ?u8, desc_opt: ?[]const u8) OptionDefinition {
        core.meta.expectIntType(Elem);
        return def([]const Elem, []const Elem, default, name, short_opt, desc_opt);
    }

    /// Define a float array option
    pub fn floatArray(comptime Elem: type, default: []const Elem, name: []const u8, short_opt: ?u8, desc_opt: ?[]const u8) OptionDefinition {
        core.meta.expectFloatType(Elem);
        return def([]const Elem, []const Elem, default, name, short_opt, desc_opt);
    }

    /// Define an enum array option
    pub fn enumArray(comptime Elem: type, default: []const Elem, name: []const u8, short_opt: ?u8, desc_opt: ?[]const u8) OptionDefinition {
        core.meta.expectEnumType(Elem);
        return def([]const Elem, []const Elem, default, name, short_opt, desc_opt);
    }

    inline fn defaultValue(comptime this: *const OptionDefinition) this.Type {
        const dp: *const this.Type = @ptrCast(@alignCast(this.default_value_ptr));
        return dp.*;
    }
};

/// Comptime parser configuration
pub const ParserConfig = struct {
    /// Optional additional label to be printed in usage().
    usage_positionals_label_opt: ?[]const u8 = null,

    /// Enforced minimal positional count
    min_positionals: usize = 0,
    /// Optional enforced maximal positional count
    max_positionals_opt: ?usize = null,
};

/// Constructs a parser from option definitions and config.
/// The returned type has an 'Options' struct field with a field for each option
///   definition, plus the positional remainder.
pub fn Parser(comptime option_defs: []const OptionDefinition, config: ParserConfig) type {
    const additional_field_count = 1;
    const field_count = option_defs.len + additional_field_count;

    const array_count = blk: {
        var n: usize = 0;
        inline for (option_defs) |d| if (isSlice(d.Type)) {
            n += 1;
        };
        break :blk n;
    };

    const Meta = struct {
        fn n(comptime meta_field_count: usize) type {
            return struct {
                names: [meta_field_count][]const u8 = undefined,
                types: [meta_field_count]type = undefined,
                attrs: [meta_field_count]std.builtin.Type.StructField.Attributes = undefined,
            };
        }
    };

    var option_meta: Meta.n(field_count) = .{};
    var _max_name_len: usize = 0;
    var _max_type_name_len: usize = 0;

    option_meta.names[option_defs.len] = "positionals";
    option_meta.types[option_defs.len] = []const []const u8;
    const default_positionals: []const []const u8 = &.{};
    option_meta.attrs[option_defs.len] = .{ .default_value_ptr = @ptrCast(&default_positionals) };

    inline for (option_defs, 0..) |*def, i| {
        if (def.short_name_opt) |short_name| {
            for (option_defs[0..i]) |o| {
                if (o.short_name_opt == short_name) {
                    @compileError(std.fmt.comptimePrint(
                        "Duplicate short name '{c}' (name '{s}'), duplicate of '{c}' (name '{s}')",
                        .{ short_name, def.name, o.short_name_opt.?, o.name },
                    ));
                }
            }
        }

        for (option_meta.names[0..i], option_defs[0..i]) |other_name, other_def| {
            if (std.mem.eql(u8, def.name, other_name)) {
                const short = if (def.short_name_opt) |s| std.fmt.comptimePrint(" (short '{c}')", .{s}) else "";
                const dup_short = if (other_def.short_name_opt) |s| std.fmt.comptimePrint(" (short '{c}')", .{s}) else "";
                @compileError(std.fmt.comptimePrint(
                    "Duplicate name '{s}'{s}, duplicate of '{s}'{s}",
                    .{ def.name, short, other_name, dup_short },
                ));
            }
        }

        if (def.name.len > _max_name_len) _max_name_len = def.name.len;
        if (typeName(def.Type).len > _max_type_name_len) _max_type_name_len = typeName(def.Type).len;

        option_meta.names[i] = def.name;
        option_meta.types[i] = def.OptionType;
        option_meta.attrs[i] = .{ .default_value_ptr = def.default_value_ptr };
    }

    const OptionStruct = @Struct(.auto, null, &option_meta.names, &option_meta.types, &option_meta.attrs);
    const max_name_len = _max_name_len;
    const max_type_name_len = _max_type_name_len;

    return struct {
        /// The parsed result. One field for each option definition,
        ///  plus the positional remainder.
        /// String options borrow memory from 'args', array options allocate the
        ///   array, string elements are borrowed from 'args'.
        /// Must be freed with 'Parser.freeOptions()'.
        pub const Options = OptionStruct;

        pub const ParseError = error{
            InvalidOption,
            InvalidShortOption,
            OutOfMemory,
            InvalidValue,
            MissingValue,
            IntegerValueOverflow,
            TooFewPositionals,
            TooManyPositionals,
        };

        program_name: []const u8,
        usage_help_hint: UsageHelpHint,
        err_writer_opt: ?*std.Io.Writer,

        pub const UsageHelpHint = union(enum) {
            /// If a help option is defined, print an additional usage() line to
            ///   hint to the help option.
            default,

            /// Custom string to print after regular usage().
            /// usage() does not add a newline at the end!
            custom: []const u8,
        };

        /// Run time parser options.
        pub const InitOptions = struct {
            /// Optional error writer. If null, no errors are logged, only returned.
            err_writer: ?*std.Io.Writer,

            /// Determines if usages hints to the help option
            usage_help_hint: UsageHelpHint = .default,
        };

        /// Initialize parser.
        /// 'program_name' is used in usage()/help() printing.
        /// 'options' run time parser options.
        pub fn init(program_name: []const u8, options: InitOptions) @This() {
            return .{
                .program_name = program_name,
                .usage_help_hint = options.usage_help_hint,
                .err_writer_opt = options.err_writer,
            };
        }

        /// Parse the given 'args' into the 'Options' struct.
        /// 'allocator' is used to allocate arrays.
        /// Strings and string arrays borrow the string memory from 'args'.
        /// 'positionals' is a sub slice into 'args'.
        /// Returned 'Options' must be freed by 'Parser.freeOptions()'
        ///
        /// Boolean options accept no value, they 'set' the opposite of the default.
        /// Non array options keep the last set value.
        /// Array options append each value to the corresponding slice.
        pub fn parse(this: *const @This(), allocator: Allocator, args: []const []const u8) ParseError!Options {
            var result: Options = .{};
            errdefer freeOptions(&result, allocator);

            var array_counts: [array_count]usize = @splat(0);
            var positionals_start: ?usize = null;
            // First pass
            var i: usize = 0;
            while (i < args.len) : (i += 1) {
                const rem = args[i..];
                const arg = rem[0];

                if (std.mem.startsWith(u8, arg, "--")) {
                    if (arg.len == 2) {
                        positionals_start = i + 1;
                        break;
                    }

                    // long option
                    const stripped_arg = arg[2..];
                    const eq_idx_opt = std.mem.findScalar(u8, stripped_arg, '=');
                    const name = if (eq_idx_opt) |eq_idx| stripped_arg[0..eq_idx] else stripped_arg;

                    var array_idx: usize = 0;
                    def_loop: inline for (option_defs) |*def| {
                        if (std.mem.eql(u8, def.name, name)) {
                            _ = longValueString(def, eq_idx_opt, stripped_arg, rem, &i) catch |e| {
                                switch (e) {
                                    error.InvalidOption => this.err("Invalid option: '{s}'", .{arg}),
                                    error.MissingValue => this.err("Missing value for option: '{s}'", .{arg}),
                                }
                                return e;
                            };

                            if (array_count > 0 and isSlice(def.Type)) {
                                array_counts[array_idx] += 1;
                            }

                            break :def_loop;
                        }

                        if (isSlice(def.Type)) {
                            array_idx += 1;
                        }
                    } else {
                        this.err("Invalid option: '--{s}'", .{name});
                        return error.InvalidOption;
                    }
                } else if (arg.len > 1 and arg[0] == '-') {
                    // short option
                    const short_names = arg[1..];
                    short_loop: for (short_names, 0..) |short_name, si| {
                        var array_idx: usize = 0;
                        def_loop: inline for (option_defs) |*def| {
                            if (def.short_name_opt == short_name) {
                                _ = shortValueString(def, si, short_names, rem, &i) catch |e| {
                                    switch (e) {
                                        error.MissingValue => this.err("Missing value for option: '-{c}'", .{short_name}),
                                    }
                                    return e;
                                };

                                if (array_count > 0 and isSlice(def.Type)) {
                                    array_counts[array_idx] += 1;
                                }

                                if (def.Type != bool) break :short_loop;
                                break :def_loop;
                            }

                            if (isSlice(def.Type)) {
                                array_idx += 1;
                            }
                        } else {
                            this.err("Invalid short option: '-{c}'", .{short_name});
                            return error.InvalidShortOption;
                        }
                    }
                } else {
                    positionals_start = i;
                    break;
                }
            }

            {
                // Allocate arrays
                var array_idx: usize = 0;
                inline for (option_defs) |*def| {
                    if (comptime isSlice(def.Type)) {
                        if (array_counts[array_idx] > 0)
                            @field(result, def.name) = try allocator.alloc(std.meta.Elem(def.OptionType), array_counts[array_idx]);
                        array_idx += 1;
                    }
                }
            }

            var array_fill_indices: [array_count]usize = @splat(0);

            // Second pass
            i = 0;
            const end = positionals_start orelse args.len;
            while (i < end) : (i += 1) {
                const rem = args[i..];
                const arg = rem[0];

                if (std.mem.startsWith(u8, arg, "--")) {
                    if (arg.len == 2) {
                        break;
                    }

                    // long option
                    const stripped_arg = arg[2..];
                    const eq_idx_opt = std.mem.findScalar(u8, stripped_arg, '=');
                    const name = if (eq_idx_opt) |eq_idx| stripped_arg[0..eq_idx] else stripped_arg;

                    var array_index: usize = 0;
                    def_loop: inline for (option_defs) |*def| {
                        if (std.mem.eql(u8, def.name, name)) {
                            const value_str = longValueString(def, eq_idx_opt, stripped_arg, rem, &i) catch unreachable;

                            const name_for_err = if (eq_idx_opt) |eq_idx| arg[0 .. eq_idx + 2] else arg;

                            const value = try this.parseValueString(def, value_str, name_for_err);
                            setValue(def, &result, &array_fill_indices, array_index, value);

                            break :def_loop;
                        }

                        if (comptime isSlice(def.Type)) {
                            array_index += 1;
                        }
                    } else unreachable; // Option not found

                } else if (arg.len > 1 and arg[0] == '-') {
                    // short option
                    const short_names = arg[1..];
                    short_loop: for (short_names, 0..) |short_name, si| {
                        var array_index: usize = 0;
                        def_loop: inline for (option_defs) |*def| {
                            if (def.short_name_opt == short_name) {
                                const value_str = shortValueString(def, si, short_names, rem, &i) catch unreachable;

                                const name_for_err = "-" ++ [_]u8{def.short_name_opt.?};

                                const value = try this.parseValueString(def, value_str, name_for_err);
                                setValue(def, &result, &array_fill_indices, array_index, value);

                                if (def.Type != bool) break :short_loop;
                                break :def_loop;
                            }

                            if (isSlice(def.Type)) {
                                array_index += 1;
                            }
                        } else unreachable; // Option not found
                    }
                } else unreachable; // Positionals start
            }

            result.positionals = if (positionals_start) |s| args[s..] else &.{};

            if (result.positionals.len < config.min_positionals) {
                this.err("Expected at least {} positionals, got {}", .{ config.min_positionals, result.positionals.len });
                return error.TooFewPositionals;
            } else if (config.max_positionals_opt) |max_positionals| if (result.positionals.len > max_positionals) {
                this.err("Expected at most {} positionals, got {}", .{ max_positionals, result.positionals.len });
                return error.TooManyPositionals;
            };

            return result;
        }

        inline fn longValueString(
            def: *const OptionDefinition,
            eq_idx_opt: ?usize,
            stripped_arg: []const u8,
            rem: []const []const u8,
            arg_idx: *usize,
        ) error{ InvalidOption, MissingValue }![]const u8 {
            return if (def.Type == bool)
                if (eq_idx_opt != null)
                    return error.InvalidOption
                else
                    ""
            else if (eq_idx_opt) |eq_idx|
                if (stripped_arg[eq_idx..].len == 1)
                    if (def.Type == String or def.Type == []const String)
                        ""
                    else
                        return error.MissingValue
                else
                    stripped_arg[eq_idx + 1 ..]
            else if (rem.len >= 2) blk: {
                arg_idx.* += 1;
                break :blk rem[1];
            } else return error.MissingValue;
        }

        inline fn shortValueString(
            def: *const OptionDefinition,
            short_index: usize,
            short_names: []const u8,
            rem: []const []const u8,
            arg_idx: *usize,
        ) error{MissingValue}![]const u8 {
            return if (def.Type == bool)
                ""
            else if (short_index < short_names.len - 1)
                short_names[short_index + 1 ..]
            else if (rem.len >= 2) blk: {
                arg_idx.* += 1;
                break :blk rem[1];
            } else return error.MissingValue;
        }

        inline fn setValue(def: *const OptionDefinition, options: *Options, array_fill_indices: *[array_count]usize, array_index: usize, value: anytype) void {
            if (comptime isSlice(def.Type)) {
                const dst: []std.meta.Elem(def.OptionType) = @constCast(@field(options, def.name));
                dst[array_fill_indices[array_index]] = value;
                array_fill_indices[array_index] += 1;
            } else {
                @field(options, def.name) = value;
            }
        }

        inline fn parseValueString(this: *const @This(), comptime def: *const OptionDefinition, value_str: anytype, name: []const u8) !if (isSlice(def.Type))
            std.meta.Elem(def.OptionType)
        else
            def.OptionType {
            const T = def.Type;

            return switch (T) {
                bool => !def.defaultValue(),
                String => value_str,

                else => switch (@typeInfo(T)) {
                    .int => try this.parseInt(T, value_str, name),
                    .float => try this.parseFloat(T, value_str, name),
                    .@"enum" => try this.parseEnum(T, value_str, name),

                    .pointer => blk: {
                        const Elem = std.meta.Elem(T);
                        break :blk switch (Elem) {
                            String => value_str,

                            else => switch (@typeInfo(Elem)) {
                                .int => try this.parseInt(Elem, value_str, name),
                                .float => try this.parseFloat(Elem, value_str, name),
                                .@"enum" => try this.parseEnum(Elem, value_str, name),

                                else => unreachable,
                            },
                        };
                    },

                    else => unreachable,
                },
            };
        }

        fn parseInt(this: *const @This(), comptime T: type, str: []const u8, name: []const u8) error{ IntegerValueOverflow, InvalidValue }!T {
            return std.fmt.parseInt(T, str, 10) catch |e| switch (e) {
                error.InvalidCharacter => {
                    this.err("Invalid integer value: '{s}' for option: '{s}'", .{ str, name });
                    return error.InvalidValue;
                },
                error.Overflow => {
                    this.err("Integer overflow: '{s}', option: '{s}', (int type: '{s}')", .{ str, name, @typeName(T) });
                    return error.IntegerValueOverflow;
                },
            };
        }

        fn parseFloat(this: *const @This(), comptime T: type, str: []const u8, name: []const u8) error{InvalidValue}!T {
            return std.fmt.parseFloat(T, str) catch |e| switch (e) {
                error.InvalidCharacter => {
                    this.err("Invalid float value: '{s}' for option: '{s}'", .{ str, name });
                    return error.InvalidValue;
                },
            };
        }

        fn parseEnum(this: *const @This(), comptime T: type, str: []const u8, name: []const u8) !T {
            return std.meta.stringToEnum(T, str) orelse {
                this.err("Invalid enum value: '{s}' for option: '{s}'", .{ str, name });
                return error.InvalidValue;
            };
        }

        /// Frees the memory referenced by 'Options' struct.
        pub fn freeOptions(o: *const Options, allocator: Allocator) void {
            inline for (option_defs) |*def| {
                skip: {
                    if (comptime isSlice(def.Type)) {
                        const slice = @field(o, def.name);
                        if (slice.len == 0) break :skip;

                        const default_slice = @as(*@TypeOf(slice), @ptrCast(@alignCast(@constCast(def.default_value_ptr)))).*;
                        if (default_slice.ptr == slice.ptr) break :skip;

                        allocator.free(slice);
                    }
                }
            }
        }

        /// Prints a short usage line, plus optional help hint.
        pub fn usage(this: *const @This(), writer: *std.Io.Writer) error{WriteFailed}!void {
            try this.usageNoHelpHint(writer);

            switch (this.usage_help_hint) {
                .default => if (@hasField(Options, "help") and @FieldType(Options, "help") == bool) {
                    try writer.print("Try '{s} --help' for more information.\n", .{this.program_name});
                },
                .custom => |str| if (str.len > 0) {
                    try writer.writeAll(str);
                },
            }
        }

        fn usageNoHelpHint(this: *const @This(), writer: *std.Io.Writer) error{WriteFailed}!void {
            try writer.print("Usage: {s} [OPTIONS]", .{this.program_name});
            if (config.usage_positionals_label_opt) |upl| {
                try writer.writeByte(' ');
                try writer.writeAll(upl);
            }
            try writer.writeByte('\n');
        }

        /// Prints the usage(), plus full option list with names, types, and descriptions.
        pub fn help(this: *const @This(), writer: *std.Io.Writer) error{WriteFailed}!void {
            try this.usageNoHelpHint(writer);
            try writer.writeAll("\nOptions:\n");

            var name_align_buf: [max_name_len]u8 = undefined;
            var type_align_buf: [max_type_name_len]u8 = undefined;

            inline for (option_defs) |*def| {
                try writer.writeAll("  ");

                if (def.short_name_opt) |s|
                    try writer.print("-{c}, --", .{s})
                else
                    try writer.writeAll("    --");

                try writer.writeAll(padRight(&name_align_buf, def.name, ' '));

                try writer.writeAll("  ");
                const type_name = typeName(def.Type);
                try writer.writeAll(padRight(&type_align_buf, type_name, ' '));

                try writer.writeAll("    ");
                if (def.desc_opt) |desc| {
                    try writer.writeAll(desc);
                }

                try writer.writeByte('\n');
            }

            try writer.writeByte('\n');
        }

        inline fn err(this: *const @This(), comptime fmt: []const u8, args: anytype) void {
            if (this.err_writer_opt) |err_writer| {
                err_writer.print("{s}: ", .{this.program_name}) catch {};
                err_writer.print(fmt ++ "\n", args) catch {};
            }
        }
    };
}

fn padRight(buf: []u8, str: []const u8, pad: u8) []const u8 {
    assert(str.len <= buf.len);

    @memcpy(buf[0..str.len], str);
    if (buf.len > str.len) @memset(buf[str.len..], pad);
    return buf;
}

fn typeName(comptime T: type) []const u8 {
    return switch (T) {
        bool => "bool",
        String => "String",
        else => switch (@typeInfo(T)) {
            .int,
            .float,
            => @typeName(T),

            .@"enum" => core.meta.typeNameLeaf(T),

            else => if (isSlice(T))
                "[]" ++ comptime typeName(std.meta.Elem(T))
            else
                unreachable,
        },
    };
}

fn isSlice(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |pi| pi.size == .slice and pi.is_const,
        else => false,
    };
}

const Color = enum { black, white, red, green, blue };
const YesOrNo = enum { yes, no };
const TestParser = Parser(&.{
    .bool(false, "verbose", 'v', null),
    .bool(false, "debug", 'd', null),
    .string("", "path", 'p', null),
    .int(u8, 0, "num_threads", 'n', null),
    .int(i8, 0, "offset", 'o', null),
    .float(f32, 0, "float", 'f', null),
    .@"enum"(Color, .black, "color", 'c', null),
    .stringArray(&.{}, "array", 'a', null),
    .intArray(u8, &.{}, "int_array", 'i', null),
    .floatArray(f32, &.{}, "float_array", null, null),
    .enumArray(YesOrNo, &.{}, "enum_array", null, null),
    .bool(false, "help", 'h', "Print this help"),
}, .{ .usage_positionals_label_opt = "[FILES]" });

pub fn main(init: std.process.Init) !u8 {
    var stderr_buf: [128]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buf);
    defer stderr_writer.flush() catch {};

    var stdout_buf: [128]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    defer stdout_writer.flush() catch {};

    const all_args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(all_args);

    assert(all_args.len >= 1);

    const program_name = all_args[0];
    const args = if (all_args.len > 0) all_args[1..] else &.{};

    const option_parser = TestParser.init(program_name, .{
        .err_writer = &stderr_writer.interface,
    });

    const options = option_parser.parse(init.gpa, args) catch |e| {
        switch (e) {
            error.OutOfMemory => return e,
            else => try option_parser.usage(&stderr_writer.interface),
        }
        return 1;
    };
    defer TestParser.freeOptions(&options, init.gpa);

    if (@hasField(TestParser.Options, "help") and options.help) {
        try option_parser.help(&stdout_writer.interface);
        return 0;
    }

    log.info("String array values:", .{});
    for (options.array, 0..) |value, i| {
        log.info("\t{}: '{s}'", .{ i, value });
    }
    log.info("", .{});

    log.info("int array values:", .{});
    for (options.int_array, 0..) |value, i| {
        log.info("\t{}: {}", .{ i, value });
    }
    log.info("", .{});

    log.info("float array values:", .{});
    for (options.float_array, 0..) |value, i| {
        log.info("\t{}: {}", .{ i, value });
    }
    log.info("", .{});

    log.info("enum array values:", .{});
    for (options.enum_array, 0..) |value, i| {
        log.info("\t{}: {s}", .{ i, @tagName(value) });
    }
    log.info("", .{});

    log.info("positionals:", .{});
    for (options.positionals, 0..) |value, i| {
        log.info("\t{}: '{s}'", .{ i, value });
    }

    return 0;
}

const t = std.testing;

fn expectParseResult(comptime OP: type, args: []const []const u8, expected: OP.Options) !void {
    const parser = OP.init("test", .{ .err_writer = null });
    const result_or_err = parser.parse(t.allocator, args);

    const result = result_or_err catch {
        return error.UnexpectedError;
    };

    defer OP.freeOptions(&result, t.allocator);

    try t.expectEqualDeep(expected, result);
}

fn expectParseError(comptime OP: type, args: []const []const u8, expected: OP.ParseError) !void {
    const parser = OP.init("test", .{ .err_writer = null });
    const result_or_err = parser.parse(t.allocator, args);

    try t.expectError(expected, result_or_err);

    if (result_or_err) |result| {
        OP.freeOptions(&result, t.allocator);
    } else |_| {}
}

test Parser {
    const P = TestParser;

    try expectParseResult(P, &.{}, .{});

    try expectParseResult(P, &.{"-v"}, .{ .verbose = true });
    try expectParseResult(P, &.{ "--", "-v" }, .{ .positionals = &.{"-v"} });
    try expectParseResult(P, &.{ "-v", "--" }, .{ .verbose = true });

    try expectParseError(P, &.{"-p"}, error.MissingValue);
    try expectParseError(P, &.{"-x"}, error.InvalidShortOption);
    try expectParseError(P, &.{"-vx"}, error.InvalidShortOption);

    try expectParseResult(P, &.{"-"}, .{ .positionals = &.{"-"} });

    try expectParseResult(P, &.{ "-p", "abc" }, .{ .path = "abc" });
    try expectParseResult(P, &.{ "-p", "abc", "-p", "def" }, .{ .path = "def" });
    try expectParseResult(P, &.{ "-p", "-v" }, .{ .path = "-v" });
    try expectParseResult(P, &.{ "-p", "--" }, .{ .path = "--" });
    try expectParseResult(P, &.{"-pabc"}, .{ .path = "abc" });
    try expectParseResult(P, &.{"-pabc-v"}, .{ .path = "abc-v" });
    try expectParseResult(P, &.{"-p abc"}, .{ .path = " abc" });
    try expectParseResult(P, &.{"-p -- abc"}, .{ .path = " -- abc" });
    try expectParseResult(P, &.{ "-pabc", "def" }, .{ .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "--", "-p", "abc" }, .{ .positionals = &.{ "-p", "abc" } });
    try expectParseResult(P, &.{ "-p", "--", "abc" }, .{ .path = "--", .positionals = &.{"abc"} });
    try expectParseResult(P, &.{ "-p", "abc", "--" }, .{ .path = "abc" });

    try expectParseResult(P, &.{ "-v", "-p", "abc", "def" }, .{ .verbose = true, .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "--", "-v", "-p", "abc", "def" }, .{ .positionals = &.{ "-v", "-p", "abc", "def" } });
    try expectParseResult(P, &.{ "-v", "--", "-p", "abc", "def" }, .{ .verbose = true, .positionals = &.{ "-p", "abc", "def" } });
    try expectParseResult(P, &.{ "-v", "-p", "--", "abc", "def" }, .{ .verbose = true, .path = "--", .positionals = &.{ "abc", "def" } });
    try expectParseResult(P, &.{ "-v", "-p", "abc", "--", "def" }, .{ .verbose = true, .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "-v", "-p", "abc", "def", "--" }, .{ .verbose = true, .path = "abc", .positionals = &.{ "def", "--" } });

    try expectParseResult(P, &.{"-vpabc"}, .{ .verbose = true, .path = "abc" });
    try expectParseResult(P, &.{ "-vp", "abc" }, .{ .verbose = true, .path = "abc" });
    try expectParseResult(P, &.{"-pv"}, .{ .path = "v" });
    try expectParseResult(P, &.{"-pabcv"}, .{ .path = "abcv" });
    try expectParseResult(P, &.{"-vd"}, .{ .verbose = true, .debug = true });

    try expectParseResult(P, &.{"--verbose"}, .{ .verbose = true });
    try expectParseResult(P, &.{ "--", "--verbose" }, .{ .positionals = &.{"--verbose"} });
    try expectParseResult(P, &.{ "--verbose", "--" }, .{ .verbose = true });

    try expectParseError(P, &.{"--whatever"}, error.InvalidOption);
    try expectParseError(P, &.{"--verbose=foo"}, error.InvalidOption);
    try expectParseError(P, &.{"--verbose=true"}, error.InvalidOption);
    try expectParseResult(P, &.{ "--verbose", "true" }, .{ .verbose = true, .positionals = &.{"true"} });
    try expectParseResult(P, &.{ "--verbose", "false" }, .{ .verbose = true, .positionals = &.{"false"} });

    try expectParseResult(P, &.{ "-p", "abc" }, .{ .path = "abc" });
    try expectParseResult(P, &.{ "--", "-p", "abc" }, .{ .positionals = &.{ "-p", "abc" } });
    try expectParseResult(P, &.{ "-p", "--", "abc" }, .{ .path = "--", .positionals = &.{"abc"} });
    try expectParseResult(P, &.{ "-p", "abc", "--" }, .{ .path = "abc" });

    try expectParseResult(P, &.{ "--verbose", "-p", "abc", "def" }, .{ .verbose = true, .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "--", "--verbose", "-p", "abc", "def" }, .{ .positionals = &.{ "--verbose", "-p", "abc", "def" } });
    try expectParseResult(P, &.{ "--verbose", "--", "-p", "abc", "def" }, .{ .verbose = true, .positionals = &.{ "-p", "abc", "def" } });
    try expectParseResult(P, &.{ "--verbose", "-p", "--", "abc", "def" }, .{ .verbose = true, .path = "--", .positionals = &.{ "abc", "def" } });
    try expectParseResult(P, &.{ "--verbose", "-p", "abc", "--", "def" }, .{ .verbose = true, .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "--verbose", "-p", "abc", "def", "--" }, .{ .verbose = true, .path = "abc", .positionals = &.{ "def", "--" } });

    try expectParseResult(P, &.{ "--path", "a", "--path", "b" }, .{ .path = "b" });
    try expectParseResult(P, &.{ "--path=a", "--path", "b" }, .{ .path = "b" });
    try expectParseResult(P, &.{ "--path", "a", "--path=b" }, .{ .path = "b" });
    try expectParseResult(P, &.{ "--path=a", "--path=b" }, .{ .path = "b" });

    try expectParseError(P, &.{"--path"}, error.MissingValue);
    try expectParseResult(P, &.{"--path="}, .{ .path = "" });
    try expectParseResult(P, &.{ "--path", "" }, .{ .path = "" });
    try expectParseResult(P, &.{ "--path=", "abc" }, .{ .path = "", .positionals = &.{"abc"} });
    try expectParseResult(P, &.{"--path=--"}, .{ .path = "--" });
    try expectParseResult(P, &.{ "--path", "--" }, .{ .path = "--" });
    try expectParseResult(P, &.{"--path=a=b"}, .{ .path = "a=b" });
    try expectParseResult(P, &.{ "--path", "=a=b" }, .{ .path = "=a=b" });
    try expectParseResult(P, &.{ "--path", "abc" }, .{ .path = "abc" });
    try expectParseResult(P, &.{ "--", "--path", "abc" }, .{ .positionals = &.{ "--path", "abc" } });
    try expectParseResult(P, &.{ "--path", "--", "abc" }, .{ .path = "--", .positionals = &.{"abc"} });
    try expectParseResult(P, &.{ "--path", "abc", "--" }, .{ .path = "abc" });

    try expectParseResult(P, &.{ "-v", "--path", "abc", "def" }, .{ .verbose = true, .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "--", "-v", "--path", "abc", "def" }, .{ .positionals = &.{ "-v", "--path", "abc", "def" } });
    try expectParseResult(P, &.{ "-v", "--", "--path", "abc", "def" }, .{ .verbose = true, .positionals = &.{ "--path", "abc", "def" } });
    try expectParseResult(P, &.{ "-v", "--path", "--", "abc", "def" }, .{ .verbose = true, .path = "--", .positionals = &.{ "abc", "def" } });
    try expectParseResult(P, &.{ "-v", "--path", "abc", "--", "def" }, .{ .verbose = true, .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "-v", "--path", "abc", "def", "--" }, .{ .verbose = true, .path = "abc", .positionals = &.{ "def", "--" } });

    try expectParseResult(P, &.{ "--verbose", "--path", "abc", "def" }, .{ .verbose = true, .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "--", "--verbose", "--path", "abc", "def" }, .{ .positionals = &.{ "--verbose", "--path", "abc", "def" } });
    try expectParseResult(P, &.{ "--verbose", "--", "--path", "abc", "def" }, .{ .verbose = true, .positionals = &.{ "--path", "abc", "def" } });
    try expectParseResult(P, &.{ "--verbose", "--path", "--", "abc", "def" }, .{ .verbose = true, .path = "--", .positionals = &.{ "abc", "def" } });
    try expectParseResult(P, &.{ "--verbose", "--path", "abc", "--", "def" }, .{ .verbose = true, .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "--verbose", "--path", "abc", "def", "--" }, .{ .verbose = true, .path = "abc", .positionals = &.{ "def", "--" } });

    try expectParseResult(P, &.{"--path=abc"}, .{ .path = "abc" });
    try expectParseResult(P, &.{"--path= abc"}, .{ .path = " abc" });
    try expectParseError(P, &.{"--path =abc"}, error.InvalidOption);
    try expectParseResult(P, &.{ "--path", "=", "abc" }, .{ .path = "=", .positionals = &.{"abc"} });
    try expectParseResult(P, &.{ "--path", "=abc" }, .{ .path = "=abc" });
    try expectParseResult(P, &.{ "--", "--path=abc" }, .{ .positionals = &.{"--path=abc"} });
    try expectParseResult(P, &.{ "--path", "--", "=abc" }, .{ .path = "--", .positionals = &.{"=abc"} });
    try expectParseResult(P, &.{ "--path=abc", "--" }, .{ .path = "abc" });

    try expectParseResult(P, &.{ "-v", "--path=abc", "def" }, .{ .verbose = true, .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "-v", "--path=abc def" }, .{ .verbose = true, .path = "abc def" });
    try expectParseResult(P, &.{ "--", "-v", "--path=abc", "def" }, .{ .positionals = &.{ "-v", "--path=abc", "def" } });
    try expectParseResult(P, &.{ "--", "-v", "--path=abc def" }, .{ .positionals = &.{ "-v", "--path=abc def" } });
    try expectParseResult(P, &.{ "-v", "--", "--path=abc", "def" }, .{ .verbose = true, .positionals = &.{ "--path=abc", "def" } });
    try expectParseResult(P, &.{ "-v", "--path", "--", "=abc", "def" }, .{ .verbose = true, .path = "--", .positionals = &.{ "=abc", "def" } });
    try expectParseResult(P, &.{ "-v", "--path=abc", "--", "def" }, .{ .verbose = true, .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "-v", "--path=abc", "def", "--" }, .{ .verbose = true, .path = "abc", .positionals = &.{ "def", "--" } });

    try expectParseResult(P, &.{ "--verbose", "--path=abc", "def" }, .{ .verbose = true, .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "--", "--verbose", "--path=abc", "def" }, .{ .positionals = &.{ "--verbose", "--path=abc", "def" } });
    try expectParseResult(P, &.{ "--verbose", "--", "--path=abc", "def" }, .{ .verbose = true, .positionals = &.{ "--path=abc", "def" } });
    try expectParseResult(P, &.{ "--verbose", "--path", "--", "=abc", "def" }, .{ .verbose = true, .path = "--", .positionals = &.{ "=abc", "def" } });
    try expectParseResult(P, &.{ "--verbose", "--path=abc", "--", "def" }, .{ .verbose = true, .path = "abc", .positionals = &.{"def"} });
    try expectParseResult(P, &.{ "--verbose", "--path=abc", "def", "--" }, .{ .verbose = true, .path = "abc", .positionals = &.{ "def", "--" } });

    try expectParseResult(P, &.{ "-n", "42" }, .{ .num_threads = 42 });
    try expectParseResult(P, &.{"-n42"}, .{ .num_threads = 42 });
    try expectParseResult(P, &.{"--num_threads=42"}, .{ .num_threads = 42 });
    try expectParseResult(P, &.{ "--num_threads", "42" }, .{ .num_threads = 42 });
    try expectParseError(P, &.{ "--num_threads=", "42" }, error.MissingValue);
    try expectParseError(P, &.{ "--num_threads", "=42" }, error.InvalidValue);
    try expectParseResult(P, &.{ "-n", "255" }, .{ .num_threads = 255 });
    try expectParseError(P, &.{ "-n", "256" }, error.IntegerValueOverflow);
    try expectParseError(P, &.{ "-n", "-1" }, error.IntegerValueOverflow);
    try expectParseError(P, &.{"-nacb"}, error.InvalidValue);
    try expectParseError(P, &.{ "-n", "acb" }, error.InvalidValue);
    try expectParseError(P, &.{"--num_threads=acb"}, error.InvalidValue);
    try expectParseError(P, &.{ "--num_threads", "acb" }, error.InvalidValue);
    try expectParseResult(P, &.{"-o-1"}, .{ .offset = -1 });
    try expectParseResult(P, &.{"-o127"}, .{ .offset = 127 });
    try expectParseResult(P, &.{"-o-128"}, .{ .offset = -128 });
    try expectParseError(P, &.{"-o128"}, error.IntegerValueOverflow);
    try expectParseError(P, &.{"-o-129"}, error.IntegerValueOverflow);

    try expectParseResult(P, &.{ "-f", "42" }, .{ .float = 42 });
    try expectParseResult(P, &.{ "-f", "4.2" }, .{ .float = 4.2 });
    try expectParseResult(P, &.{ "-f", ".42" }, .{ .float = 0.42 });
    try expectParseResult(P, &.{"--float=4.2"}, .{ .float = 4.2 });
    try expectParseResult(P, &.{ "--float", "4.2" }, .{ .float = 4.2 });
    try expectParseError(P, &.{ "--float=", "4.2" }, error.MissingValue);
    try expectParseError(P, &.{ "--float", "=4.2" }, error.InvalidValue);

    try expectParseResult(P, &.{ "-c", "red" }, .{ .color = .red });
    try expectParseResult(P, &.{ "-cwhite", "red" }, .{ .color = .white, .positionals = &.{"red"} });
    try expectParseResult(P, &.{ "--color", "red" }, .{ .color = .red });
    try expectParseResult(P, &.{"--color=red"}, .{ .color = .red });
    try expectParseError(P, &.{"--color=redd"}, error.InvalidValue);
    try expectParseError(P, &.{ "--color=", "red" }, error.MissingValue);
    try expectParseError(P, &.{ "--color", "=red" }, error.InvalidValue);

    try expectParseResult(
        P,
        &.{ "-afirst", "-a", "second", "--array=third", "--array", "fourth", "fifth" },
        .{ .array = &.{ "first", "second", "third", "fourth" }, .positionals = &.{"fifth"} },
    );

    try expectParseError(P, &.{"-a"}, error.MissingValue);
    try expectParseError(P, &.{"--array"}, error.MissingValue);
    try expectParseResult(P, &.{"--array="}, .{ .array = &.{""} });

    try expectParseResult(
        P,
        &.{ "-i1", "-i", "2", "--int_array=3", "--int_array", "4", "5" },
        .{ .int_array = &.{ 1, 2, 3, 4 }, .positionals = &.{"5"} },
    );

    try expectParseError(P, &.{"-i"}, error.MissingValue);
    try expectParseError(P, &.{"--int_array"}, error.MissingValue);
    try expectParseError(P, &.{"--int_array="}, error.MissingValue);
    try expectParseError(P, &.{"-i1.2"}, error.InvalidValue);
    try expectParseError(P, &.{"--int_array=1.2"}, error.InvalidValue);
    try expectParseError(P, &.{ "--int_array", "1.2" }, error.InvalidValue);

    try expectParseResult(
        P,
        &.{ "--float_array", "1.2", "--float_array", "33.44", "--float_array=555.666", "--float_array", "7777.8888", "9999.10101010" },
        .{ .float_array = &.{ 1.2, 33.44, 555.666, 7777.8888 }, .positionals = &.{"9999.10101010"} },
    );

    try expectParseError(P, &.{"-f"}, error.MissingValue);
    try expectParseError(P, &.{"--float_array"}, error.MissingValue);
    try expectParseError(P, &.{"--float_array="}, error.MissingValue);
    try expectParseError(P, &.{"-fabc"}, error.InvalidValue);
    try expectParseError(P, &.{"--float_array=abc"}, error.InvalidValue);
    try expectParseError(P, &.{ "--float_array", "abc" }, error.InvalidValue);

    try expectParseResult(
        P,
        &.{ "--enum_array", "yes", "--enum_array", "no", "--enum_array=yes", "--enum_array", "no", "no" },
        .{ .enum_array = &.{ .yes, .no, .yes, .no }, .positionals = &.{"no"} },
    );

    try expectParseError(P, &.{"--enum_array"}, error.MissingValue);
    try expectParseError(P, &.{"--enum_array="}, error.MissingValue);
    try expectParseError(P, &.{"--enum_array=abc"}, error.InvalidValue);
    try expectParseError(P, &.{ "--enum_array", "abc" }, error.InvalidValue);
    try expectParseError(P, &.{"--enum_array=1"}, error.InvalidValue);
    try expectParseError(P, &.{ "--enum_array", "1" }, error.InvalidValue);
    try expectParseError(P, &.{"--enum_array=Yes"}, error.InvalidValue);
    try expectParseError(P, &.{ "--enum_array", " no" }, error.InvalidValue);
}

test "array defaults" {
    const P = Parser(&.{
        .stringArray(&.{ "one", "two", "tree" }, "string", 's', null),
        .intArray(u8, &.{ 1, 2, 3 }, "int", 'i', null),
        .floatArray(f32, &.{ 1.1, 2.2, 3.3 }, "float", 'f', null),
        .enumArray(enum { red, green, blue }, &.{ .red, .blue, .green, .blue }, "color", 'c', null),
    }, .{});

    try expectParseResult(P, &.{}, .{
        .string = &.{ "one", "two", "tree" },
        .int = &.{ 1, 2, 3 },
        .float = &.{ 1.1, 2.2, 3.3 },
        .color = &.{ .red, .blue, .green, .blue },
    });

    try expectParseResult(P, &.{ "-sa", "-i1", "-f1.1", "-cgreen" }, .{
        .string = &.{"a"},
        .int = &.{1},
        .float = &.{1.1},
        .color = &.{.green},
    });

    try expectParseResult(P, &.{"--string="}, .{ .string = &.{""} });
    try expectParseError(P, &.{"--int="}, error.MissingValue);
    try expectParseError(P, &.{"--float="}, error.MissingValue);
    try expectParseError(P, &.{"--color="}, error.MissingValue);
}

test "positional limits" {
    const PMinParser = Parser(&.{
        .bool(false, "verbose", 'v', null),
        .string("", "path", 'p', null),
    }, .{ .min_positionals = 2 });

    try expectParseError(PMinParser, &.{}, error.TooFewPositionals);
    try expectParseError(PMinParser, &.{"first"}, error.TooFewPositionals);
    try expectParseError(PMinParser, &.{ "-v", "first" }, error.TooFewPositionals);
    try expectParseError(PMinParser, &.{ "-v", "--", "first" }, error.TooFewPositionals);
    try expectParseError(PMinParser, &.{ "--path=abc", "def" }, error.TooFewPositionals);
    try expectParseError(PMinParser, &.{ "--path", "abc", "def" }, error.TooFewPositionals);
    try expectParseResult(PMinParser, &.{ "--path=", "abc", "def" }, .{ .positionals = &.{ "abc", "def" } });
    try expectParseError(PMinParser, &.{"first"}, error.TooFewPositionals);
    try expectParseResult(PMinParser, &.{ "first", "second" }, .{ .positionals = &.{ "first", "second" } });

    const PMaxParser = Parser(&.{
        .bool(false, "verbose", 'v', null),
        .string("", "path", 'p', null),
    }, .{ .max_positionals_opt = 2 });

    try expectParseResult(PMaxParser, &.{}, .{});
    try expectParseResult(PMaxParser, &.{"first"}, .{ .positionals = &.{"first"} });
    try expectParseResult(PMaxParser, &.{ "first", "second" }, .{ .positionals = &.{ "first", "second" } });
    try expectParseError(PMaxParser, &.{ "first", "second", "third" }, error.TooManyPositionals);
    try expectParseResult(PMaxParser, &.{ "-v", "first" }, .{ .verbose = true, .positionals = &.{"first"} });
    try expectParseResult(PMaxParser, &.{ "--path", "abc", "first", "second" }, .{ .path = "abc", .positionals = &.{ "first", "second" } });
    try expectParseError(PMaxParser, &.{ "--path=abc", "first", "second", "third" }, error.TooManyPositionals);

    const PMinMaxParser = Parser(&.{
        .bool(false, "verbose", 'v', null),
        .string("", "path", 'p', null),
    }, .{ .min_positionals = 1, .max_positionals_opt = 3 });

    try expectParseError(PMinMaxParser, &.{}, error.TooFewPositionals);
    try expectParseError(PMinMaxParser, &.{"-v"}, error.TooFewPositionals);
    try expectParseError(PMinMaxParser, &.{"-pabc"}, error.TooFewPositionals);
    try expectParseError(PMinMaxParser, &.{ "-v", "-pabc" }, error.TooFewPositionals);
    try expectParseResult(PMinMaxParser, &.{"one"}, .{ .positionals = &.{"one"} });
    try expectParseResult(PMinMaxParser, &.{ "one", "two" }, .{ .positionals = &.{ "one", "two" } });
    try expectParseResult(PMinMaxParser, &.{ "one", "two", "tree" }, .{ .positionals = &.{ "one", "two", "tree" } });
    try expectParseError(PMinMaxParser, &.{ "one", "two", "tree", "four" }, error.TooManyPositionals);
    try expectParseResult(PMinMaxParser, &.{ "--path", "one", "two", "tree", "four" }, .{ .path = "one", .positionals = &.{ "two", "tree", "four" } });
}
