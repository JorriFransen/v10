const std = @import("std");

const assert = @import("../../assert.zig").assert;
const fs = @import("../../fs.zig");
const meta = @import("../../meta.zig");
const win32 = @import("win32.zig");

pub const Handle = win32.HANDLE;

pub const path_sep = '\\';
pub const path_sep_str = "\\";

/// Including null
pub const max_path_bytes = win32.PATH_MAX_WIDE * 3 + 1;
/// Not including null
pub const max_name_bytes = win32.NAME_MAX * 3;

const nt_path_prefix: [4]u16 = .{ '\\', '?', '?', '\\' };

pub const Permissions = enum(u32) {
    default_file,
    default_dir,
    _,

    pub fn readOnly(this: Permissions) Permissions {
        _ = this;
        unreachable;
    }
};

pub inline fn isSep(char: anytype) bool {
    meta.expectUnsigned(char);
    return char == '\\' or char == '/';
}

pub inline fn cwd() fs.Dir {
    return .{ .handle = std.os.windows.peb().ProcessParameters.CurrentDirectory.Handle };
}

pub fn existsAt(dir: fs.Dir, path: [:0]const u8) fs.ExistsAtError!bool {
    var nt_path_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;

    const nt_path = try toNtPath(dir, path, &nt_path_buf);
    const object_attributes = nt_path.ntObjectAttributes();

    var out_info: win32.NT_FILE_BASIC_INFORMATION = undefined;
    switch (win32.NtQueryAttributesFile(&object_attributes, &out_info)) {
        .SUCCESS => return true,
        .OBJECT_NAME_NOT_FOUND, .OBJECT_PATH_NOT_FOUND => return false,
        .OBJECT_NAME_INVALID => return error.BadPath,
        .ACCESS_DENIED => return error.AccessDenied,
        .IO_REPARSE_TAG_NOT_HANDLED => return error.TooManySymLinks,
        else => |e| {
            std.log.err("Unexpected NtQueryAttributesFile error: '{s}' ({})", .{ std.enums.tagName(win32.NTSTATUS, e) orelse "", @intFromEnum(e) });
            return error.Unexpected;
        },
    }
}

pub fn openDirAt(dir: fs.Dir, path: [:0]const u8, options: fs.OpenDirAtOptions) fs.OpenDirAtError!fs.Dir {
    _ = dir;
    _ = path;
    _ = options;
    unreachable;
}

pub fn createDirAt(dir: fs.Dir, dir_name: [:0]const u8, options: fs.CreateDirAtOptions) fs.CreateDirAtError!void {
    _ = dir;
    _ = dir_name;
    _ = options;
    unreachable;
}

pub const DirIterator = struct {
    pub const Options = fs.DirIteratorOptions;

    pub const Entry = fs.DirIteratorEntry;

    pub const Error = fs.DirIteratorError;
    pub const InitError = fs.DirIteratorInitError;
    pub const NextError = fs.DirIteratorNextError;

    pub fn init(dir: fs.Dir, options: Options) InitError!DirIterator {
        _ = dir;
        _ = options;
        unreachable;
    }

    pub fn next(this: *DirIterator) NextError!?Entry {
        _ = this;
        unreachable;
    }
};

pub const ParsedPath = struct {
    type: Type,
    root_end: usize,

    pub const Type = enum {
        relative,
        rooted,
        drive_absolute,
        drive_relative,
        unc,
        local_device,
        verbatim,
    };
};

pub fn parsePath(path: []const u8) error{BadPath}!ParsedPath {
    if (path.len == 0) return error.BadPath;

    if (isSep(path[0])) {
        if (path.len < 2 or !isSep(path[1]))
            if (path.len > 2 and path[2] == '?')
                return error.BadPath
            else
                return .{ .type = .rooted, .root_end = 1 } // \x
        else if (path.len > 2 and (path[2] == '.' or path[2] == '?')) // \\. or \\?
            if (path.len == 3) return error.BadPath // exactly \\. or \\?
            else if (isSep(path[3]))
                if (std.mem.findNone(u8, path[4..], "/\\") == null) {
                    return error.BadPath;
                } else {
                    if (path[0] == path_sep and path[1] == path_sep and path[2] == '?' and path[3] == path_sep) {
                        return .{ .type = .verbatim, .root_end = 4 }; // \\?\
                    }
                    return .{ .type = .local_device, .root_end = 4 }; // \\.\x
                };

        // \\x
        const server_end = std.mem.findAnyPos(u8, path, 2, "/\\") orelse return error.BadPath;
        if (server_end == 2) return error.BadPath;
        var it = std.mem.tokenizeAny(u8, path[server_end + 1 ..], "/\\");

        // There might be multiple separators between server and share
        const share = it.next() orelse return error.BadPath;

        const server = path[2..server_end];
        var len = 2 + (share.ptr - server.ptr) + share.len;
        if (path.len > len and isSep(path[len])) len += 1;

        return .{ .type = .unc, .root_end = len };
    }

    const drive_len = std.unicode.utf8ByteSequenceLength(path[0]) catch return error.BadPath;
    // 4-byte sequences start at a codepoint that needs a surrogate pair, which
    // WTF-16 cannot express, so RtlDetermineDosPathNameType_U sees no colon at
    // index 1 and reports relative. Match that.
    if (drive_len > 3 or path.len <= drive_len or path[drive_len] != ':')
        return .{ .type = .relative, .root_end = 0 } // x
    else if (path.len > drive_len + 1 and isSep(path[drive_len + 1]))
        return .{ .type = .drive_absolute, .root_end = drive_len + 2 }; // x:\

    return .{ .type = .drive_relative, .root_end = drive_len + 1 };
}

