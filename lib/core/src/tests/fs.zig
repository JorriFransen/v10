const std = @import("std");
const builtin = @import("builtin");

const fs = @import("../fs.zig");

const is_windows = builtin.os.tag == .windows;

test "cwd" {
    const t = std.testing;
    var _a = std.heap.ArenaAllocator.init(t.allocator);
    defer _a.deinit();
    const a = _a.allocator();

    var zig_tmp_dir = t.tmpDir(.{});
    defer zig_tmp_dir.cleanup();

    const tmp_cwd_rel_path = try std.fs.path.joinZ(a, &.{ ".zig-cache", "tmp", &zig_tmp_dir.sub_path });
    const tmp_cwd_rel_file_path = try std.fs.path.joinZ(a, &.{ tmp_cwd_rel_path, "file" });

    try t.expectEqual(std.Io.Dir.cwd().handle, fs.cwd().handle);

    const std_cwd = std.Io.Dir{ .handle = fs.cwd().handle };

    try t.expectEqual({}, std_cwd.access(t.io, tmp_cwd_rel_path, .{}));
    try t.expectError(error.FileNotFound, std_cwd.access(t.io, tmp_cwd_rel_file_path, .{}));

    const file_handle = try zig_tmp_dir.dir.createFile(t.io, "file", .{});
    file_handle.close(t.io);
    try t.expectEqual({}, std_cwd.access(t.io, tmp_cwd_rel_file_path, .{}));
}

