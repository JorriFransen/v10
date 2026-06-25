const std = @import("std");
const log = std.log.scoped(.cli_parse);
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const assert = std.debug.assert;

pub const max_name_length = 20;
const max_type_length = 10;

const Option = struct {
    name: [:0]const u8,
    short: ?u8,

    type: type,
    type_tag: TypeTag,
    is_array: bool,
    default_value_ptr: ?*const anyopaque,

    description: ?[]const u8,
};

const TypeTag = enum {
    bool,
    int,
    uint,
    float,
    string,
    @"enum",
};

pub fn option(default: anytype, name: [:0]const u8, short: ?u8, description: ?[]const u8) Option {
    const ValueType = @TypeOf(default);

    if (name.len > max_name_length) {
        @compileError(std.fmt.comptimePrint("Name too long (max {})", .{max_name_length}));
    }

    const tag = validateType(ValueType);

    return .{
        .name = name,
        .short = short,
        .type = ValueType,
        .type_tag = tag,
        .is_array = false,
        .default_value_ptr = @ptrCast(&default),
        .description = description,
    };
}

pub fn arrayOption(comptime ElemType: type, name: [:0]const u8, short: ?u8, description: ?[]const u8) Option {
    if (name.len > max_name_length) {
        @compileError(std.fmt.comptimePrint("Name too long (max {})", .{max_name_length}));
    }

    const tag = validateType(ElemType);
    const default = std.ArrayList(ElemType).empty;

    return .{
        .name = name,
        .short = short,
        .type = ElemType,
        .type_tag = tag,
        .is_array = true,
        .default_value_ptr = @ptrCast(&default),
        .description = description,
    };
}

