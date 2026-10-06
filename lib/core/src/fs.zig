const std = @import("std");
const builtin = @import("builtin");

const assert = @import("assert.zig").assert;
const mem = @import("mem/mem.zig");

const os = @import("os/os.zig").current.fs;

pub const Handle = os.Handle;

pub const path_sep = os.path_sep;
pub const path_sep_str = os.path_sep_str;
/// Including null
pub const max_path_bytes = os.max_path_bytes;
/// Not including null
pub const max_name_bytes = os.max_name_bytes;

pub const Error = OpenDirAtError || ExistsAtError || DirIteratorError || CreateDirAtError;

pub const File = struct {
    handle: Handle,
};

pub const Dir = struct {
    handle: Handle,

    pub inline fn openDir(this: Dir, path: [:0]const u8, options: OpenDirAtOptions) OpenDirAtError!Dir {
        return openDirAt(this, path, options);
    }

    pub inline fn createDir(this: Dir, dir_name: [:0]const u8, options: CreateDirAtOptions) CreateDirAtError!void {
        return createDirAt(this, dir_name, options);
    }

    pub inline fn createDirParents(this: Dir, dir_path: [:0]const u8, options: CreateDirAtOptions) CreateDirAtError!void {
        return CreateDirParentsAt(this, dir_path, options);
    }

    pub inline fn exists(this: Dir, path: [:0]const u8) ExistsAtError!bool {
        return existsAt(this, path);
    }

    pub inline fn close(this: Dir) void {
        os.close(this.handle);
    }

    // TODO: Remove
    /// Temporary!
    pub inline fn stdDir(this: Dir) std.Io.Dir {
        return .{ .handle = this.handle };
    }
};

pub const Permissions = os.Permissions;

pub const isSep = os.isSep;

pub const cwd = os.cwd;

pub const ExistsAtError = error{
    AccessDenied,
    BadPath,
    IO,
    NameTooLong,
    OutOfMemory,
    PermissionDenied,
    SymLinkNotResolved,

    Unexpected,
};
pub const existsAt = os.existsAt;

pub const OpenDirAtError = error{
    AccessDenied,
    AlreadyExists,
    BadPath,
    DeviceBusy,
    FileNotFound,
    Interrupted,
    NameTooLong,
    NoSpace,
    NotDir,
    OutOfMemory,
    PermissionDenied,
    ProcessHandleQuotaExceeded,
    ReadOnlyFileSystem,
    SymLinkNotResolved,
    SystemHandleQuotaExceeded,

    Unexpected,
};
pub const OpenDirAtOptions = struct {
    iterate: bool = false,
    follow_symlinks: bool = true,
};
pub const openDirAt = os.openDirAt;

pub const CreateDirAtError = error{
    AccessDenied,
    AlreadyExists,
    BadPath,
    FileNotFound,
    MissingIdMapping,
    NameTooLong,
    NoSpace,
    NotDir,
    OutOfMemory,
    PermissionDenied,
    ReadOnlyFileSystem,
    SymLinkNotResolved,

    Unexpected,
};
pub const CreateDirAtOptions = struct {
    permissions: Permissions = .default_dir,
};
pub const createDirAt = os.createDirAt;

pub fn CreateDirParentsAt(dir: Dir, dir_path: [:0]const u8, options: CreateDirAtOptions) CreateDirAtError!void {
    if (createDirAt(dir, dir_path, options)) {
        return;
    } else |e| switch (e) {
        else => return e,
        error.FileNotFound => {},
    }

    var it = try PathIterator.init(dir_path);
    _ = it.last();

    var path_buf: [max_path_bytes]u8 = undefined;

    while (it.prev()) |elem| {
        if (createDirAt(dir, mem.copySentinel(&path_buf, elem.path, 0), options)) {
            break;
        } else |e| switch (e) {
            else => return e,
            error.FileNotFound => {},
        }
    }

    while (it.next()) |elem| {
        try createDirAt(dir, mem.copySentinel(&path_buf, elem.path, 0), options);
    }
}

