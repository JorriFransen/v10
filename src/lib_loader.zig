const std = @import("std");
const log = std.log.scoped(.lib_loader);

const core = @import("core");
const DynLib = core.DynLib;
const meta = core.meta;

const compile_options = @import("options");

pub const LoadOptions = struct {
    name_for_debugging: []const u8,

    search_prefix_opt: ?[]const u8 = null,
    stub_suffix_opt: ?[]const u8 = "Stub",
};

pub fn load(comptime T: type, lib_names: []const []const u8, comptime options: LoadOptions) ?DynLib {
    meta.expectStructType(T);

    var lib: DynLib = undefined;
    var lib_found = false;

    for (lib_names) |lib_name| {
        if (DynLib.open(lib_name)) |l| {
            lib = l;
            lib_found = true;
            break;
        } else |e| {
            log.warn("Failed to open library: '{s}', error: '{}'", .{ lib_name, e });
        }
    }

    var load_stubs = false;

    if (lib_found) {
        inline for (@typeInfo(T).@"struct".decls) |decl| {
            const decl_type = @TypeOf(@field(T, decl.name));
            const decl_type_info = @typeInfo(decl_type);

            if (decl_type_info == .pointer and @typeInfo(decl_type_info.pointer.child) == .@"fn") {
                const name = if (options.search_prefix_opt) |sp| sp ++ decl.name else decl.name;

                if (lib.lookup(decl_type, name)) |sym| {
                    @field(T, decl.name) = sym;
                } else {
                    load_stubs = true;
                    if (compile_options.internal_build) {
                        @panic("Unable to load function: '" ++ name ++ "'");
                    }
                }
            }
        }
    }

    if ((!lib_found or load_stubs) and options.stub_suffix_opt != null) {
        log.err("Failed to load library: '{s}'", .{options.name_for_debugging});
        loadStubs(T, options);
        log.warn("Loaded stubs for: '{s}'", .{options.name_for_debugging});
    }

    return if (lib_found) lib else null;
}

pub fn loadStubs(comptime T: type, comptime options: LoadOptions) void {
    inline for (@typeInfo(T).@"struct".decls) |decl| {
        const decl_type = @TypeOf(@field(T, decl.name));
        const decl_type_info = @typeInfo(decl_type);

        if (decl_type_info == .pointer and @typeInfo(decl_type_info.pointer.child) == .@"fn") {
            const stub_name = decl.name ++ options.stub_suffix_opt.?;
            @field(T, decl.name) = &@field(T, stub_name);
        }
    }
}
