const std = @import("std");
const builtin = @import("builtin");

const assert = @import("assert.zig").assert;

const os = @import("os/os.zig").current.fs;

pub const Handle = os.Handle;

pub const path_sep = os.path_sep;
pub const path_sep_str = os.path_sep_str;
pub const max_path_bytes = os.max_path_bytes;
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

    pub fn stdDir(this: Dir) @import("std").Io.Dir {
        return .{ .handle = this.handle };
    }
};

pub const Permissions = os.Permissions;

pub const isSep = os.isSep;

pub const cwd = os.cwd;

pub const ExistsAtError = error{
    AccessDenied,
    IO,
    NameTooLong,
    OutOfMemory,
    PermissionDenied,
    TooManySymLinks,
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
    SystemHandleQuotaExceeded,
    TooManySymLinks,

    Unexpected,
};
pub const OpenDirAtOptions = struct {
    iterate: bool = false,
    follow_symlinks: bool = true,
};
pub const openDirAt = os.openDirAt;

pub const CreateDirAtError = error{
    AccessDenied,
    PermissionDenied,
    NoSpace,
    AlreadyExists,
    BadPath,
    TooManySymLinks,
    NameTooLong,
    FileNotFound,
    OutOfMemory,
    NotDir,
    ReadOnlyFileSystem,
    MissingIdMapping,

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

    var it = PathIterator.init(dir_path);
    _ = it.last();

    while (it.prev()) |elem| {
        if (createDirAt(dir, stackPathZ(elem.path), options)) {
            break;
        } else |e| switch (e) {
            else => return e,
            error.FileNotFound => {},
        }
    }

    while (it.next()) |elem| {
        try createDirAt(dir, stackPathZ(elem.path), options);
    }
}

pub const DirIteratorInitError = error{ SeekFailed, InvalidHandle };
pub const DirIteratorNextError = error{ InvalidHandle, MalformedDirEntry, Unexpected };
pub const DirIteratorError = DirIteratorInitError || DirIteratorNextError;
pub const DirIterator = os.DirIterator;

pub const PathIterator = struct {
    path: [:0]const u8,
    current_start: usize,
    current_end: usize,
    root_end: usize,

    pub const Elem = struct {
        /// From begin, inluding this element
        path: []const u8,

        name: []const u8,
    };

    pub fn init(path: [:0]const u8) PathIterator {
        if (path.len == 0) {
            return .{ .path = path, .current_start = 0, .current_end = 0, .root_end = 0 };
        }

        if (!isSep(path[0])) {
            return .{ .path = path, .current_start = 0, .current_end = 0, .root_end = 0 };
        } else {
            var start: usize = 1;
            while (start < path.len and isSep(path[start])) start += 1;
            return .{ .path = path, .current_start = start, .current_end = start, .root_end = start };
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
        if (this.path.len == 0 or (this.path.len == 1 and isSep(this.path[0]))) return null;

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

pub const dirnameN = os.dirnameN;

/// Copy 'path' into a (inlined) stack buffer, return null terminated slice.
pub inline fn stackPathZ(path: []const u8) [:0]const u8 {
    var buf: [max_path_bytes]u8 = undefined;
    assert(path.len + 1 <= buf.len);
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return buf[0..path.len :0];
}

// =============================================================================
// tests
// =============================================================================

test "PathIterator linux" {
    const t = std.testing;

    {
        const path = "a/b/c/";
        var it = PathIterator.init(path);
        try t.expectEqual(0, it.root_end);
        try t.expect(null == it.root());
        {
            try t.expect(null == it.prev());

            const first_via_next = it.next().?;
            try t.expectEqualStrings("a", first_via_next.name);
            try t.expectEqualStrings("a", first_via_next.path);

            const first = it.first().?;
            try t.expectEqualStrings("a", first.name);
            try t.expectEqualStrings("a", first.path);

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
        var it = PathIterator.init(path);
        try t.expectEqual(1, it.root_end);
        try t.expectEqualStrings("/", it.root().?);
        {
            try t.expect(null == it.prev());

            const first_via_next = it.next().?;
            try t.expectEqualStrings("a", first_via_next.name);
            try t.expectEqualStrings("/a", first_via_next.path);

            const first = it.first().?;
            try t.expectEqualStrings("a", first.name);
            try t.expectEqualStrings("/a", first.path);

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
        var it = PathIterator.init(path);
        try t.expectEqual(4, it.root_end);
        try t.expectEqualStrings("/", it.root().?);
        {
            try t.expect(null == it.prev());

            const first_via_next = it.next().?;
            try t.expectEqualStrings("a", first_via_next.name);
            try t.expectEqualStrings("////a", first_via_next.path);

            const first = it.first().?;
            try t.expectEqualStrings("a", first.name);
            try t.expectEqualStrings("////a", first.path);

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
        var it = PathIterator.init(path);
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
        var it = PathIterator.init(path);
        try t.expectEqual(0, it.root_end);
        try t.expect(null == it.root());

        try t.expect(null == it.first());
        try t.expect(null == it.prev());
        try t.expect(null == it.first());
        try t.expect(null == it.next());

        try t.expect(null == it.last());
        try t.expect(null == it.prev());
        try t.expect(null == it.last());
        try t.expect(null == it.next());
    }
}