pub const DirIteratorInitError = error{ SeekFailed, InvalidHandle };
pub const DirIteratorNextError = error{ InvalidHandle, MalformedDirEntry, Unexpected };
pub const DirIteratorError = DirIteratorInitError || DirIteratorNextError;
pub const DirIteratorOptions = struct {
    reset_handle_pos: bool = true,
};
pub const DirIteratorEntry = struct {
    name: [:0]const u8,
    type: Type,

    pub const Type = enum {
        unknown,
        pipe,
        char,
        dir,
        block,
        file,
        link,
        socket,
        whiteout,
    };
};
pub const DirIterator = os.DirIterator;

pub const PathIterator = struct {
    path: []const u8,
    current_start: usize,
    current_end: usize,
    root_end: usize,

    pub const Elem = struct {
        /// From begin, inluding this element
        path: []const u8,

        name: []const u8,
    };

    pub fn init(path: []const u8) error{BadPath}!PathIterator {
        if (path.len == 0) return error.BadPath;

        if (builtin.os.tag == .linux) {
            if (!isSep(path[0])) {
                return .{ .path = path, .current_start = 0, .current_end = 0, .root_end = 0 };
            } else {
                var start: usize = 1;
                while (start < path.len and isSep(path[start])) start += 1;
                return .{ .path = path, .current_start = start, .current_end = start, .root_end = start };
            }
        } else if (builtin.os.tag == .windows) {
            const parsed_path = try os.parsePath(path);
            const root_end = parsed_path.root_end;

            return .{ .path = path, .current_start = root_end, .current_end = root_end, .root_end = root_end };
        } else {
            @compileError("Unsupported os: " ++ @tagName(builtin.os.tag));
        }
    }

    pub fn next(this: *PathIterator) ?Elem {
        if (this.current_end >= this.path.len) return null;

        var new_start = this.current_end;
        while (new_start < this.path.len and isSep(this.path[new_start])) new_start += 1;

        if (new_start >= this.path.len) return null;

        var new_end = new_start + 1;
        while (new_end < this.path.len and !isSep(this.path[new_end])) new_end += 1;

        this.current_start = new_start;
        this.current_end = new_end;

        return .{
            .path = this.path[0..this.current_end],
            .name = this.path[this.current_start..this.current_end],
        };
    }

    pub fn prev(this: *PathIterator) ?Elem {
        if (this.current_start <= this.root_end) return null;

        var new_end = this.current_start - 1;
        while (new_end > this.root_end and isSep(this.path[new_end - 1])) new_end -= 1;

        var new_start = new_end;
        while (new_start > this.root_end and !isSep(this.path[new_start - 1])) new_start -= 1;

        this.current_end = new_end;
        this.current_start = new_start;

        return .{
            .path = this.path[0..this.current_end],
            .name = this.path[this.current_start..this.current_end],
        };
    }

    pub fn first(this: *PathIterator) ?Elem {
        if (this.path.len == 0 or this.path.len == this.root_end) return null;

        this.current_start = this.root_end;

        var new_end = this.current_start + 1;
        while (new_end < this.path.len and !isSep(this.path[new_end])) new_end += 1;
        this.current_end = new_end;

        return .{
            .path = this.path[0..this.current_end],
            .name = this.path[this.current_start..this.current_end],
        };
    }

    pub fn last(this: *PathIterator) ?Elem {
        if (this.path.len == 0 or this.path.len == this.root_end) return null;

        if (isSep(this.path[this.path.len - 1])) {
            var end: usize = this.path.len - 1;
            while (end > this.root_end and isSep(this.path[end - 1])) end -= 1;
            this.current_end = end;
        } else {
            this.current_end = this.path.len;
        }

        var new_start = this.current_end;
        while (new_start > this.root_end and !isSep(this.path[new_start - 1])) new_start -= 1;

        this.current_start = new_start;

        return .{
            .path = this.path[0..this.current_end],
            .name = this.path[this.current_start..this.current_end],
        };
    }

    pub fn root(this: *PathIterator) ?[]const u8 {
        if (this.root_end == 0) return null;

        if (builtin.os.tag == .windows) {
            return this.path[0..this.root_end];
        } else {
            return "/";
        }
    }
};

