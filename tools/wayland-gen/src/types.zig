pub const Protocol = struct {
    name: []const u8,
    interfaces: []Interface,
};

pub const Interface = struct {
    name: []const u8,
    version: u32,
    summary: []const u8,
    description: []const u8,

    requests: []Request,
    events: []Event,
    enums: []Enum,
};

pub const Request = struct {
    name: []const u8,
    destructor: bool,
    since: u32,
    summary: []const u8,
    description: []const u8,
    args: []Arg,
};

pub const Event = struct {
    name: []const u8,
    destructor: bool,
    since: u32,
    summary: []const u8,
    description: []const u8,
    args: []Arg,
};

pub const Enum = struct {
    name: []const u8,
    bitfield: bool,
    since: u32,
    summary: []const u8,
    description: []const u8,
    entries: []Entry,

    resolved_type: ?Type,

    pub const Entry = struct {
        name: []const u8,
        since: u32,
        value_str: []const u8,
        summary: []const u8,
        description: []const u8,
        generated: bool = false,
    };
};

pub const Arg = struct {
    name: []const u8,
    type: Type,
    enum_name: ?[]const u8,
    allow_null: bool,
    interface: ?[]const u8,
    summary: []const u8,
};

pub const Type = enum {
    int,
    uint,
    fixed,
    string,
    object,
    new_id,
    array,
    fd,
};
