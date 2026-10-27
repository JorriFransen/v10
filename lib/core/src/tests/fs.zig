const std = @import("std");
const t = std.testing;
const builtin = @import("builtin");

const fs = @import("../fs.zig");
const win32 = @import("../os/win32/win32.zig");

const is_windows = builtin.os.tag == .windows;

test "cwd" {
    var _a = std.heap.ArenaAllocator.init(t.allocator);
    defer _a.deinit();
    const a = _a.allocator();

    var zig_tmp_dir = t.tmpDir(.{});
    defer zig_tmp_dir.cleanup();

    const tmp_cwd_rel_path = try std.fs.path.joinZ(a, &.{ ".zig-cache", "tmp", &zig_tmp_dir.sub_path });
    const tmp_cwd_rel_file_path = try std.fs.path.joinZ(a, &.{ tmp_cwd_rel_path, "file" });

    const cwd = fs.cwd();

    try t.expectEqual(std.Io.Dir.cwd().handle, cwd.handle);

    try t.expect(try testAccess(cwd.handle, tmp_cwd_rel_path));
    try t.expectError(error.FileNotFound, testAccess(cwd.handle, tmp_cwd_rel_file_path));

    const file_handle = try zig_tmp_dir.dir.createFile(t.io, "file", .{});
    file_handle.close(t.io);
    try t.expect(try testAccess(cwd.handle, tmp_cwd_rel_file_path));
}

test "existsAt" {
    var _a = std.heap.ArenaAllocator.init(t.allocator);
    defer _a.deinit();
    const a = _a.allocator();

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
    try t.expectError(error.NameTooLong, tmp_dir.exists(&long_path_buf));

    if (is_windows) {
        try t.expect(try tmp_dir.exists("C:\\"));
        try t.expect(try tmp_dir.exists("\\")); // unc
        try t.expectError(error.BadPath, tmp_dir.exists("//"));
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
        try t.expect(!try tmp_dir.exists("FILE"));
        try t.expect(!try tmp_dir.exists("FILE."));
        try t.expect(!try tmp_dir.exists("FILE "));
        try t.expect(!try tmp_dir.exists("file."));
        try t.expect(!try tmp_dir.exists("file "));
        try t.expect(!try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ abs_file_path, "." }, 0)));
        try t.expect(!try tmp_dir.exists(try std.mem.concatWithSentinel(a, u8, &.{ abs_file_path, " " }, 0)));
    }

    try t.expect(!try tmp_dir.exists("subdir"));
    try t.expect(!try tmp_dir.exists("subdir/"));

    try zig_tmp_dir.dir.createDir(t.io, "subdir", .default_dir);

    try t.expect(try tmp_dir.exists("subdir"));
    try t.expect(try tmp_dir.exists("subdir/"));
    try t.expect(try tmp_dir.exists("subdir/."));
    try t.expect(try tmp_dir.exists("subdir/.."));
    try t.expect(try tmp_dir.exists("subdir//"));
    try t.expect(try tmp_dir.exists("subdir/../file"));

    try t.expect(try tmp_parent_dir.exists("../tmp"));
    try t.expect(try tmp_parent_dir.exists("../tmp/"));

    try t.expect(!try tmp_dir.exists("*"));
    try t.expect(!try tmp_dir.exists("a?b"));
    try t.expect(!try tmp_dir.exists("a*b"));
    try t.expect(!try tmp_dir.exists("<x."));
    try t.expect(!try tmp_dir.exists("control\x01"));
    try t.expect(!try tmp_dir.exists(":"));
    try t.expect(!try tmp_dir.exists("::"));
    try t.expect(!try tmp_dir.exists("x:y"));

    if (is_windows) {
        try t.expectError(error.BadPath, tmp_dir.exists("//"));
        try t.expect(try tmp_dir.exists("nul"));
    } else {
        try t.expect(try tmp_dir.exists("//"));
        try t.expect(!try tmp_dir.exists("aux"));
        try t.expect(!try tmp_dir.exists("com1"));
        try t.expect(!try tmp_dir.exists("con"));
        try t.expect(!try tmp_dir.exists("nul"));
    }

    try zig_tmp_dir.dir.deleteFile(t.io, "file");
    try t.expect(!try tmp_dir.exists("file"));
    try t.expect(!try tmp_dir.exists(abs_file_path));

    try zig_tmp_dir.dir.deleteDir(t.io, "subdir");
}