pub fn dirnameN(path: []const u8, n: usize) error{BadPath}!?[]const u8 {
    if (n == 0) return path;

    var n_rem = n;
    var it = try PathIterator.init(path);

    _ = it.last() orelse return null;
    n_rem -= 1;

    while (n_rem > 0) : (n_rem -= 1) {
        _ = it.prev() orelse return null;
    }

    return if (it.prev()) |p| p.path else it.root();
}

// =============================================================================
// tests
// =============================================================================

test "PathIterator linux" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const t = std.testing;

    {
        const path = "a/b/c/";
        var it = try PathIterator.init(path);
        try t.expectEqual(0, it.root_end);
        try t.expect(null == it.root());
        {
            try t.expect(null == it.prev());

            const first_via_next = it.next().?;
            try t.expectEqualStrings("a", first_via_next.name);
            try t.expectEqualStrings("a", first_via_next.path);

            try t.expectEqualStrings("a", it.first().?.name);
            try t.expectEqualStrings("a", it.first().?.path);

            try t.expect(null == it.prev());

            const second = it.next().?;
            try t.expectEqualStrings("b", second.name);
            try t.expectEqualStrings("a/b", second.path);

            const third = it.next().?;
            try t.expectEqualStrings("c", third.name);
            try t.expectEqualStrings("a/b/c", third.path);

            try t.expect(null == it.next());
        }
        {
            const last = it.last().?;
            try t.expectEqualStrings("c", last.name);
            try t.expectEqualStrings("a/b/c", last.path);

            try t.expect(null == it.next());

            const second_to_last = it.prev().?;
            try t.expectEqualStrings("b", second_to_last.name);
            try t.expectEqualStrings("a/b", second_to_last.path);

            const third_to_last = it.prev().?;
            try t.expectEqualStrings("a", third_to_last.name);
            try t.expectEqualStrings("a", third_to_last.path);

            try t.expect(null == it.prev());
        }
    }
    {
        const path = "/a/b/c/";
        var it = try PathIterator.init(path);
        try t.expectEqual(1, it.root_end);
        try t.expectEqualStrings("/", it.root().?);
        {
            try t.expect(null == it.prev());

            const first_via_next = it.next().?;
            try t.expectEqualStrings("a", first_via_next.name);
            try t.expectEqualStrings("/a", first_via_next.path);

            try t.expectEqualStrings("a", it.first().?.name);
            try t.expectEqualStrings("/a", it.first().?.path);

            try t.expect(null == it.prev());

            const second = it.next().?;
            try t.expectEqualStrings("b", second.name);
            try t.expectEqualStrings("/a/b", second.path);

            const third = it.next().?;
            try t.expectEqualStrings("c", third.name);
            try t.expectEqualStrings("/a/b/c", third.path);

            try t.expect(null == it.next());
        }
        {
            const last = it.last().?;
            try t.expectEqualStrings("c", last.name);
            try t.expectEqualStrings("/a/b/c", last.path);

            try t.expect(null == it.next());

            const second_to_last = it.prev().?;
            try t.expectEqualStrings("b", second_to_last.name);
            try t.expectEqualStrings("/a/b", second_to_last.path);

            const third_to_last = it.prev().?;
            try t.expectEqualStrings("a", third_to_last.name);
            try t.expectEqualStrings("/a", third_to_last.path);

            try t.expect(null == it.prev());
        }
    }
    {
        const path = "////a///b///c////";
        var it = try PathIterator.init(path);
        try t.expectEqual(4, it.root_end);
        try t.expectEqualStrings("/", it.root().?);
        {
            try t.expect(null == it.prev());

            const first_via_next = it.next().?;
            try t.expectEqualStrings("a", first_via_next.name);
            try t.expectEqualStrings("////a", first_via_next.path);

            try t.expectEqualStrings("a", it.first().?.name);
            try t.expectEqualStrings("////a", it.first().?.path);

            try t.expect(null == it.prev());

            const second = it.next().?;
            try t.expectEqualStrings("b", second.name);
            try t.expectEqualStrings("////a///b", second.path);

            const third = it.next().?;
            try t.expectEqualStrings("c", third.name);
            try t.expectEqualStrings("////a///b///c", third.path);

            try t.expect(null == it.next());
        }
        {
            const last = it.last().?;
            try t.expectEqualStrings("c", last.name);
            try t.expectEqualStrings("////a///b///c", last.path);

            try t.expect(null == it.next());

            const second_to_last = it.prev().?;
            try t.expectEqualStrings("b", second_to_last.name);
            try t.expectEqualStrings("////a///b", second_to_last.path);

            const third_to_last = it.prev().?;
            try t.expectEqualStrings("a", third_to_last.name);
            try t.expectEqualStrings("////a", third_to_last.path);

            try t.expect(null == it.prev());
        }
    }
    {
        const path = "/";
        var it = try PathIterator.init(path);
        try t.expectEqual(1, it.root_end);
        try t.expectEqualStrings("/", it.root().?);

        try t.expect(null == it.first());
        try t.expect(null == it.prev());
        try t.expect(null == it.first());
        try t.expect(null == it.next());

        try t.expect(null == it.last());
        try t.expect(null == it.prev());
        try t.expect(null == it.last());
        try t.expect(null == it.next());
    }
    {
        const path = "";
        try t.expectError(error.BadPath, PathIterator.init(path));
    }
}