const NtPath = struct {
    unicode_string: win32.NT_UNICODE_STRING,
    root_handle: ?win32.HANDLE,

    inline fn ntObjectAttributes(this: *const NtPath) win32.NT_OBJECT_ATTRIBUTES {
        return .{
            .root_directory = this.root_handle,
            .object_name = &this.unicode_string,
            .attributes = .{ .CASE_INSENSITIVE = true },
            .security_descriptor = null,
            .security_quality_of_service = null,
        };
    }
};

fn toNtPath(dir: fs.Dir, path: [:0]const u8, buf: [:0]u16) !NtPath {
    if (path.len > buf.len) return error.NameTooLong;

    const parsed_path = try parsePath(path);
    const name_len = try wtf8ToWtf16LeCheckedLen(buf, path);

    var name: [:0]u16 = if (parsed_path.type != .verbatim) blk: {
        var new_len = name_len;
        while (new_len > 1 and isSep(buf[new_len - 1])) {
            if (buf[new_len - 2] == ':') break;
            new_len -= 1;
        }

        buf[new_len] = 0;
        break :blk buf[0..new_len :0];
    } else blk: {
        buf[name_len] = 0;
        break :blk buf[0..name_len :0];
    };

    // var name: [:0]u16 = if (parsed_path.type != .verbatim) blk: {
    //     var name_len: usize = unstripped_name.len;
    //
    //     while (name_len > 1 and isSep(buf[name_len - 1])) {
    //         if (buf[name_len - 2] == ':') break;
    //         name_len -= 1;
    //     }
    //
    //     buf[name_len] = 0;
    //     break :blk buf[0..name_len :0];
    // } else blk: {
    //     buf[unstripped_name.len] = 0;
    //     break :blk buf[0..unstripped_name.len :0];
    // };

    var nt_name: win32.NT_UNICODE_STRING = undefined;
    var dir_handle: ?win32.HANDLE = null;

    switch (parsed_path.type) {
        // In place prefix swap
        .verbatim => {
            name[0..nt_path_prefix.len].* = nt_path_prefix;
        },
        .local_device,
        // Resolve and prefix
        .rooted,
        .drive_relative,
        // Prefix only
        .unc,
        .drive_absolute,
        => {
            switch (win32.RtlDosPathNameToNtPathName_U_WithStatus(name, &nt_name, null, null)) {
                .SUCCESS => {},
                .OBJECT_NAME_INVALID => return error.BadPath,
                .NO_MEMORY => return error.OutOfMemory,
                .ACCESS_DENIED => return error.AccessDenied,
                else => return error.Unexpected,
            }
            const nt_name_slice = nt_name.slice();
            if (buf.len < nt_name_slice.len + 1) return error.NameTooLong;
            @memcpy(buf[0 .. nt_name_slice.len + 1], nt_name_slice.ptr[0 .. nt_name_slice.len + 1]);
            name = buf[0..nt_name_slice.len :0];
        },

        .relative => {
            if (std.os.windows.normalizePath(u16, name)) |normalized_len| {
                name[normalized_len] = 0;
                name = name[0..normalized_len :0];
                dir_handle = dir.handle;
            } else |e| switch (e) {
                error.TooManyParentDirs => {
                    name = try relativeEscapingDirHandleNtPath(dir, path, buf);
                },
            }
        },
    }
    defer if (parsed_path.type != .relative and parsed_path.type != .verbatim) win32.RtlFreeUnicodeString(&nt_name);

    return .{
        .unicode_string = .{
            .buffer = name.ptr,
            .length = @intCast(name.len * @sizeOf(u16)),
            // Do not include null to avoid overflow when len == PATH_MAX_WIDE
            .maximum_length = @intCast((name.len) * @sizeOf(u16)),
        },
        .root_handle = dir_handle,
    };
}