/// # Example usage
/// ```zig
/// const OptionParser = clip.OptionParser(&.{
///     clip.option(glfw.Platform.any, "glfw_platform", 'p', "Specify the platform hint for glfw.\n"),
///     clip.option(@as(i32, -42), "test_int", 'i', "test integer."),
///     clip.option(@as(u32, 42), "test_uint", null, null),
///     clip.option(@as(f32, 4.2), "test_float", 'f', "Some float."),
///     clip.option(@as([]const u8, "abc"), "test_str", 's', null),
///     clip.ArrayOption([]const u8, "name", 'n', "Name\n"),
///     clip.option(false, "help", 'h', "Print this help message and exit."),
/// });
///
/// const cli_options = OptionParser.parse(mem.common_arena.allocator())) catch {
///     try OptionParser.usage(stderr_writer);
///     return; // Exit
/// };
/// tmp.release();
///
/// if (cli_options.help) {
///     try OptionParser.usage(stdout_writer);
///     return; // Exit
/// }
/// ```
///
/// The type of cli_options looks like this:
/// ```zig
/// struct {
///     glfw_platform: glfw.Platform = any,
///     test_int: i32 = -42,
///     test_uint: u32 = 42,
///     test_float: f32 = 4.2,
///     test_str: []const u8 = "abc",
///     name: std.ArrayList([]const u8) = std.ArrayList([]const u8){},
///     help: bool = false,
/// };
/// ```
///
/// The parse function inititalizes the result to the default values, so any
///  unset options will have their default value.
/// When specifying options by their long name (--option_name) a '=' between
///  the name and value is mandatory.
/// When specifying options by their short name (-o) a '=' between the name
/// and value is optional. When the option is a boolean the value may be
/// omitted,in which case it will be set to the inverse of the default value.
pub fn OptionParser(program_name: []const u8, comptime options: []const Option) type {
    const Info = struct {
        program_name: []const u8,
        field_names: [options.len][]const u8,
        field_types: [options.len]type,
        field_attrs: [options.len]std.builtin.Type.StructField.Attributes,
        options: [options.len]Option,
    };

    const info: Info = blk: {
        var field_names: [options.len][]const u8 = undefined;
        var field_types: [options.len]type = undefined;
        var field_attrs: [options.len]std.builtin.Type.StructField.Attributes = undefined;
        var options_copy: [options.len]Option = undefined;

        inline for (options, &field_names, &field_types, &field_attrs, &options_copy, 0..) |opt, *fname, *ftype, *fattr, *oc, i| {
            oc.* = opt;

            // Check for duplicate short name
            if (opt.short) |s| {
                for (options[0..i]) |o| {
                    if (o.short == s) {
                        @compileError(std.fmt.comptimePrint(
                            "Duplicate short name '{c}' (name '{s}'), duplicate of '{c}' (name '{s}')",
                            .{ s, opt.name, o.short.?, o.name },
                        ));
                    }
                }
            }

            // Check for duplicate name
            for (field_names[0..i], options[0..i]) |dup_f_name, o| {
                if (std.mem.eql(u8, opt.name, dup_f_name)) {
                    const short = if (opt.short) |s| std.fmt.comptimePrint(" (short '{c}')", .{s}) else "";
                    const dup_short = if (o.short) |s| std.fmt.comptimePrint(" (short '{c}')", .{s}) else "";
                    @compileError(std.fmt.comptimePrint(
                        "Duplicate name '{s}'{s}, duplicate of '{s}'{s}",
                        .{ opt.name, short, dup_f_name, dup_short },
                    ));
                }
            }

            const otag = validateType(opt.type);
            assert(otag == opt.type_tag);

            fname.* = opt.name;
            ftype.* = if (opt.is_array) std.ArrayList(opt.type) else opt.type;
            fattr.* = .{ .default_value_ptr = opt.default_value_ptr };
        }

        break :blk .{
            .program_name = program_name,
            .field_names = field_names,
            .field_types = field_types,
            .field_attrs = field_attrs,
            .options = options_copy,
        };
    };

    const OptionStruct = @Struct(.auto, null, &info.field_names, &info.field_types, &info.field_attrs);
    const ParseError = error{
        InvalidBoolValue,
        InvalidEnumValue,
        InvalidFloatValue,
        InvalidIntValue,
        InvalidOption,
        InvalidShortOption,
        MissingEq,
        MissingValue,
        OutOfMemory,
    };

    return struct {
        /// Result of the parse operation, struct containing all option fields
        pub const Options = OptionStruct;
        pub const Error = ParseError;

        /// Original options passed into OptionParser()
        pub const from_options = info.options;

        pub fn freeOptions(o: *Options, allocator: Allocator) void {
            _ = .{ o, allocator };

            const o_info = @typeInfo(Options);
            assert(o_info == .@"struct");
            assert(o_info.@"struct".fields.len == from_options.len);

            inline for (from_options, o_info.@"struct".fields) |oo, field_info| {
                if (!oo.is_array) {
                    if (oo.type_tag == .string) allocator.free(@field(o, field_info.name));
                } else {
                    const arraylist = &@field(o, field_info.name);

                    if (oo.type_tag == .string) for (arraylist.items) |s| allocator.free(s);

                    arraylist.deinit(allocator);
                }
            }
        }

        // TODO: Handle duplicate non array options (disallow or overwrite and free previous)
        pub fn parse(args: []const []const u8, allocator: Allocator) Error!Options {
            var result: Options = .{};

            var tokens = Tokenizer.init(args);

            const opt_info = @typeInfo(Options);
            assert(opt_info == .@"struct");

            while (!tokens.eof) {
                var used_short = false;

                const field_name: []const u8 = blk: {
                    if (tokens.eat("--")) |_| {
                        var name = tokens.current_token;

                        if (std.mem.indexOf(u8, name, "=")) |idx| {
                            name = name[0..idx];
                        }
                        _ = tokens.eat(name);

                        break :blk name;
                    } else if (tokens.eat("-")) |_| {
                        const c = tokens.current_token;
                        if (c.len < 1) {
                            err("Invalid short option: '{s}'", .{c});
                            return error.InvalidShortOption;
                        }
                        const short_name = c[0];
                        _ = tokens.eat(c[0..1]);

                        var field_name: ?[]const u8 = null;
                        inline for (from_options) |o| {
                            if (short_name == o.short) {
                                field_name = o.name;
                                break;
                            }
                        }

                        if (field_name == null) {
                            err("Invalid short option: '-{c}'", .{short_name});
                            return error.InvalidShortOption;
                        }

                        used_short = true;

                        break :blk field_name.?;
                    } else {
                        err("Expected option to start with '--' or '-' got '{s}'", .{tokens.current_token});
                        return error.InvalidOption;
                    }
                };

                var found = false;
                inline for (from_options, @typeInfo(Options).@"struct".fields) |o, field| {
                    if (std.mem.eql(u8, field_name, o.name)) {
                        const field_type_info = @typeInfo(o.type);

                        const before_eof = tokens.eof;
                        const parsed_eq = tokens.eat("=") != null;

                        if (field_type_info != .bool and !parsed_eq and !used_short) {
                            err("Expect '=' after option '--{s}'", .{o.name});
                            return error.MissingEq;
                        }

                        var invert_boolean = false;

                        if (field_type_info == .bool and
                            !parsed_eq and
                            (tokens.eof or
                                std.mem.startsWith(u8, tokens.current_token, "--") or
                                std.mem.startsWith(u8, tokens.current_token, "-")))
                        {
                            invert_boolean = true;
                        }

                        const value_token = if (!invert_boolean) tokens.next() else "";

                        if (!invert_boolean and value_token.len == 0) {
                            const valid_empty = o.type_tag == .string and !before_eof;
                            if (!valid_empty) {
                                err("Missing value for option '--{s}'", .{o.name});
                                return error.MissingValue;
                            }
                        }

                        const value = switch (field_type_info) {
                            else => unreachable,

                            .bool => if (invert_boolean)
                                !field.defaultValue().?
                            else if (std.mem.eql(u8, value_token, "true"))
                                true
                            else if (std.mem.eql(u8, value_token, "TRUE"))
                                true
                            else if (std.mem.eql(u8, value_token, "false"))
                                false
                            else if (std.mem.eql(u8, value_token, "FALSE"))
                                false
                            else {
                                err("Invalid boolean value: '{s}'", .{value_token});
                                return error.InvalidBoolValue;
                            },

                            .int => std.fmt.parseInt(o.type, value_token, 10) catch {
                                err("Invalid int value: '{s}'", .{value_token});
                                return error.InvalidIntValue;
                            },

                            .float => std.fmt.parseFloat(o.type, value_token) catch {
                                err("Invalid float value: '{s}'", .{value_token});
                                return error.InvalidFloatValue;
                            },

                            .@"enum" => blk: {
                                break :blk std.meta.stringToEnum(o.type, value_token) orelse {
                                    err("Invalid enum value '{s}'", .{value_token});
                                    return error.InvalidEnumValue;
                                };
                            },

                            .pointer => |ptr| blk: {
                                assert(ptr.size == .slice);
                                assert(ptr.child == u8);
                                assert(ptr.is_const);

                                const string = try allocator.alloc(u8, value_token.len);
                                @memcpy(string, value_token);

                                break :blk string;
                            },
                        };

                        if (o.is_array) {
                            try @field(result, o.name).append(allocator, value);
                        } else {
                            @field(result, o.name) = value;
                        }

                        found = true;
                        break;
                    }
                }

                if (!found) {
                    err("Invalid option: '{s}'", .{field_name});
                    return error.InvalidOption;
                }
            }

            return result;
        }

        pub fn usage(writer: *std.Io.Writer) !void {
            try writer.print("Usage: {s} [OPTION]...", .{info.program_name});
            try writer.print("\nOptions\n", .{});

            var name_pad: [max_name_length]u8 = undefined;
            var type_tag_pad: [max_type_length]u8 = undefined;

            inline for (from_options) |opt| {
                try writer.print("  ", .{});
                if (opt.short) |s| try writer.print("-{c}, ", .{s}) else try writer.print("    ", .{});

                padRight(opt.name, &name_pad);
                try writer.print("--{s}", .{name_pad});

                if (opt.is_array) {
                    type_tag_pad[0] = '[';
                    type_tag_pad[1] = ']';
                    padRight(@tagName(opt.type_tag), type_tag_pad[2..]);
                } else {
                    padRight(@tagName(opt.type_tag), &type_tag_pad);
                }
                try writer.print(" {s}", .{type_tag_pad});

                if (opt.description) |d| try writer.print(" {s}", .{d});

                try writer.print("\n", .{});
            }
        }

        inline fn err(comptime fmt: []const u8, args: anytype) void {
            if (!builtin.is_test) log.err(fmt, args);
        }
    };
}