test "PathIterator windows" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const t = std.testing;

    {
        const path = "a/b\\c/";
        var it = try PathIterator.init(path);
        try t.expectEqual(0, it.root_end);
        try t.expect(null == it.root());
        try t.expectEqualStrings("a", it.next().?.name);
        try t.expectEqualStrings("b", it.next().?.name); // second via next
        try t.expectEqualStrings("c", it.next().?.name);
        try t.expect(null == it.next());

        var it2 = try PathIterator.init(path);
        try t.expectEqualStrings("c", it2.last().?.name);
        try t.expectEqualStrings("b", it2.prev().?.name);
        try t.expectEqualStrings("a", it2.prev().?.name);
        try t.expect(null == it2.prev());
    }
    {
        const path = "C:\\a\\b\\c\\";
        var it = try PathIterator.init(path);
        try t.expectEqualStrings("C:\\", it.root().?);
        try t.expectEqualStrings("a", it.first().?.name);
        try t.expectEqualStrings("C:\\a", it.first().?.path);
        try t.expectEqualStrings("b", it.next().?.name);
        try t.expectEqualStrings("c", it.next().?.name);
        try t.expect(null == it.next());

        var it2 = try PathIterator.init(path);
        try t.expectEqualStrings("c", it2.last().?.name);
        try t.expectEqualStrings("C:\\a\\b\\c", it2.last().?.path);
    }
    {
        const path = "C:a\\b";
        var it = try PathIterator.init(path);
        try t.expectEqualStrings("C:", it.root().?);
        try t.expectEqualStrings("a", it.next().?.name);
        try t.expectEqualStrings("b", it.next().?.name);
    }
    {
        const path = "\\\\server\\share\\a\\b";
        var it = try PathIterator.init(path);
        try t.expectEqualStrings("\\\\server\\share\\", it.root().?);
        try t.expectEqualStrings("a", it.first().?.name);
        try t.expectEqualStrings("\\\\server\\share\\a", it.first().?.path);
        try t.expectEqualStrings("b", it.next().?.name);
    }
    {
        const path = "C:\\";
        var it = try PathIterator.init(path);
        try t.expectEqualStrings("C:\\", it.root().?);
        try t.expect(null == it.first());
        try t.expect(null == it.last());
    }
    {
        const path = "\\\\server\\share\\";
        var it = try PathIterator.init(path);
        try t.expectEqualStrings("\\\\server\\share\\", it.root().?);
        try t.expect(null == it.first());
    }
    {
        const path = "\\\\?\\C:\\";
        var it = try PathIterator.init(path);
        try t.expectEqualStrings("\\\\?\\", it.root().?);
        try t.expectEqualStrings("C:", it.first().?.name);
    }
    {
        const path = "\\\\?\\C:\\a";
        var it = try PathIterator.init(path);
        try t.expectEqualStrings("\\\\?\\", it.root().?);
        try t.expectEqualStrings("C:", it.first().?.name);
        try t.expectEqualStrings("a", it.next().?.name);
    }
    {
        const path = "";
        try t.expectError(error.BadPath, PathIterator.init(path));
    }
}