test "existsAt symlinks" {
    var zig_tmp_dir = t.tmpDir(.{});
    defer zig_tmp_dir.cleanup();

    try skipIfNoSymLinkPermission(zig_tmp_dir.dir);

    const tmp_dir = fs.Dir{ .handle = zig_tmp_dir.dir.handle };

    const file_handle = try zig_tmp_dir.dir.createFile(t.io, "file", .{});
    file_handle.close(t.io);
    try t.expect(try tmp_dir.exists("file"));

    try t.expect(!try tmp_dir.exists("file_link"));
    try t.expect(!try tmp_dir.exists("file_link/"));

    try zig_tmp_dir.dir.symLink(t.io, "file", "file_link", .{});

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

    try zig_tmp_dir.dir.deleteFile(t.io, "file");
    try t.expect(!try tmp_dir.exists("file"));
    try t.expect(!try tmp_dir.exists("file_link"));
    try t.expect(!try tmp_dir.exists("file_link/"));

    try zig_tmp_dir.dir.deleteDir(t.io, "subdir");
    try t.expect(!try tmp_dir.exists("subdir_link"));
    try t.expect(!try tmp_dir.exists("subdir_link/"));
    try t.expect(!try tmp_dir.exists("subdir_link2"));
    try t.expect(!try tmp_dir.exists("subdir_link2/"));

    try zig_tmp_dir.dir.symLink(t.io, "loop_a", "loop_b", .{});
    try zig_tmp_dir.dir.symLink(t.io, "loop_b", "loop_a", .{});

    try t.expectError(error.SymLinkNotResolved, tmp_dir.exists("loop_a"));
}

test "openDirAt" {
    var _a = std.heap.ArenaAllocator.init(t.allocator);
    defer _a.deinit();
    const a = _a.allocator();

    var zig_tmp_dir = t.tmpDir(.{});
    defer zig_tmp_dir.cleanup();

    const tmp_cwd_rel_path = try std.fs.path.joinZ(a, &.{ ".zig-cache", "tmp", &zig_tmp_dir.sub_path });

    const cwd_path = try std.process.currentPathAlloc(t.io, a);
    const abs_tmp_path = try std.fs.path.joinZ(a, &.{ cwd_path, ".zig-cache", "tmp", &zig_tmp_dir.sub_path });

    try zig_tmp_dir.dir.createDir(t.io, "subdir", .default_dir);
    const file = try zig_tmp_dir.dir.createFile(t.io, "file", .{});
    file.close(t.io);

    const tmp_dir = try fs.cwd().openDir(tmp_cwd_rel_path, .{});
    defer tmp_dir.close();

    {
        var long_name_buf: [300:0]u8 = @splat('a');
        long_name_buf[long_name_buf.len] = 0;

        try t.expect(try testAccess(tmp_dir.handle, "subdir"));
        try t.expect(try testAccess(tmp_dir.handle, "subdir/"));
        try t.expect(try testAccess(tmp_dir.handle, "subdir/."));
        try t.expect(try testAccess(tmp_dir.handle, "subdir/.."));
        try t.expect(try testAccess(tmp_dir.handle, "subdir//"));
        try t.expect(try testAccess(tmp_dir.handle, abs_tmp_path));
        try t.expect(try testAccess(tmp_dir.handle, "subdir"));
        try t.expectError(error.FileNotFound, testAccess(tmp_dir.handle, "x"));
        try t.expectError(error.FileNotFound, tmp_dir.openDir("x", .{}));
        try t.expectError(error.NotDir, tmp_dir.openDir("file", .{}));
        try t.expectError(error.NameTooLong, tmp_dir.openDir(&long_name_buf, .{}));

        const dir = try tmp_dir.openDir(".", .{});
        defer dir.close();
        try t.expect(try testAccess(dir.handle, "subdir"));
        try t.expect(try testAccess(dir.handle, "subdir/"));
        try t.expect(try testAccess(dir.handle, "subdir/."));
        try t.expect(try testAccess(dir.handle, "subdir/.."));
        try t.expect(try testAccess(dir.handle, "subdir//"));
        try t.expect(try testAccess(dir.handle, abs_tmp_path));
        try t.expectError(error.FileNotFound, testAccess(dir.handle, "x"));
        try t.expectError(error.FileNotFound, dir.openDir("x", .{}));
        try t.expectError(error.NotDir, dir.openDir("file", .{}));
        try t.expectError(error.NameTooLong, dir.openDir(&long_name_buf, .{}));

        const sub_dir = try tmp_dir.openDir("subdir", .{});
        defer sub_dir.close();
        try t.expect(try testAccess(sub_dir.handle, "."));
        try t.expectError(error.FileNotFound, testAccess(sub_dir.handle, "x"));

        try t.expectError(error.FileNotFound, tmp_dir.openDir("::", .{}));
        try t.expectError(error.FileNotFound, tmp_dir.openDir("x:y", .{}));

        if (is_windows) {
            try t.expectError(error.BadPath, tmp_dir.openDir("", .{}));
            try t.expectError(error.FileNotFound, tmp_dir.openDir("file/x", .{}));
            try t.expectError(error.BadPath, tmp_dir.openDir("nul", .{}));
            try t.expectError(error.BadPath, tmp_dir.openDir("*", .{}));
            try t.expectError(error.BadPath, tmp_dir.openDir("a?b", .{}));
            try t.expectError(error.BadPath, tmp_dir.openDir("a*b", .{}));
            try t.expectError(error.BadPath, tmp_dir.openDir("<x.", .{}));
            try t.expectError(error.BadPath, tmp_dir.openDir("control\x01", .{}));
            try t.expectError(error.BadPath, tmp_dir.openDir(":", .{}));
        } else {
            try t.expectError(error.FileNotFound, tmp_dir.openDir("", .{}));
            try t.expectError(error.NotDir, tmp_dir.openDir("file/x", .{}));
            try t.expectError(error.FileNotFound, tmp_dir.openDir("nul", .{}));
            try t.expectError(error.FileNotFound, tmp_dir.openDir("*", .{}));
            try t.expectError(error.FileNotFound, tmp_dir.openDir("a?b", .{}));
            try t.expectError(error.FileNotFound, tmp_dir.openDir("a*b", .{}));
            try t.expectError(error.FileNotFound, tmp_dir.openDir("<x.", .{}));
            try t.expectError(error.FileNotFound, tmp_dir.openDir("control\x01", .{}));
            try t.expectError(error.FileNotFound, tmp_dir.openDir(":", .{}));
        }
    }
}