fn relativeEscapingDirHandleNtPath(dir: fs.Dir, path: [:0]const u8, dest: [:0]u16) ![:0]u16 {
    var buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;

    var dir_path_len = win32.GetFinalPathNameByHandleW(dir.handle, &buf, buf.len + 1, win32.FILE_NAME_NORMALIZED | win32.VOLUME_NAME_DOS);
    if (dir_path_len > buf.len) return error.NameTooLong;
    if (dir_path_len == 0) {
        const err = win32.GetLastError();
        switch (err) {
            else => return error.Unexpected,
            .INVALID_PARAMETER => unreachable,
            .PATH_NOT_FOUND => return error.BadPath,
            .NOT_ENOUGH_MEMORY => return error.OutOfMemory,
            .ACCESS_DENIED => return error.AccessDenied,

            .UNRECOGNIZED_VOLUME => {
                dir_path_len = win32.GetFinalPathNameByHandleW(dir.handle, &buf, buf.len + 1, win32.FILE_NAME_NORMALIZED | win32.VOLUME_NAME_GUID);
                if (dir_path_len > buf.len) return error.NameTooLong;
                if (dir_path_len == 0) {
                    const retry_err = win32.GetLastError();
                    return switch (retry_err) {
                        else => blk: {
                            std.log.err("Unexpected error after UNRECOGNIZED_VOLUME retry with VOLUME_NAME_GUID: '{s}' ({})", .{
                                std.enums.tagName(win32.ERROR, retry_err) orelse "",
                                @intFromEnum(retry_err),
                            });
                            break :blk error.Unexpected;
                        },
                        .INVALID_PARAMETER => unreachable,
                        .PATH_NOT_FOUND => error.BadPath,
                        .NOT_ENOUGH_MEMORY => error.OutOfMemory,
                        .ACCESS_DENIED => error.AccessDenied,
                    };
                }
            },
        }
    }

    if (dir_path_len + path.len + 1 > buf.len) return error.NameTooLong;

    buf[dir_path_len] = path_sep;

    const path_len = try wtf8ToWtf16LeCheckedLen(buf[dir_path_len + 1 ..], path);
    const unresolved_len = dir_path_len + path_len + 1;
    buf[unresolved_len] = 0;
    const unresolved_name = buf[0..unresolved_len :0];

    const dest_len_bytes = (dest.len + 1) * @sizeOf(u16);
    const result_len_bytes = win32.RtlGetFullPathName_U(unresolved_name, @intCast(dest_len_bytes), dest.ptr, null);
    if (result_len_bytes == 0) return error.BadPath;
    if (result_len_bytes >= dest_len_bytes) return error.NameTooLong;

    dest[0..nt_path_prefix.len].* = nt_path_prefix;

    const result_len = result_len_bytes / @sizeOf(u16);

    return dest[0..result_len :0];
}

inline fn wtf8ToWtf16LeCheckedLen(dest: []u16, src: []const u8) error{ NameTooLong, BadPath }!usize {
    const wide_len = std.unicode.calcWtf16LeLen(src) catch return error.BadPath;
    if (wide_len > dest.len) return error.NameTooLong;

    const actual_wide_len = std.unicode.wtf8ToWtf16Le(dest, src) catch unreachable;
    assert(actual_wide_len == wide_len);

    return wide_len;
}