fn validateType(comptime T: type) TypeTag {
    return switch (@typeInfo(T)) {
        else => @compileError(std.fmt.comptimePrint("Type not supported '{s}", .{@typeName(T)})),

        .bool => .bool,

        .int => |i| blk: {
            if (i.signedness == .signed) {
                break :blk .int;
            } else break :blk .uint;
        },

        .float => .float,

        .pointer => |ptr| blk: {
            if (ptr.size != .slice or ptr.child != u8 or !ptr.is_const) {
                @compileError(std.fmt.comptimePrint("Type not supported '{s}\nUse @as([]const u8, \"...\") for strings.", .{@typeName(T)}));
            }

            break :blk .string;
        },

        .@"enum" => .@"enum",
    };
}

const Tokenizer = struct {
    args: []const []const u8,
    current_arg_index: usize = 0,
    current_token: []const u8,
    eof: bool,

    pub fn init(args: []const []const u8) Tokenizer {
        const tokenizer = Tokenizer{
            .args = args,
            .current_arg_index = 0,
            .current_token = if (args.len > 0) args[0] else "",
            .eof = args.len == 0,
        };

        return tokenizer;
    }

    pub fn next(this: *Tokenizer) []const u8 {
        const result = this.current_token;

        this.current_arg_index += 1;
        if (this.current_arg_index < this.args.len) {
            this.current_token = this.args[this.current_arg_index];
        } else {
            this.current_token = "";
            this.eof = true;
        }

        return result;
    }

    pub fn eat(this: *Tokenizer, str: []const u8) ?[]const u8 {
        if (std.mem.startsWith(u8, this.current_token, str)) {
            this.current_token = this.current_token[str.len..];
            if (this.current_token.len == 0) {
                _ = this.next();
            }
            return str;
        }

        return null;
    }
};