test "openDirAt symlinks" {
    var _a = std.heap.ArenaAllocator.init(t.allocator);
    defer _a.deinit();
    const a = _a.allocator();

    var zig_tmp_dir = t.tmpDir(.{});
    defer zig_tmp_dir.cleanup();

    try skipIfNoSymLinkPermission(zig_tmp_dir.dir);

    const tmp_cwd_rel_path = try std.fs.path.joinZ(a, &.{ ".zig-cache", "tmp", &zig_tmp_dir.sub_path });

    try zig_tmp_dir.dir.createDir(t.io, "subdir", .default_dir);
    try zig_tmp_dir.dir.createDir(t.io, "subdir/nested", .default_dir);
    try zig_tmp_dir.dir.symLink(t.io, "subdir", "subdir_link", .{ .is_directory = true });
    const file_in_subdir = try zig_tmp_dir.dir.createFile(t.io, "subdir/file_in_subdir", .{});
    file_in_subdir.close(t.io);

    const file = try zig_tmp_dir.dir.createFile(t.io, "file", .{});
    file.close(t.io);
    try zig_tmp_dir.dir.symLink(t.io, "file", "file_link", .{});

    try zig_tmp_dir.dir.symLink(t.io, "dir_loop_a", "dir_loop_b", .{ .is_directory = true });
    try zig_tmp_dir.dir.symLink(t.io, "dir_loop_b", "dir_loop_a", .{ .is_directory = true });
    try zig_tmp_dir.dir.symLink(t.io, "loop_a", "loop_b", .{});
    try zig_tmp_dir.dir.symLink(t.io, "loop_b", "loop_a", .{});

    const tmp_dir = try fs.cwd().openDir(tmp_cwd_rel_path, .{});
    defer tmp_dir.close();

    {
        const subdir = try tmp_dir.openDir("subdir", .{ .follow_symlinks = false });
        defer subdir.close();
        try t.expect(try testAccess(subdir.handle, "file_in_subdir"));
        try t.expectError(error.FileNotFound, testAccess(subdir.handle, "x"));

        const subdir_link = try tmp_dir.openDir("subdir_link", .{});
        defer subdir_link.close();
        try t.expect(try testAccess(subdir_link.handle, "file_in_subdir"));
        try t.expectError(error.FileNotFound, testAccess(subdir_link.handle, "x"));

        const subdir_link2 = try tmp_dir.openDir("subdir_link/", .{ .follow_symlinks = true });
        defer subdir_link2.close();
        try t.expect(try testAccess(subdir_link2.handle, "file_in_subdir"));
        try t.expectError(error.FileNotFound, testAccess(subdir_link2.handle, "x"));

        const subdir_link3 = try tmp_dir.openDir("subdir_link/.", .{ .follow_symlinks = true });
        defer subdir_link3.close();
        try t.expect(try testAccess(subdir_link3.handle, "file_in_subdir"));
        try t.expectError(error.FileNotFound, testAccess(subdir_link3.handle, "x"));

        try t.expectError(error.NotDir, tmp_dir.openDir("file_link", .{ .follow_symlinks = true }));

        const nested = try tmp_dir.openDir("subdir_link/nested", .{ .follow_symlinks = true });
        nested.close();

        const nested_nofollow = try tmp_dir.openDir("subdir_link/nested", .{ .follow_symlinks = false });
        nested_nofollow.close();

        try t.expectError(error.SymLinkNotResolved, tmp_dir.openDir("dir_loop_a", .{}));
        try t.expectError(error.SymLinkNotResolved, tmp_dir.openDir("dir_loop_b", .{}));

        try t.expectError(error.NotDir, tmp_dir.openDir("loop_a", .{ .follow_symlinks = false }));
        try t.expectError(error.NotDir, tmp_dir.openDir("loop_b", .{ .follow_symlinks = false }));

        if (is_windows) {
            try t.expectError(error.SymLinkNotResolved, tmp_dir.openDir("dir_loop_a", .{ .follow_symlinks = false }));
            try t.expectError(error.SymLinkNotResolved, tmp_dir.openDir("dir_loop_b", .{ .follow_symlinks = false }));

            try t.expectError(error.SymLinkNotResolved, tmp_dir.openDir("subdir_link", .{ .follow_symlinks = false }));

            try t.expectError(error.NotDir, tmp_dir.openDir("loop_a", .{}));
            try t.expectError(error.NotDir, tmp_dir.openDir("loop_b", .{}));
        } else {
            try t.expectError(error.NotDir, tmp_dir.openDir("dir_loop_a", .{ .follow_symlinks = false }));
            try t.expectError(error.NotDir, tmp_dir.openDir("dir_loop_b", .{ .follow_symlinks = false }));

            try t.expectError(error.NotDir, tmp_dir.openDir("subdir_link", .{ .follow_symlinks = false }));

            try t.expectError(error.SymLinkNotResolved, tmp_dir.openDir("loop_a", .{}));
            try t.expectError(error.SymLinkNotResolved, tmp_dir.openDir("loop_b", .{}));
        }

        try zig_tmp_dir.dir.deleteTree(t.io, "subdir");
        try t.expectError(error.FileNotFound, tmp_dir.openDir("subdir_link", .{}));

        if (is_windows) {
            try t.expectError(error.SymLinkNotResolved, tmp_dir.openDir("subdir_link", .{ .follow_symlinks = false }));
        } else {
            try t.expectError(error.NotDir, tmp_dir.openDir("subdir_link", .{ .follow_symlinks = false }));
        }
    }
}

fn testAccess(dir_handle: fs.Handle, path: [:0]const u8) !bool {
    const std_dir = std.Io.Dir{ .handle = dir_handle };

    if (is_windows) {
        // Access does not work on wine with dir handle + relative path
        const file_handle = try std_dir.openFile(t.io, path, .{});
        file_handle.close(t.io);
        return true;
    } else {
        try std_dir.access(t.io, path, .{});
        return true;
    }
}

fn skipIfNoSymLinkPermission(zig_tmp_dir: std.Io.Dir) !void {
    if (!is_windows) return;

    var was_enabled: win32.NT.BOOLEAN = undefined;
    _ = win32.NT.RtlAdjustPrivilege(.CREATE_SYMBOLIC_LINK_PRIVILEGE, .TRUE, .FALSE, &was_enabled);

    zig_tmp_dir.symLink(t.io, "probe_target", "probe_link", .{}) catch |e| switch (e) {
        error.PermissionDenied => return error.SkipZigTest,
        else => return e,
    };

    try zig_tmp_dir.deleteFile(t.io, "probe_link");
}