test "dirnameN linux" { // TODO: Windows version
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    try testDirnameN("/a/b/c", 1, "/a/b");
    try testDirnameN("/a/b/c///", 1, "/a/b");
    try testDirnameN("a/b", 1, "a");
    try testDirnameN("a/b/c", 1, "a/b");
    try testDirnameN("a/b/c///", 1, "a/b");
    try testDirnameN("/a", 1, "/");
    try testDirnameN("/", 1, null);
    try testDirnameN("//", 1, null);
    try testDirnameN("///", 1, null);
    try testDirnameN("////", 1, null);
    try testDirnameN("", 1, error.BadPath);
    try testDirnameN("a", 1, null);
    try testDirnameN("a/", 1, null);
    try testDirnameN("a//", 1, null);

    try testDirnameN("/a/b/c", 2, "/a");
    try testDirnameN("/a/b/c///", 2, "/a");
    try testDirnameN("a/b/c", 2, "a");
    try testDirnameN("a/b", 2, null);
    try testDirnameN("a/b/c///", 2, "a");
    try testDirnameN("/a", 2, null);
    try testDirnameN("/", 2, null);
    try testDirnameN("//", 2, null);
    try testDirnameN("///", 2, null);
    try testDirnameN("////", 2, null);
    try testDirnameN("", 2, error.BadPath);
    try testDirnameN("a", 2, null);
    try testDirnameN("a/", 2, null);
    try testDirnameN("a//", 2, null);

    try testDirnameN("a/b/c", 3, null);
    try testDirnameN("a/b/c///", 3, null);
    try testDirnameN("a/b", 3, null);

    try testDirnameN("a//b", 1, "a");
    try testDirnameN("a///b", 1, "a");
    try testDirnameN("a//b//c", 1, "a//b");
    try testDirnameN("a//b//c", 2, "a");
    try testDirnameN("a//b//c", 3, null);

    try testDirnameN("/a//b", 1, "/a");
    try testDirnameN("/a///b", 1, "/a");
    try testDirnameN("/a//b//c", 1, "/a//b");
    try testDirnameN("/a//b//c", 2, "/a");
    try testDirnameN("/a//b//c", 3, "/");
    try testDirnameN("/a//b//c", 4, null);

    try testDirnameN("///a/b", 1, "///a");
    try testDirnameN("///a/b", 2, "/");
    try testDirnameN("///a/b", 3, null);

    try testDirnameN("a//b///c////d", 1, "a//b///c");
    try testDirnameN("a//b///c////d", 2, "a//b");
    try testDirnameN("a//b///c////d", 3, "a");
    try testDirnameN("a//b///c////d", 4, null);
}

fn testDirnameN(input: []const u8, n: usize, expected: anytype) !void {
    const t = std.testing;

    const output_opt_or_err = dirnameN(input, n);

    if (@typeInfo(@TypeOf(expected)) == .error_set) {
        try t.expectError(expected, output_opt_or_err);
    } else {
        var std_result_opt: ?[]const u8 = input;
        for (0..n) |_| {
            std_result_opt = if (std_result_opt) |std_result| std.fs.path.dirnamePosix(std_result) else null;
        }

        const output_opt = try output_opt_or_err;

        try t.expectEqualDeep(expected, std_result_opt);
        try t.expectEqualDeep(expected, output_opt);
        try t.expectEqualDeep(std_result_opt, output_opt);
    }
}

comptime {
    if (@import("options").test_fs) {
        std.testing.refAllDecls(@import("tests/fs.zig"));
    }
}