test toNtPath {
    const t = std.testing;

    const test_nt_path_prefix: [4]u16 = .{ '\\', '?', '?', '\\' };

    const F = struct {
        pub fn testToNtPathAgainstRtl(path: [:0]const u8) !void {
            var buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
            const result = try toNtPath(cwd(), path, &buf);

            const parsed = try parsePath(path);
            try t.expect(parsed.type != .relative);

            var result_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
            const result_len = try std.unicode.wtf8ToWtf16Le(&result_buf, path);
            result_buf[result_len] = 0;
            const result_name = result_buf[0..result_len :0];

            var rtl_unicode_result: win32.NT_UNICODE_STRING = undefined;
            const rc = win32.RtlDosPathNameToNtPathName_U_WithStatus(result_name, &rtl_unicode_result, null, null);
            try t.expectEqual(win32.NTSTATUS.SUCCESS, rc);
            defer win32.RtlFreeUnicodeString(&rtl_unicode_result);

            var expected_result = rtl_unicode_result.slice();
            if (parsed.type != .verbatim) {
                while (expected_result.len > 1 and isSep(expected_result[expected_result.len - 1])) {
                    if (expected_result[expected_result.len - 2] == ':') break;
                    expected_result.len -= 1;
                }
            }

            if (!std.mem.eql(u16, expected_result, result.unicode_string.slice())) {
                std.debug.print("expected: '{f}', got: '{f}'\n", .{ std.unicode.fmtUtf16Le(expected_result), std.unicode.fmtUtf16Le(result.unicode_string.slice()) });
                return error.TestExpectedEqual;
            }

            try t.expect(result.root_handle == null);
        }

        pub fn testToNtPathRelativeNoEscape(path: [:0]const u8, expected_narrow_result: []const u8) !void {
            var result_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
            const result = try toNtPath(cwd(), path, &result_buf);

            const parsed = try parsePath(path);
            try t.expectEqual(.relative, parsed.type);

            var expected_result_wide_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
            const expected_wide_len = try std.unicode.wtf8ToWtf16Le(&expected_result_wide_buf, expected_narrow_result);
            const expected = expected_result_wide_buf[0..expected_wide_len];

            if (!std.mem.eql(u16, expected, result.unicode_string.slice())) {
                std.debug.print("expected: '{f}', got: '{f}'\n", .{ std.unicode.fmtUtf16Le(expected), std.unicode.fmtUtf16Le(result.unicode_string.slice()) });
                return error.TestExpectedEqual;
            }

            try t.expectEqual(cwd().handle, result.root_handle);
        }

        pub fn testToNtPathRelativeEscaping(path: [:0]const u8, drop_count: usize, tail: []const u8) !void {
            var result_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
            const result = try toNtPath(cwd(), path, &result_buf);

            const parsed = try parsePath(path);
            try t.expectEqual(.relative, parsed.type);

            var expected_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
            const dir_len = win32.GetFinalPathNameByHandleW(cwd().handle, &expected_buf, expected_buf.len + 1, win32.FILE_NAME_NORMALIZED | win32.VOLUME_NAME_DOS);
            if (dir_len == 0 or dir_len > expected_buf.len) return error.TestUnexpected;

            var expected_len: usize = dir_len;

            const verbatim_prefix: [4]u16 = .{ '\\', '\\', '?', '\\' };
            try t.expectEqualSlices(u16, &verbatim_prefix, expected_buf[0..4]);

            if (expected_buf[5] != ':') return error.TestUnexpected;
            const root_len: usize = 6;

            for (0..drop_count) |_| {
                while (expected_len > root_len and isSep(expected_buf[expected_len - 1])) expected_len -= 1;
                const sep = std.mem.lastIndexOfScalar(u16, expected_buf[root_len..expected_len], path_sep) orelse
                    return error.TestUnexpected;
                expected_len = sep + root_len;
            }

            const expected = expected_buf[0..expected_len];

            expected[0..nt_path_prefix.len].* = test_nt_path_prefix;

            if (tail.len != 0) {
                if (expected_len + tail.len + 1 > expected_buf.len) return error.TestUnexpected;
                expected_len += try std.unicode.wtf8ToWtf16Le(expected_buf[expected_len..], tail);
            }

            if (!std.mem.eql(u16, expected_buf[0..expected_len], result.unicode_string.slice())) {
                std.debug.print("expected: '{f}', got: '{f}'\n", .{
                    std.unicode.fmtUtf16Le(expected_buf[0..expected_len]),
                    std.unicode.fmtUtf16Le(result.unicode_string.slice()),
                });
                return error.TestExpectedEqual;
            }

            try t.expect(result.root_handle == null);
        }

        pub fn testToNtPathLength(path: [:0]const u8, expected_error: ?anyerror) !void {
            var buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
            if (expected_error) |err| {
                try t.expectError(err, toNtPath(cwd(), path, &buf));
            } else {
                const result = try toNtPath(cwd(), path, &buf);
                try t.expectEqual(@as(usize, win32.PATH_MAX_WIDE), result.unicode_string.slice().len);
                try t.expect(result.root_handle == null);
            }
        }
    };

    const testToNtPathAgainstRtl = F.testToNtPathAgainstRtl;
    const testToNtPathRelativeNoEscape = F.testToNtPathRelativeNoEscape;
    const testToNtPathRelativeEscaping = F.testToNtPathRelativeEscaping;
    const testToNtPathLength = F.testToNtPathLength;

    // verbatim
    try testToNtPathAgainstRtl("\\\\?\\C:\\foo");
    try testToNtPathAgainstRtl("\\\\?\\C:\\foo\\");
    try testToNtPathAgainstRtl("\\\\?\\C:\\foo\\..\\bar");
    try testToNtPathAgainstRtl("\\\\?\\C:\\foo.");
    try testToNtPathAgainstRtl("\\\\?\\C:\\foo ");
    try testToNtPathAgainstRtl("\\\\?\\C:\\");
    try testToNtPathAgainstRtl("\\\\?\\UNC\\server\\share\\foo");
    try testToNtPathAgainstRtl("\\\\?\\UNC\\");
    try testToNtPathAgainstRtl("\\\\?\\C:/foo");
    try testToNtPathAgainstRtl("\\\\?\\Volume{GUID}\\");
    try testToNtPathAgainstRtl("\\\\?\\GLOBALROOT\\Device\\HarddiskVolume1\\");
    try testToNtPathAgainstRtl("\\\\?\\C:");
    try testToNtPathAgainstRtl("\\\\?\\C:\\abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ");

    // drive_absolute
    try testToNtPathAgainstRtl("C:\\foo");
    try testToNtPathAgainstRtl("C:/foo");
    try testToNtPathAgainstRtl("C:\\foo\\");
    try testToNtPathAgainstRtl("C:\\");
    try testToNtPathAgainstRtl("C:\\\\foo");
    try testToNtPathAgainstRtl("C:\\foo\\..\\bar");
    try testToNtPathAgainstRtl("C:\\foo\\.");
    try testToNtPathAgainstRtl("C:\\foo ");
    try testToNtPathAgainstRtl("C:\\foo. ");
    try testToNtPathAgainstRtl("C:\\foo .");
    try testToNtPathAgainstRtl("C:\\.");
    try testToNtPathAgainstRtl("C:\\foo\\.");
    try testToNtPathAgainstRtl("C:\\..\\foo");
    try testToNtPathAgainstRtl("C:\\..\\..\\foo");
    try testToNtPathAgainstRtl("C:\\foo:bar");
    try testToNtPathAgainstRtl("C:\\foo:");
    try testToNtPathAgainstRtl("C:\\foo::$DATA");
    try testToNtPathAgainstRtl("C:\\CON");
    try testToNtPathAgainstRtl("C:\\CON ");
    try testToNtPathAgainstRtl("C:\\foo*.txt");
    try testToNtPathAgainstRtl("c:\\foo");
    try testToNtPathAgainstRtl("C:\\Foo\\BAR");
    try testToNtPathAgainstRtl("é:\\foo");
    try testToNtPathAgainstRtl("1:\\foo");
    try testToNtPathAgainstRtl("?:\\foo");
    try testToNtPathAgainstRtl("::\\foo");
    try testToNtPathAgainstRtl("\\Device\\HarddiskVolume1\\foo");
    try testToNtPathAgainstRtl("C:\\dir\\😀\\file");

    // local_device
    try testToNtPathAgainstRtl("\\\\.\\C:\\foo");
    try testToNtPathAgainstRtl("\\\\.\\C:");
    try testToNtPathAgainstRtl("\\\\.\\Volume{GUID}\\");
    try testToNtPathAgainstRtl("\\\\.\\UNC\\server\\share\\foo");
    try testToNtPathAgainstRtl("\\\\.\\PIPE\\name");
    try testToNtPathAgainstRtl("\\\\.\\GLOBALROOT\\Device\\HarddiskVolume1\\");
    try testToNtPathAgainstRtl("\\\\.\\COM1");
    try testToNtPathAgainstRtl("\\\\.\\C:\\foo\\..\\bar");
    try testToNtPathAgainstRtl("\\\\.\\unix\\path");
    try testToNtPathAgainstRtl("//?/C:\\foo");
    try testToNtPathAgainstRtl("//?/foo");

    // unc
    try testToNtPathAgainstRtl("\\\\server\\share\\foo");
    try testToNtPathAgainstRtl("\\\\server\\share");
    try testToNtPathAgainstRtl("\\\\server\\share\\");
    try testToNtPathAgainstRtl("\\\\a\\b");
    try testToNtPathAgainstRtl("//server/share/foo");
    try testToNtPathAgainstRtl("\\\\server\\share\\foo\\..\\bar");
    try testToNtPathAgainstRtl("\\\\127.0.0.1\\c$\\foo");
    try testToNtPathAgainstRtl("\\\\127.0.0.1\\c$\\");
    try testToNtPathAgainstRtl("\\\\??\\C:\\foo");
    try testToNtPathAgainstRtl("\\\\server\\\\share");
    try testToNtPathAgainstRtl("\\\\fe80::1\\share");
    try testToNtPathAgainstRtl("\\\\srv\\é\\share");

    // rooted
    try testToNtPathAgainstRtl("\\foo");
    try testToNtPathAgainstRtl("/foo");
    try testToNtPathAgainstRtl("\\foo\\");
    try testToNtPathAgainstRtl("\\");
    try testToNtPathAgainstRtl("\\C:\\");
    try testToNtPathAgainstRtl("\\foo\\..\\bar");
    try testToNtPathAgainstRtl("\\..");

    // drive_relative
    try testToNtPathAgainstRtl("C:foo");
    try testToNtPathAgainstRtl("C:");
    try testToNtPathAgainstRtl("C:a\\b");
    try testToNtPathAgainstRtl("C::\\foo");
    try testToNtPathAgainstRtl("c:foo");
    try testToNtPathAgainstRtl("é:foo");

    // relative (not escaping root handle)
    try testToNtPathRelativeNoEscape("foo", "foo");
    try testToNtPathRelativeNoEscape("a/../b", "b");
    try testToNtPathRelativeNoEscape("a\\b\\./c/../d", "a\\b\\d");
    try testToNtPathRelativeNoEscape(".", "");
    try testToNtPathRelativeNoEscape("a//b", "a\\b");
    try testToNtPathRelativeNoEscape("a\\b\\\\c/", "a\\b\\c");
    try testToNtPathRelativeNoEscape("a\\b\\..\\c\\..\\d", "a\\d");
    try testToNtPathRelativeNoEscape("a\\b\\..\\..", "");
    try testToNtPathRelativeNoEscape(".\\a", "a");
    try testToNtPathRelativeNoEscape("a\\..", "");
    try testToNtPathRelativeNoEscape("a.", "a.");
    try testToNtPathRelativeNoEscape("a ", "a ");
    try testToNtPathRelativeNoEscape("...", "...");
    try testToNtPathRelativeNoEscape("..a", "..a");

    // relative (escaping root handle)
    try testToNtPathRelativeEscaping("..", 1, "");
    try testToNtPathRelativeEscaping("..\\..", 2, "");
    try testToNtPathRelativeEscaping("../foo", 1, "\\foo");
    try testToNtPathRelativeEscaping("a/../../b", 1, "\\b");
    try testToNtPathRelativeEscaping("..\\foo", 1, "\\foo");
    try testToNtPathRelativeEscaping("..\\..\\a\\b", 2, "\\a\\b");
    try testToNtPathRelativeEscaping("a\\..\\..\\..\\b", 2, "\\b");

    // capacity
    var verbatim_exact_buf: [win32.PATH_MAX_WIDE + 1]u8 = undefined;
    @memcpy(verbatim_exact_buf[0..7], "\\\\?\\C:\\");
    @memset(verbatim_exact_buf[7..win32.PATH_MAX_WIDE], 'a');
    verbatim_exact_buf[win32.PATH_MAX_WIDE] = 0;
    try testToNtPathLength(verbatim_exact_buf[0..win32.PATH_MAX_WIDE :0], null);

    var verbatim_long_buf: [win32.PATH_MAX_WIDE + 2]u8 = undefined;
    @memcpy(verbatim_long_buf[0..7], "\\\\?\\C:\\");
    @memset(verbatim_long_buf[7 .. win32.PATH_MAX_WIDE + 1], 'a');
    verbatim_long_buf[win32.PATH_MAX_WIDE + 1] = 0;
    try testToNtPathLength(verbatim_long_buf[0 .. win32.PATH_MAX_WIDE + 1 :0], error.NameTooLong);

    // C:\ is 3 units, filler is PATH_MAX_WIDE - 3. Same input length as the verbatim
    // success case, but a non-verbatim DOS path cannot exceed MAX_PATH, so RTL refuses
    // it with OBJECT_NAME_INVALID before any size check runs.
    var absolute_exact_buf: [win32.PATH_MAX_WIDE + 1]u8 = undefined;
    @memcpy(absolute_exact_buf[0..3], "C:\\");
    @memset(absolute_exact_buf[3..win32.PATH_MAX_WIDE], 'a');
    absolute_exact_buf[win32.PATH_MAX_WIDE] = 0;
    try testToNtPathLength(absolute_exact_buf[0..win32.PATH_MAX_WIDE :0], error.BadPath);

    var rooted_long_buf: [win32.PATH_MAX_WIDE + 1]u8 = undefined;
    rooted_long_buf[0] = '\\';
    @memset(rooted_long_buf[1..win32.PATH_MAX_WIDE], 'a');
    rooted_long_buf[win32.PATH_MAX_WIDE] = 0;
    try testToNtPathLength(rooted_long_buf[0..win32.PATH_MAX_WIDE :0], error.BadPath);
}