fn padRight(str: []const u8, out_buf: []u8) void {
    assert(str.len <= out_buf.len);
    @memcpy(out_buf[0..str.len], str);
    @memset(out_buf[str.len..], ' ');
}

fn testParse(comptime OP: type, args: []const []const u8, expected: OP.Options, err: ?OP.Error) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const opt_or_err = OP.parse(args, allocator);
    if (err) |expected_err| {
        try std.testing.expectError(expected_err, opt_or_err);
    } else {
        const options = try opt_or_err;

        inline for (@typeInfo(OP.Options).@"struct".fields) |field| {
            const expected_value = @field(expected, field.name);
            const actual_value = @field(options, field.name);

            switch (@typeInfo(field.type)) {
                else => @compileError("Unsupported type " ++ @typeName(field.type)),

                .bool, .int, .float, .@"enum" => {
                    try std.testing.expectEqual(expected_value, actual_value);
                },

                .pointer => |ptr| {
                    if (ptr.size == .slice and ptr.child == u8 and ptr.is_const) {
                        try std.testing.expectEqualStrings(expected_value, actual_value);
                    } else {
                        @compileError("Unsupported pointer type (only []const u8 is supported)");
                    }
                },
            }
        }
    }
}

test "Option parser - strings and quotes" {
    const OP = OptionParser("optest", &.{
        option(@as([]const u8, ""), "string", 's', "string option"),
    });

    try testParse(OP, &.{"-sabc"}, .{ .string = "abc" }, null);
    try testParse(OP, &.{"-s abc"}, .{ .string = " abc" }, null);
    try testParse(OP, &.{ "-s", "abc" }, .{ .string = "abc" }, null);
    try testParse(OP, &.{ "-s", "" }, .{ .string = "" }, null);
    try testParse(OP, &.{"-s"}, .{}, error.MissingValue);
    try testParse(OP, &.{ "-s", "-xyz" }, .{ .string = "-xyz" }, null);
    try testParse(OP, &.{"-s-xyz"}, .{ .string = "-xyz" }, null);
    try testParse(OP, &.{ "-s", "foo", "-s", "bar" }, .{ .string = "bar" }, null);

    try testParse(OP, &.{"--stringabc"}, .{}, error.InvalidOption);
    try testParse(OP, &.{ "--string", "abc" }, .{}, error.MissingEq);
    try testParse(OP, &.{ "--string", "=abc" }, .{ .string = "abc" }, null);
    try testParse(OP, &.{ "--string=", "abc" }, .{ .string = "abc" }, null);
    try testParse(OP, &.{ "--string =", "abc" }, .{}, error.InvalidOption);
    try testParse(OP, &.{ "--string", "=", "abc" }, .{ .string = "abc" }, null);
    try testParse(OP, &.{ "--string", "= abc" }, .{ .string = " abc" }, null);
    try testParse(OP, &.{ "--string=", " abc" }, .{ .string = " abc" }, null);
    try testParse(OP, &.{ "--string", "=", " abc" }, .{ .string = " abc" }, null);
    try testParse(OP, &.{"--string="}, .{ .string = "" }, null);
    try testParse(OP, &.{ "--string", "=" }, .{ .string = "" }, null);
}

