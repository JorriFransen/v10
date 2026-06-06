pub const Protocol = struct {
    name: []const u8,
    interfaces: []Interface,
    description: Description,
};

pub const Interface = struct {
    name: []const u8,
    version: u32,
    description: Description,
    requests: []Message,
    events: []Message,
    enums: []Enum,

    /// valid after resolving
    zig_name: []const u8 = "XXX_UNRESOLVED_INTERFACE_NAME__X_X_X_",
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
    zig_enum_name: ?[]const u8 = null,
    /// valid after resolving
    zig_interface_name: ?[]const u8 = null,
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

    name: []const u8,
    since: u32,
    deprecated_since: ?u32,
    entries: []Entry,
    description: Description,
    is_bitfield: bool,

    // valid after resolving
    zig_name: []const u8 = "XXX_UNRESOLVED_ENUM_NAME__X_X_X_",
    // valid after resolving
    zig_int_type: []const u8 = "XXX_UNRESOLVED_ENUM_INT_TYPE__X_X_X_",
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
    int,
    uint,
    fixed,
    string,
    object,
    new_id,
    array,
    fd,
};