test "existsAt" {
    const t = std.testing;
    var _a = std.heap.ArenaAllocator.init(t.allocator);
    defer _a.deinit();
    const a = _a.allocator();

    const win_console_attached = if (is_windows)
        @import("../os/win32/win32.zig").GetConsoleWindow() != null
    else
        false;

    var zig_tmp_dir = t.tmpDir(.{});
    defer zig_tmp_dir.cleanup();
    // std.debug.print("tmp dir: {s}\n", .{zig_tmp_dir.sub_path});

    const cwd_path = try std.process.currentPathAlloc(t.io, a);
    const abs_tmp_path = try std.fs.path.joinZ(a, &.{ cwd_path, ".zig-cache", "tmp", &zig_tmp_dir.sub_path });
    // std.debug.print("abs_tmp_path: {s}\n", .{abs_tmp_path});

    const tmp_dir = fs.Dir{ .handle = zig_tmp_dir.dir.handle };
    const tmp_parent_dir = fs.Dir{ .handle = zig_tmp_dir.parent_dir.handle };

    try t.expect(try tmp_dir.exists("."));
    try t.expect(try tmp_dir.exists(".."));
    try t.expect(!try tmp_dir.exists("x"));
    try t.expectError(error.BadPath, tmp_dir.exists(""));

    const abs_file_path = try std.fs.path.joinZ(a, &.{ abs_tmp_path, "file" });
    // std.debug.print("abs file path: {s}\n", .{abs_file_path});

    try t.expect(!try tmp_dir.exists("file"));
    try t.expect(!try tmp_dir.exists(abs_file_path));

    const file_handle = try zig_tmp_dir.dir.createFile(t.io, "file", .{});
    file_handle.close(t.io);

    try t.expect(!try tmp_dir.exists("file_link"));
    try t.expect(!try tmp_dir.exists("file_link/"));

    try zig_tmp_dir.dir.symLink(t.io, "file", "file_link", .{});

    try t.expect(try tmp_dir.exists("/"));
    try t.expect(try tmp_dir.exists("file"));
    try t.expect(try tmp_dir.exists("./file"));
    try t.expect(try tmp_dir.exists(abs_file_path));
    try t.expect(!try tmp_dir.exists("file/x"));
    try t.expect(!try tmp_dir.exists("file//x"));
    try t.expect(!try tmp_dir.exists("file/"));
    try t.expect(!try tmp_dir.exists("x/"));
    try t.expect(!try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ abs_file_path, "/x" }, 0)));
    try t.expect(!try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ abs_file_path, "/" }, 0)));

    var long_path_buf: [300:0]u8 = @splat('a');
    long_path_buf[long_path_buf.len] = 0;

    if (is_windows) {
        try t.expect(try tmp_dir.exists("C:\\"));
        try t.expect(try tmp_dir.exists("\\")); // unc
        try t.expectError(error.BadPath, tmp_dir.exists("//"));
        try t.expect(!try tmp_dir.exists(&long_path_buf));
        try t.expect(try tmp_dir.exists("FILE"));
        try t.expect(try tmp_dir.exists("FILE."));
        try t.expect(try tmp_dir.exists("FILE "));
        try t.expect(try tmp_dir.exists("file."));
        try t.expect(try tmp_dir.exists("file "));
        try t.expect(try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ abs_file_path, "." }, 0)));
        try t.expect(try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ abs_file_path, " " }, 0)));

        try t.expect(try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ "\\\\?\\", abs_file_path }, 0)));
        try t.expect(!try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ "\\\\?\\", abs_file_path, "." }, 0)));
        try t.expect(!try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ "\\\\?\\", abs_file_path, " " }, 0)));
        try t.expect(!try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ "\\\\?\\", abs_file_path, "\\" }, 0)));
        try t.expect(try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ "\\\\?\\", abs_tmp_path, "\\" }, 0)));
    } else {
        try t.expect(!try tmp_dir.exists("\\"));
        try t.expect(try tmp_dir.exists("//")); // root
        try t.expectError(error.NameTooLong, tmp_dir.exists(&long_path_buf));
        try t.expect(!try tmp_dir.exists("FILE"));
        try t.expect(!try tmp_dir.exists("FILE."));
        try t.expect(!try tmp_dir.exists("FILE "));
        try t.expect(!try tmp_dir.exists("file."));
        try t.expect(!try tmp_dir.exists("file "));
        try t.expect(!try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ abs_file_path, "." }, 0)));
        try t.expect(!try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ abs_file_path, " " }, 0)));
    }

    try t.expect(try tmp_dir.exists("file_link"));
    try t.expect(!try tmp_dir.exists("file_link/"));

    try t.expect(!try tmp_dir.exists("subdir"));
    try t.expect(!try tmp_dir.exists("subdir/"));

    try zig_tmp_dir.dir.createDir(t.io, "subdir", .default_dir);

    try t.expect(!try tmp_dir.exists("subdir_link"));
    try t.expect(!try tmp_dir.exists("subdir_link/"));
    try zig_tmp_dir.dir.symLink(t.io, "subdir", "subdir_link", .{ .is_directory = true });
    try zig_tmp_dir.dir.symLink(t.io, "subdir", "subdir_link2", .{ .is_directory = true });

    try t.expect(try tmp_dir.exists("subdir_link"));
    try t.expect(try tmp_dir.exists("subdir_link/"));

    try t.expect(try tmp_dir.exists("subdir"));
    try t.expect(try tmp_dir.exists("subdir/"));
    try t.expect(try tmp_dir.exists("subdir/."));
    try t.expect(try tmp_dir.exists("subdir/.."));
    try t.expect(try tmp_dir.exists("subdir//"));
    try t.expect(try tmp_dir.exists("subdir/../file"));

    try t.expect(try tmp_parent_dir.exists("../tmp"));
    try t.expect(try tmp_parent_dir.exists("../tmp/"));

    if (is_windows) {
        try t.expectError(error.BadPath, tmp_dir.exists("*"));
        try t.expectError(error.BadPath, tmp_dir.exists("a?b"));
        try t.expectError(error.BadPath, tmp_dir.exists("a*b"));
        try t.expectError(error.BadPath, tmp_dir.exists("<x."));
        try t.expectError(error.BadPath, tmp_dir.exists("control\x01"));
        try t.expectError(error.AccessDenied, tmp_dir.exists("aux"));
        try t.expectError(error.AccessDenied, tmp_dir.exists("com1"));

        if (win_console_attached)
            try t.expect(try tmp_dir.exists("con"))
        else
            try t.expectError(error.Unexpected, tmp_dir.exists("con"));

        try t.expect(try tmp_dir.exists("nul"));
    } else {
        try t.expect(!try tmp_dir.exists("*"));
        try t.expect(!try tmp_dir.exists("a?b"));
        try t.expect(!try tmp_dir.exists("a*b"));
        try t.expect(!try tmp_dir.exists("<x."));
        try t.expect(!try tmp_dir.exists("control\x01"));
        try t.expect(!try tmp_dir.exists("aux"));
        try t.expect(!try tmp_dir.exists("com1"));
        try t.expect(!try tmp_dir.exists("con"));
        try t.expect(!try tmp_dir.exists("nul"));
    }

    try zig_tmp_dir.dir.deleteFile(t.io, "file");
    try t.expect(!try tmp_dir.exists("file"));
    try t.expect(!try tmp_dir.exists(abs_file_path));
    try t.expect(!try tmp_dir.exists("file_link"));
    try t.expect(!try tmp_dir.exists("file_link/"));

    try t.expect(!try tmp_dir.exists(":"));
    try t.expect(!try tmp_dir.exists("::"));
    try t.expect(!try tmp_dir.exists("x:y"));

    try zig_tmp_dir.dir.deleteDir(t.io, "subdir");
    try t.expect(!try tmp_dir.exists("subdir_link"));
    try t.expect(!try tmp_dir.exists("subdir_link/"));
    try t.expect(!try tmp_dir.exists("subdir_link2"));
    try t.expect(!try tmp_dir.exists("subdir_link2/"));

    try zig_tmp_dir.dir.symLink(t.io, "loop_b", "loop_a", .{});
    try zig_tmp_dir.dir.symLink(t.io, "loop_a", "loop_b", .{});

    try t.expectError(error.SymLinkNotResolved, tmp_dir.exists("loop_a"));
}
