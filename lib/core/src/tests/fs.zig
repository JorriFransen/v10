const std = @import("std");

const fs = @import("../fs.zig");

test "existsAt" {
    const t = std.testing;

    var zig_tmp_dir = t.tmpDir(.{});
    defer zig_tmp_dir.cleanup();

    const tmp_dir = fs.Dir{ .handle = zig_tmp_dir.dir.handle };

    try t.expect(try tmp_dir.exists("."));
    try t.expect(try tmp_dir.exists(".."));
    try t.expect(!try tmp_dir.exists("x"));

    _ = try zig_tmp_dir.dir.createFile(t.io, "file", .{});
    try t.expect(try tmp_dir.exists("file"));
    try zig_tmp_dir.dir.deleteFile(t.io, "file");
    try t.expect(!try tmp_dir.exists("file"));
}
