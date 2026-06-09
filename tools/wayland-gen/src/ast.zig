const std = @import("std");

pub const Protocol = struct {
    name: []const u8,
    interfaces: std.array_hash_map.String(Interface),
    description: Description,

    /// valid after parsing
    xml_path: []const u8 = "XXX_UNINITIALIZED_XML_PATH__X_X_X_",
    /// valid after resolving
    protocol_imports: std.array_hash_map.String(*const Protocol),
};

pub const Interface = struct {
    name: []const u8,
    version: u32,
    description: Description,
    requests: []Message,
    events: []Message,
    enums: std.array_hash_map.String(Enum),

    /// valid after resolving
    zig_name: []const u8 = "XXX_UNRESOLVED_INTERFACE_NAME__X_X_X_",
    /// valid after resolving
    has_destructor: bool = false,
};

pub const Message = struct {
    name: []const u8,
    since: u32,
    deprecated_since: ?u32,
    args: []Arg,
    description: Description,
    is_destructor: bool,

    /// valid after resolving
    zig_name: []const u8 = "XXX_UNRESOLVED_MESSAGE_NAME__X_X_X_",
    /// valid after resolving (request)
    zig_constructor_interface: ?[]const u8 = null,
    /// valid after resolving (request)
    is_anonymous_constructor: bool = false,
    /// valid after resolving
    fd_count: usize = 0,
    /// valid after resolving
    signature: []const u8 = "XXX_UNRESOLVED_MESSAGE_SIGNATURE__X_X_X_",
};

pub const Arg = struct {
    name: []const u8,
    type: Type,
    enum_name: ?[]const u8,
    interface_name: ?[]const u8,
    summary: []const u8,

    /// valid after resolving
    zig_name: []const u8 = "XXX_UNRESOLVED_ARG_NAME__X_X_X_",
    /// valid after resolving
    enum_type: ?*const Enum = null,
    /// valid after resolving
    zig_interface_name: ?[]const u8 = null,
    /// valid after resolving
    import_name: ?[]const u8 = null,
};

pub const Enum = struct {
    pub const Entry = struct {
        name: []const u8,
        since: u32,
        value: []const u8,
        description: Description,

        // valid after resolving
        zig_name: []const u8 = "XXX_UNRESOLVED_ENUM_ENTRY_NAME__X_X_X_",
    };

    pub const BitfieldEntry = struct {
        n: u32,
        name_index: u32,
    };

    name: []const u8,
    since: u32,
    deprecated_since: ?u32,
    entries: []Entry,
    description: Description,
    is_bitfield: bool,

    /// valid after resolving
    interface: *const Interface = undefined,
    /// valid after resolving
    zig_name: []const u8 = "XXX_UNRESOLVED_ENUM_NAME__X_X_X_",
    /// valid after resolving
    zig_int_type: []const u8 = "XXX_UNRESOLVED_ENUM_INT_TYPE__X_X_X_",
    /// valid after resolving
    single_bit_bitfield_entries: []BitfieldEntry = &.{},
    /// valid after resolving
    multi_bit_bitfield_entries: []BitfieldEntry = &.{},
};

pub const Description = struct {
    summary: []const u8 = "",
    text: []const u8 = "",
};

pub const Type = struct {
    tag: TypeTag,
    allow_null: bool,
};

pub const TypeTag = enum {
    i,
    u,
    f,
    s,
    o,
    n,
    a,
    h,
};
