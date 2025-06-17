const std = @import("std");
const log = std.log.scoped(.Resource);

const Allocator = std.mem.Allocator;

const assert = std.debug.assert;

pub const ResourceData = union(enum) {
    model_file: struct {
        pub const Kind = enum {
            obj,
        };

        kind: Kind,
        data: []const u8,
    },
};

pub const LoadResourceError = error{
    OutOfMemory,
    UnsupportedFileExtension,
} || std.fs.File.OpenError;

/// Load named resource into memory
pub fn load(allocator: Allocator, name: []const u8) LoadResourceError!ResourceData {
    const file = std.fs.cwd().openFile(name, .{}) catch |err| switch (err) {
        else => return err,
        error.FileNotFound => {
            log.err("Unable to open resource file: '{s}'", .{name});
            return error.FileNotFound;
        },
    };
    defer file.close();

    const file_size = file.getEndPos() catch return error.Unexpected;

    var file_buf = allocator.alloc(u8, file_size + 1) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };

    const read_size = file.readAll(file_buf) catch return error.Unexpected;
    assert(file_size == read_size);
    file_buf[read_size] = 0;
    file_buf = file_buf[0..file_size];

    const kind = if (std.mem.endsWith(u8, name, ".obj"))
        .obj
    else
        return error.UnsupportedFileExtension;

    return .{ .model_file = .{ .kind = kind, .data = file_buf } };
}