test parsePath {
    const t = std.testing;

    const testParse = struct {
        pub fn testParse(path: []const u8, expected_type: ParsedPath.Type, expected_root: []const u8) !void {
            const parsed = try parsePath(path);

            try t.expectEqual(expected_type, parsed.type);
            try t.expectEqualStrings(expected_root, path[0..parsed.root_end]);
        }
    }.testParse;

    // relative — root_end is always 0
    try testParse("foo", .relative, "");
    try testParse("a/b\\c/", .relative, "");
    try testParse("C", .relative, "");
    try testParse(":", .relative, ""); // len 1, short-circuits
    try testParse(":\\foo", .relative, ""); // path[1] != ':'
    try testParse(".", .relative, "");
    try testParse("con.txt", .relative, ""); // reserved names not special-cased
    try testParse("\u{20AC}", .relative, ""); // no colon
    try testParse("\u{1F600}:\\foo", .relative, ""); // 4-byte lead
    try testParse("\xC3", .relative, ""); // truncated 2-byte lead
    try testParse("..", .relative, "");
    try testParse("../foo", .relative, "");
    try testParse("./foo", .relative, "");

    // rooted
    try testParse("\\", .rooted, "\\");
    try testParse("/", .rooted, "/");
    try testParse("\\foo", .rooted, "\\");
    try testParse("/foo", .rooted, "/");
    try testParse("\\foo\\bar", .rooted, "\\");
    try testParse("\\?x", .rooted, "\\"); // '?' illegal in a name, not validated
    try testParse("\\:", .rooted, "\\");
    try testParse("\\C:", .rooted, "\\");
    try testParse("\\C:\\", .rooted, "\\");
    try testParse("/C:/", .rooted, "/");
    try testParse("\\?", .rooted, "\\");
    try testParse("\\?\\", .rooted, "\\");
    try testParse("\\?\\abc", .rooted, "\\");

    // drive_relative
    try testParse("C:", .drive_relative, "C:");
    try testParse("C:foo", .drive_relative, "C:");
    try testParse("c:", .drive_relative, "c:");
    try testParse("c:foo", .drive_relative, "c:");
    try testParse("C:a\\b", .drive_relative, "C:");
    try testParse("C::", .drive_relative, "C:");
    try testParse("C::\\foo", .drive_relative, "C:");
    try testParse("\u{20AC}:", .drive_relative, "\u{20AC}:");
    try testParse("é:", .drive_relative, "é:");
    try testParse("é:foo", .drive_relative, "é:");
    try testParse("::", .drive_relative, "::");
    try testParse("1:", .drive_relative, "1:");
    try testParse("::foo", .drive_relative, "::");

    // drive_absolute
    try testParse("C:\\", .drive_absolute, "C:\\");
    try testParse("C:\\foo", .drive_absolute, "C:\\");
    try testParse("c:\\", .drive_absolute, "c:\\");
    try testParse("c:\\foo", .drive_absolute, "c:\\");
    try testParse("C:/", .drive_absolute, "C:/");
    try testParse("C:/foo", .drive_absolute, "C:/");
    try testParse("C://foo", .drive_absolute, "C:/");
    try testParse("1:\\foo", .drive_absolute, "1:\\");
    try testParse("?:\\foo", .drive_absolute, "?:\\");
    try testParse("\u{20AC}:\\", .drive_absolute, "\u{20AC}:\\");
    try testParse("\u{20AC}:\\foo", .drive_absolute, "\u{20AC}:\\");
    try testParse("\u{00E9}:\\foo", .drive_absolute, "\u{00E9}:\\");
    try testParse("::\\", .drive_absolute, "::\\");

    // unc — root includes exactly one trailing separator when present
    try testParse("\\\\server\\share", .unc, "\\\\server\\share");
    try testParse("\\\\server\\share\\", .unc, "\\\\server\\share\\");
    try testParse("\\\\server\\share\\foo", .unc, "\\\\server\\share\\");
    try testParse("\\\\server\\share\\\\foo", .unc, "\\\\server\\share\\");
    try testParse("\\\\server\\\\share", .unc, "\\\\server\\\\share");
    try testParse("\\\\server\\\\share\\foo", .unc, "\\\\server\\\\share\\");
    try testParse("//server/share", .unc, "//server/share");
    try testParse("//server/share/", .unc, "//server/share/");
    try testParse("//server/share/foo", .unc, "//server/share/");
    try testParse("//server//share", .unc, "//server//share");
    try testParse("\\\\server\\sharefoo", .unc, "\\\\server\\sharefoo");
    try testParse("\\\\server\\share\\..\\foo", .unc, "\\\\server\\share\\");
    try testParse("\\\\srv\\\u{20AC}\\foo", .unc, "\\\\srv\\\u{20AC}\\");
    try testParse("\\\\?x\\y", .unc, "\\\\?x\\y"); // server named "?x"
    try testParse("\\\\127.0.0.1\\c$\\", .unc, "\\\\127.0.0.1\\c$\\");
    try testParse("\\\\127.0.0.1\\c$\\foo", .unc, "\\\\127.0.0.1\\c$\\");
    try testParse("\\\\??\\C:\\", .unc, "\\\\??\\C:\\");

    // local_device
    try testParse("\\\\.\\foo", .local_device, "\\\\.\\");
    try testParse("\\\\./foo", .local_device, "\\\\./");
    try testParse("\\\\.//foo", .local_device, "\\\\./");
    try testParse("\\\\.\\Volume{GUID}\\", .local_device, "\\\\.\\");
    try testParse("\\\\.\\unix\\path", .local_device, "\\\\.\\");
    try testParse("\\\\.\\C:\\", .local_device, "\\\\.\\");
    try testParse("\\\\.\\UNC\\server\\share\\", .local_device, "\\\\.\\");
    try testParse("//./foo", .local_device, "//./");
    try testParse("\\\\.\\.", .local_device, "\\\\.\\");
    try testParse("\\\\?/C:\\foo", .local_device, "\\\\?/");
    try testParse("//?/foo", .local_device, "//?/");

    // verbatim
    try testParse("\\\\?\\C:\\foo", .verbatim, "\\\\?\\");
    try testParse("\\\\?\\\\foo", .verbatim, "\\\\?\\");
    try testParse("\\\\?\\UNC\\server\\share", .verbatim, "\\\\?\\");
    try testParse("\\\\?\\Volume{X}\\", .verbatim, "\\\\?\\");
    try testParse("\\\\?\\GLOBALROOT\\", .verbatim, "\\\\?\\");
    try testParse("\\\\?\\.", .verbatim, "\\\\?\\");

    try t.expectError(error.BadPath, parsePath(""));
    try t.expectError(error.BadPath, parsePath("//"));
    try t.expectError(error.BadPath, parsePath("\\/"));
    try t.expectError(error.BadPath, parsePath("/\\"));
    try t.expectError(error.BadPath, parsePath("///"));
    try t.expectError(error.BadPath, parsePath("\\\\\\"));
    try t.expectError(error.BadPath, parsePath("\\\\.")); // bare prefix
    try t.expectError(error.BadPath, parsePath("\\\\?"));
    try t.expectError(error.BadPath, parsePath("//?"));
    try t.expectError(error.BadPath, parsePath("//?/"));
    try t.expectError(error.BadPath, parsePath("\\\\?\\")); // separators only after prefix
    try t.expectError(error.BadPath, parsePath("//."));
    try t.expectError(error.BadPath, parsePath("//./"));
    try t.expectError(error.BadPath, parsePath("\\\\.\\"));
    try t.expectError(error.BadPath, parsePath("\\\\?////"));
    try t.expectError(error.BadPath, parsePath("\\\\.\\/\\"));
    try t.expectError(error.BadPath, parsePath("\\\\")); // no server
    try t.expectError(error.BadPath, parsePath("\\\\server")); // no share
    try t.expectError(error.BadPath, parsePath("\\\\server\\"));
    try t.expectError(error.BadPath, parsePath("\\\\server\\\\")); // empty server
    try t.expectError(error.BadPath, parsePath("\\\\\\foo")); // empty server
    try t.expectError(error.BadPath, parsePath("////foo")); // empty server
    try t.expectError(error.BadPath, parsePath("\\\\.x")); // '.' without separator is a server name, and has none
    try t.expectError(error.BadPath, parsePath("\\??"));
    try t.expectError(error.BadPath, parsePath("\\\\??"));
    try t.expectError(error.BadPath, parsePath("\\\\??\\"));
    try t.expectError(error.BadPath, parsePath("\\??\\C:\\foo")); // NT path
    try t.expectError(error.BadPath, parsePath("/??/C:/foo")); // NT path
    try t.expectError(error.BadPath, parsePath("\\??x\\y"));
    try t.expectError(error.BadPath, parsePath("\x80foo")); // invalid UTF-8 lead bytes
    try t.expectError(error.BadPath, parsePath("\xBF"));
    try t.expectError(error.BadPath, parsePath("\xF8"));
    try t.expectError(error.BadPath, parsePath("\xFF"));
}