test "Option parser - multiple types" {
    const Color = enum { red, green, blue };

    const OP = OptionParser("optest", &.{
        option(@as([]const u8, ""), "string", 's', "string option"),
        option(Color.red, "enum", 'e', "enum option"),
        option(false, "bool", 'b', "bool option"),
        option(true, "bool2", 'c', "bool2 option"),
        option(@as(i32, -1), "int", 'i', "int option"),
        option(@as(u32, 0), "uint", 'u', "uint option"),
        option(@as(f32, 1.0), "float", 'f', "float option"),
    });

    // default values
    try testParse(OP, &.{}, .{}, null);

    // combined
    const combined_expected = OP.Options{
        .bool = true,
        .bool2 = false,
        .int = -42,
        .uint = 42,
        .float = 3.14,
        .string = "hello",
        .@"enum" = .blue,
    };
    try testParse(OP, &.{ "-b", "-c", "-i-42", "-u", "42", "-f", "3.14", "-s", "hello", "-e", "blue" }, combined_expected, null);
    try testParse(OP, &.{ "--bool", "--bool2", "--int=-42", "--uint", "=", "42", "--float=", "3.14", "--string=", "hello", "--enum=", "blue" }, combined_expected, null);

    // Single options
    try testParse(OP, &.{"-b"}, .{ .bool = true }, null);
    try testParse(OP, &.{"-btrue"}, .{ .bool = true }, null);
    try testParse(OP, &.{ "-b", "true" }, .{ .bool = true }, null);
    try testParse(OP, &.{"--bool"}, .{ .bool = true }, null);
    try testParse(OP, &.{"--bool=true"}, .{ .bool = true }, null);
    try testParse(OP, &.{ "--bool", "=", "true" }, .{ .bool = true }, null);
    try testParse(OP, &.{"-bfalse"}, .{ .bool = false }, null);
    try testParse(OP, &.{"--bool=false"}, .{ .bool = false }, null);
    try testParse(OP, &.{ "--bool", "=", "false" }, .{ .bool = false }, null);
    try testParse(OP, &.{"-bmaybe"}, .{}, error.InvalidBoolValue);
    try testParse(OP, &.{ "-b", "maybe" }, .{}, error.InvalidBoolValue);
    try testParse(OP, &.{"--bool=maybe"}, .{}, error.InvalidBoolValue);
    try testParse(OP, &.{ "--bool", "=", "maybe" }, .{}, error.InvalidBoolValue);

    try testParse(OP, &.{"-c"}, .{ .bool2 = false }, null);
    try testParse(OP, &.{"-cfalse"}, .{ .bool2 = false }, null);
    try testParse(OP, &.{ "-c", "false" }, .{ .bool2 = false }, null);
    try testParse(OP, &.{"--bool2"}, .{ .bool2 = false }, null);
    try testParse(OP, &.{"--bool2=false"}, .{ .bool2 = false }, null);
    try testParse(OP, &.{ "--bool2", "=", "false" }, .{ .bool2 = false }, null);
    try testParse(OP, &.{"-ctrue"}, .{ .bool2 = true }, null);
    try testParse(OP, &.{"--bool2=true"}, .{ .bool2 = true }, null);
    try testParse(OP, &.{ "--bool2", "=", "true" }, .{ .bool2 = true }, null);

    try testParse(OP, &.{"-i42"}, .{ .int = 42 }, null);
    try testParse(OP, &.{ "-i", "42" }, .{ .int = 42 }, null);
    try testParse(OP, &.{"--int=42"}, .{ .int = 42 }, null);
    try testParse(OP, &.{ "--int=", "42" }, .{ .int = 42 }, null);
    try testParse(OP, &.{ "--int", "=", "42" }, .{ .int = 42 }, null);
    try testParse(OP, &.{"-i-42"}, .{ .int = -42 }, null);
    try testParse(OP, &.{ "-i", "-42" }, .{ .int = -42 }, null);
    try testParse(OP, &.{"--int=-42"}, .{ .int = -42 }, null);
    try testParse(OP, &.{ "--int=", "-42" }, .{ .int = -42 }, null);
    try testParse(OP, &.{ "--int", "=", "-42" }, .{ .int = -42 }, null);
    try testParse(OP, &.{"-inotint"}, .{}, error.InvalidIntValue);
    try testParse(OP, &.{ "-i", "notint" }, .{}, error.InvalidIntValue);
    try testParse(OP, &.{"--int=notint"}, .{}, error.InvalidIntValue);
    try testParse(OP, &.{ "--int=", "notint" }, .{}, error.InvalidIntValue);
    try testParse(OP, &.{ "--int", "=", "notint" }, .{}, error.InvalidIntValue);

    try testParse(OP, &.{"-u42"}, .{ .uint = 42 }, null);
    try testParse(OP, &.{ "-u", "42" }, .{ .uint = 42 }, null);
    try testParse(OP, &.{"--uint=42"}, .{ .uint = 42 }, null);
    try testParse(OP, &.{ "--uint=", "42" }, .{ .uint = 42 }, null);
    try testParse(OP, &.{ "--uint", "=", "42" }, .{ .uint = 42 }, null);
    try testParse(OP, &.{"-unotuint"}, .{}, error.InvalidIntValue);
    try testParse(OP, &.{ "-u", "notuint" }, .{}, error.InvalidIntValue);
    try testParse(OP, &.{"--uint=notuint"}, .{}, error.InvalidIntValue);
    try testParse(OP, &.{ "--uint=", "notuint" }, .{}, error.InvalidIntValue);
    try testParse(OP, &.{ "--uint", "=", "notuint" }, .{}, error.InvalidIntValue);

    try testParse(OP, &.{"-f3.14"}, .{ .float = 3.14 }, null);
    try testParse(OP, &.{ "-f", "3.14" }, .{ .float = 3.14 }, null);
    try testParse(OP, &.{"--float=3.14"}, .{ .float = 3.14 }, null);
    try testParse(OP, &.{ "--float=", "3.14" }, .{ .float = 3.14 }, null);
    try testParse(OP, &.{ "--float", "=", "3.14" }, .{ .float = 3.14 }, null);
    try testParse(OP, &.{"-fnotfloat"}, .{}, error.InvalidFloatValue);
    try testParse(OP, &.{ "-f", "notfloat" }, .{}, error.InvalidFloatValue);
    try testParse(OP, &.{"--float=notfloat"}, .{}, error.InvalidFloatValue);
    try testParse(OP, &.{ "--float=", "notfloat" }, .{}, error.InvalidFloatValue);
    try testParse(OP, &.{ "--float", "=", "notfloat" }, .{}, error.InvalidFloatValue);

    try testParse(OP, &.{"-egreen"}, .{ .@"enum" = .green }, null);
    try testParse(OP, &.{ "-e", "green" }, .{ .@"enum" = .green }, null);
    try testParse(OP, &.{"--enum=green"}, .{ .@"enum" = .green }, null);
    try testParse(OP, &.{ "--enum=", "green" }, .{ .@"enum" = .green }, null);
    try testParse(OP, &.{ "--enum", "=", "green" }, .{ .@"enum" = .green }, null);

    try testParse(OP, &.{"-sabc"}, .{ .string = "abc" }, null);
    try testParse(OP, &.{"-s abc"}, .{ .string = " abc" }, null);
    try testParse(OP, &.{ "-s", "abc" }, .{ .string = "abc" }, null);
    try testParse(OP, &.{ "-s", "" }, .{ .string = "" }, null);
    try testParse(OP, &.{"-s"}, .{}, error.MissingValue);
    try testParse(OP, &.{ "-s", "-xyz" }, .{ .string = "-xyz" }, null);
    try testParse(OP, &.{"-s-xyz"}, .{ .string = "-xyz" }, null);
    try testParse(OP, &.{ "-s", "foo", "-s", "bar" }, .{ .string = "bar" }, null);

    try testParse(OP, &.{"--stringabc"}, .{}, error.InvalidOption);
    try testParse(OP, &.{ "--string", "abc" }, .{}, error.MissingEq);
    try testParse(OP, &.{ "--string", "=abc" }, .{ .string = "abc" }, null);
    try testParse(OP, &.{ "--string=", "abc" }, .{ .string = "abc" }, null);
    try testParse(OP, &.{ "--string =", "abc" }, .{}, error.InvalidOption);
    try testParse(OP, &.{ "--string", "=", "abc" }, .{ .string = "abc" }, null);
    try testParse(OP, &.{ "--string", "= abc" }, .{ .string = " abc" }, null);
    try testParse(OP, &.{ "--string=", " abc" }, .{ .string = " abc" }, null);
    try testParse(OP, &.{ "--string", "=", " abc" }, .{ .string = " abc" }, null);
    try testParse(OP, &.{"--string="}, .{ .string = "" }, null);
    try testParse(OP, &.{ "--string", "=" }, .{ .string = "" }, null);
}
