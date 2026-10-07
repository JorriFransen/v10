const std = @import("std");

const assert = @import("../../assert.zig").assert;
const bits = @import("../../bits.zig");
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
const local_device_prefix: [4]u16 = .{ '\\', '\\', '.', '\\' };
const unc_dos_prefix: [8]u16 = .{ '\\', '\\', '?', '\\', 'U', 'N', 'C', '\\' };
const unc_nt_prefix: [8]u16 = .{ '\\', '?', '?', '\\', 'U', 'N', 'C', '\\' };

pub const Permissions = enum(@typeInfo(win32.ACCESS_MASK).@"struct".backing_integer.?) {
    default_file = @bitCast(win32.ACCESS_MASK{ .GENERIC_READ = true, .GENERIC_WRITE = true, .SYNCHRONIZE = true }),
    _,

    pub const default_dir: Permissions = .default_file;
};

pub inline fn isSep(char: anytype) bool {
    meta.expectUnsigned(char);
    return char == '\\' or char == '/';
}

pub inline fn cwd() fs.Dir {
    return .{ .handle = std.os.windows.peb().ProcessParameters.CurrentDirectory.Handle };
}

pub inline fn close(handle: Handle) void {
    _ = win32.NT.NtClose(handle);
}

/// Always follows links
pub fn existsAt(dir: fs.Dir, path: [:0]const u8) fs.ExistsAtError!bool {
    const require_dir = path.len > 1 and isSep(path[path.len - 1]) and path[path.len - 2] != ':';

    var nt_path_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;

    const nt_path = try toNtPath(dir, path, &nt_path_buf);
    const object_attributes = nt_path.ntObjectAttributes();

    var handle: Handle = undefined;
    var io_status_block: win32.NT.IO_STATUS_BLOCK = undefined;

    switch (win32.NT.NtOpenFile(
        &handle,
        .{ .SYNCHRONIZE = true, .specific = .{ .FILE = .{ .READ_ATTRIBUTES = true } } },
        &object_attributes,
        &io_status_block,
        .{ .READ = true },
        .{
            .SYNCHRONOUS_IO_NONALERT = true,
            .OPEN_FOR_BACKUP_INTENT = true,
            .DIRECTORY_FILE = require_dir,
        },
    )) {
        .SUCCESS => {
            _ = win32.NT.NtClose(handle);
            return true;
        },

        .DELETE_PENDING => return true,

        .NOT_A_DIRECTORY,
        .OBJECT_NAME_NOT_FOUND,
        .OBJECT_PATH_NOT_FOUND,
        .BAD_NETWORK_NAME,
        .BAD_NETWORK_PATH,
        => return false,

        .OBJECT_NAME_INVALID,
        .OBJECT_PATH_INVALID,
        .OBJECT_PATH_SYNTAX_BAD,
        => return if (anyElementTooLong(nt_path)) error.NameTooLong else false,

        .INSUFFICIENT_RESOURCES, .NO_MEMORY => return error.OutOfMemory,
        .ACCESS_DENIED, .USER_MAPPED_FILE => return error.AccessDenied,
        .STOPPED_ON_SYMLINK, .REPARSE_POINT_NOT_RESOLVED => return error.SymLinkNotResolved,

        .INVALID_PARAMETER, .INVALID_HANDLE => if (nt_path.is_device) return error.Unexpected else unreachable,

        else => |status| {
            std.log.err("Unexpected NtOpenFile error: '{s}' ({})", .{
                std.enums.tagName(win32.NTSTATUS, status) orelse "", @intFromEnum(status),
            });
            return error.Unexpected;
        },
    }
}

pub fn openDirAt(dir: fs.Dir, path: [:0]const u8, options: fs.OpenDirAtOptions) fs.OpenDirAtError!fs.Dir {
    var nt_path_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
    const nt_path = try toNtPath(dir, path, &nt_path_buf);

    if (nt_path.is_device) return error.BadPath;

    var handle: Handle = undefined;
    var io_status_block: win32.NT.IO_STATUS_BLOCK = undefined;
    const object_attributes = nt_path.ntObjectAttributes();

    const status = switch (win32.NT.NtOpenFile(
        &handle,
        .{
            .SYNCHRONIZE = true,
            .specific = .{
                .FILE = bits.unionAll(win32.ACCESS_MASK.FILE, &.{
                    .TRAVERSE,
                    .{ .READ_ATTRIBUTES = true },
                    if (options.iterate) .LIST_DIRECTORY else .{},
                }),
            },
        },
        &object_attributes,
        &io_status_block,
        .{ .READ = true, .WRITE = true, .DELETE = true },
        .{
            .DIRECTORY_FILE = true,
            .SYNCHRONOUS_IO_NONALERT = true,
            .OPEN_FOR_BACKUP_INTENT = true,
            .OPEN_REPARSE_POINT = !options.follow_symlinks,
        },
    )) {
        .SUCCESS => return .{ .handle = handle },

        .OBJECT_NAME_INVALID,
        .OBJECT_PATH_INVALID,
        .OBJECT_PATH_SYNTAX_BAD,
        => return if (anyElementTooLong(nt_path)) error.NameTooLong else error.BadPath,

        .OBJECT_NAME_NOT_FOUND,
        .OBJECT_PATH_NOT_FOUND,
        .BAD_NETWORK_NAME,
        => return error.FileNotFound,

        .BAD_NETWORK_PATH => return error.BadPath,
        .NOT_A_DIRECTORY => return error.NotDir,
        .INSUFFICIENT_RESOURCES, .NO_MEMORY => return error.OutOfMemory,
        .ACCESS_DENIED, .USER_MAPPED_FILE => return error.AccessDenied,
        .SHARING_VIOLATION, .DELETE_PENDING => return error.DeviceBusy,

        .STOPPED_ON_SYMLINK, .REPARSE_POINT_NOT_RESOLVED => |s| blk: {
            if (options.follow_symlinks) return error.SymLinkNotResolved;
            break :blk s;
        },

        .INVALID_HANDLE, .INVALID_PARAMETER => unreachable,

        else => |s| s,
    };

    std.log.err("Unexpected NtOpenFile error: '{s}' ({})", .{
        std.enums.tagName(win32.NTSTATUS, status) orelse "", @intFromEnum(status),
    });
    return error.Unexpected;
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

const ParsedPath = struct {
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
    unicode_string: win32.NT.UNICODE_STRING,
    root_handle: ?win32.HANDLE,
    is_device: bool,

    inline fn ntObjectAttributes(this: *const NtPath) win32.NT.OBJECT_ATTRIBUTES {
        return .{
            .root_directory = this.root_handle,
            .object_name = &this.unicode_string,
            .attributes = .default,
            .security_descriptor = null,
            .security_quality_of_service = null,
        };
    }
};

fn toNtPath(dir: fs.Dir, unstripped_path: [:0]const u8, buf: [:0]u16) !NtPath {
    const parsed_path = try parsePath(unstripped_path);

    var path: []const u8 = unstripped_path;
    if (parsed_path.type != .verbatim) {
        while (path.len > 1 and isSep(unstripped_path[path.len - 1])) {
            if (unstripped_path[path.len - 2] == ':') break;
            path.len -= 1;
        }
    }

    var is_device = false;

    const name: [:0]u16, const handle: ?Handle, const need_device_check = values: switch (parsed_path.type) {
        .verbatim => {
            const name_len = try wtf8ToWtf16LeCheckedLen(buf, path);
            buf[name_len] = 0;
            buf[0..nt_path_prefix.len].* = nt_path_prefix;
            break :values .{ buf[0..name_len :0], null, true };
        },

        .local_device, .rooted, .drive_relative, .drive_absolute, .unc => {
            const name_len = try resolveNonVerbatimNonRelativeNtPath(path, parsed_path.type, buf);
            break :values .{ buf[0..name_len :0], null, true };
        },

        .relative => {
            const result = try resolveRelativeNtPath(dir, path, buf);
            is_device = result.is_dos_device;
            break :values .{ result.name, result.handle, false };
        },
    };

    if (need_device_check) is_device = blk: {
        if (!std.mem.startsWith(u16, name, &nt_path_prefix)) break :blk false;
        const rel = name[nt_path_prefix.len..];

        const dos_device_info = win32.NT.RtlIsDosDeviceName_U(rel);
        if (dos_device_info != 0) {
            const dos_device_len: u16 = @intCast((dos_device_info & 0xFFFF) / @sizeOf(u16));
            const dos_device_offset: u16 = @intCast(((dos_device_info & 0xFFFF0000) >> 16) / @sizeOf(u16));
            if (dos_device_offset == 0 and dos_device_len == rel.len) break :blk true;
        }

        const head = rel[0..(std.mem.indexOfScalar(u16, rel, path_sep) orelse rel.len)];
        break :blk eqlIgnoreCaseWtf16LiteralWtf8(head, "PIPE") or
            eqlIgnoreCaseWtf16LiteralWtf8(head, "GLOBALROOT") or
            eqlIgnoreCaseWtf16LiteralWtf8(head, "Device") or
            eqlIgnoreCaseWtf16LiteralWtf8(head, "DosDevices");
    };

    return .{
        .unicode_string = .{
            .buffer = name.ptr,
            .length = @intCast(name.len * @sizeOf(u16)),
            // Do not include null to avoid overflow when len == PATH_MAX_WIDE
            .maximum_length = @intCast(name.len * @sizeOf(u16)),
        },
        .root_handle = handle,
        .is_device = is_device,
    };
}

const ResolveResult = struct {
    name: [:0]u16,
    handle: ?win32.HANDLE,
    is_dos_device: bool,
};

fn resolveRelativeNtPath(dir: fs.Dir, path: []const u8, dest: [:0]u16) !ResolveResult {
    var name_len = try wtf8ToWtf16LeCheckedLen(dest, path);
    dest[name_len] = 0;

    const dos_dev_info = win32.NT.RtlIsDosDeviceName_U(dest[0..name_len :0]);

    if (dos_dev_info == 0) return resolveRelativeNtPathInner(dir, path, name_len, dest);

    const dos_dev_len: u16 = @intCast((dos_dev_info & 0xFFFF) / @sizeOf(u16));
    const dos_dev_offset: u16 = @intCast(((dos_dev_info & 0xFFFF0000) >> 16) / @sizeOf(u16));

    var dev_buffer: [16]u16 = undefined;
    if (dev_buffer.len < dos_dev_len) return error.BadPath;
    @memcpy(dev_buffer[0..dos_dev_len], dest[dos_dev_offset..][0..dos_dev_len]);

    if (dos_dev_offset != 0) {
        const narrow_dir_prefix = if (std.mem.findLastAny(u8, path, "/\\")) |i|
            path[0 .. i + 1]
        else
            unreachable; // RtlIsDosDeviceName_U only returns a non-zero offset after crossing a separator.

        const dir_r = try resolveRelativeNtPathInner(dir, narrow_dir_prefix, dos_dev_offset, dest);

        if (!try ntPathIsDirOrVolumeRoot(dir_r.handle, dir_r.name)) return error.BadPath;
    }

    @memcpy(dest[nt_path_prefix.len..][0..dos_dev_len], dev_buffer[0..dos_dev_len]);
    dest[0..nt_path_prefix.len].* = nt_path_prefix;
    name_len = nt_path_prefix.len + dos_dev_len;
    dest[name_len] = 0;

    return .{ .name = dest[0..name_len :0], .handle = null, .is_dos_device = true };
}

fn resolveRelativeNtPathInner(dir: fs.Dir, narrow_path: []const u8, wide_len: usize, dest: [:0]u16) !ResolveResult {
    if (std.os.windows.normalizePath(u16, dest[0..wide_len])) |normalized_len| {
        dest[normalized_len] = 0;

        const trimmed_len = trimTrailingDotsAndSpacesPerElement(dest[0..normalized_len :0]);

        return .{ .name = dest[0..trimmed_len :0], .handle = dir.handle, .is_dos_device = false };
    } else |e| switch (e) {
        error.TooManyParentDirs => {
            const name_len = try resolveRelativeEscapingDirHandleNtPath(dir, narrow_path, dest);
            return .{ .name = dest[0..name_len :0], .handle = null, .is_dos_device = false };
        },
    }

    unreachable;
}

fn trimTrailingDotsAndSpacesPerElement(path: [:0]u16) usize {
    var read: usize = 0;
    var write: usize = 0;

    while (read < path.len) {
        var end = read;
        while (end < path.len and path[end] != path_sep) end += 1;

        const last_element = end == path.len;

        if (write != 0) {
            path[write] = path_sep;
            write += 1;
        }

        var len = end - read;

        if (last_element) {
            while (len > 0 and (path[read..][len - 1] == '.' or path[read..][len - 1] == ' '))
                len -= 1;
        } else if (len > 0 and path[read..][len - 1] == '.' and !(len > 1 and path[read..][len - 2] == '.'))
            len -= 1;

        @memmove(path[write..][0..len], path[read..][0..len]);
        write += len;

        read = end + 1;
    }

    path[write] = 0;

    return write;
}

fn resolveNonVerbatimNonRelativeNtPath(path: []const u8, path_type: ParsedPath.Type, dest: [:0]u16) !usize {
    const r = try resolveAndPrefixNonVerbatimNonRelative(path, path_type, dest);
    if (!r.device_synthesized) return r.len;

    const prefix = if (std.mem.findLastAny(u8, path, "/\\")) |last_sep_idx|
        path[0 .. last_sep_idx + 1]
    else if (std.mem.findScalar(u8, path, ':')) |last_colon_idx|
        path[0 .. last_colon_idx + 1]
    else
        return error.BadPath;

    const parsed_prefix = try parsePath(prefix);
    const prefix_r = try resolveAndPrefixNonVerbatimNonRelative(prefix, parsed_prefix.type, dest);

    if (!try ntPathIsDirOrVolumeRoot(null, dest[0..prefix_r.len :0])) return error.BadPath;

    // Previous value was overwritten by resolving the prefix.
    _ = try resolveAndPrefixNonVerbatimNonRelative(path, path_type, dest);
    return r.len;
}

fn ntPathIsDirOrVolumeRoot(dir: ?win32.HANDLE, path: [:0]u16) error{AccessDenied}!bool {
    const prefix_unicode = win32.NT.UNICODE_STRING.init(path);
    const object_attributes = win32.NT.OBJECT_ATTRIBUTES{
        .root_directory = dir,
        .object_name = &prefix_unicode,
        .attributes = .default,
        .security_descriptor = null,
        .security_quality_of_service = null,
    };

    var info: win32.NT.FILE.BASIC_INFORMATION = undefined;
    const query_res = win32.NT.NtQueryAttributesFile(&object_attributes, &info);

    switch (query_res) {
        .SUCCESS => return info.file_attributes.DIRECTORY,

        // Can't determine if dir at this point.
        .ACCESS_DENIED => return error.AccessDenied,
        else => return false,
    }
}

const ResolveAndPrefixResult = struct {
    len: usize,
    device_synthesized: bool,
};

fn resolveAndPrefixNonVerbatimNonRelative(path: []const u8, path_type: ParsedPath.Type, dest: [:0]u16) !ResolveAndPrefixResult {
    const resolve_offset: usize = switch (path_type) {
        .verbatim, .relative => unreachable,
        .local_device => 0,
        .rooted, .drive_relative, .drive_absolute => 4,
        .unc => 6,
    };

    var wide_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
    const name_len = try wtf8ToWtf16LeCheckedLen(&wide_buf, path);
    wide_buf[name_len] = 0;

    const cap: u32 = @intCast((1 + dest.len - resolve_offset) * @sizeOf(u16));
    const result_len_bytes = win32.NT.RtlGetFullPathName_U(&wide_buf, cap, dest[resolve_offset..], null);
    // Assume the only way RtlGetFullPathName_U can fail is NameTooLong,
    // malformed paths should have been rejected already.
    if (result_len_bytes == 0) return error.NameTooLong;
    if (result_len_bytes >= cap) return error.NameTooLong;

    const result_len = result_len_bytes / @sizeOf(u16);

    var device_synthesized = false;

    var total_len = resolve_offset + result_len;
    if (resolve_offset > 0 and
        result_len >= 4 and
        dest[resolve_offset] == '\\' and dest[resolve_offset + 1] == '\\')
    {
        if (dest[resolve_offset + 2] == '.' and dest[resolve_offset + 3] == '\\') {
            device_synthesized = true;
            @memmove(dest[0..result_len], dest[resolve_offset..][0..result_len]);
            total_len -= 4;
            dest[total_len] = 0;
        } else {
            if (resolve_offset != 6) {
                const shifted_len = total_len + 2;
                if (shifted_len > dest.len) return error.NameTooLong;
                @memmove(dest[8..][0 .. result_len - 2], dest[resolve_offset + 2 ..][0 .. result_len - 2]);
                total_len = shifted_len;
            }
            dest[nt_path_prefix.len..][0..4].* = .{ 'U', 'N', 'C', '\\' };
            dest[total_len] = 0;
        }
    }

    dest[0..nt_path_prefix.len].* = nt_path_prefix;
    return .{ .len = total_len, .device_synthesized = device_synthesized };
}

fn resolveRelativeEscapingDirHandleNtPath(dir: fs.Dir, path: []const u8, dest: [:0]u16) !usize {
    var buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;

    var dir_path_len = win32.GetFinalPathNameByHandleW(dir.handle, &buf, buf.len + 1, .{ .VOLUME_NAME = .DOS });
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
                dir_path_len = win32.GetFinalPathNameByHandleW(dir.handle, &buf, buf.len + 1, .{ .VOLUME_NAME = .GUID });
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

    if (dir_path_len + 1 > buf.len) return error.NameTooLong;
    buf[dir_path_len] = path_sep;

    const path_len = try wtf8ToWtf16LeCheckedLen(buf[dir_path_len + 1 ..], path);
    const unresolved_len = dir_path_len + path_len + 1;
    buf[unresolved_len] = 0;
    var unresolved_name = buf[0..unresolved_len :0];

    const strip_count: usize = if (std.mem.startsWith(u16, unresolved_name, &unc_dos_prefix)) 8 else 4;
    unresolved_name = unresolved_name[strip_count.. :0];
    const resolve_offset: usize = if (strip_count == 8) 6 else 4;

    const dest_len_bytes = (dest.len + 1 - resolve_offset) * @sizeOf(u16);
    const result_len_bytes = win32.NT.RtlGetFullPathName_U(unresolved_name, @intCast(dest_len_bytes), dest[resolve_offset..].ptr, null);
    // Assume the only way RtlGetFullPathName_U can fail is NameTooLong,
    // malformed paths should have been rejected already.
    assert(result_len_bytes != 0);
    if (result_len_bytes >= dest_len_bytes) return error.NameTooLong;

    const resolved_len: usize = (result_len_bytes / @sizeOf(u16));
    var result_len = resolve_offset + resolved_len;

    if (resolve_offset == 4 and std.mem.startsWith(u16, dest[resolve_offset..], &local_device_prefix)) {
        const tail_len = resolved_len - local_device_prefix.len;
        @memmove(dest[resolve_offset..][0..tail_len], dest[resolve_offset + local_device_prefix.len ..][0..tail_len]);
        result_len = resolve_offset + tail_len;
        dest[result_len] = 0;
    }

    if (resolve_offset == 6) {
        dest[0..unc_nt_prefix.len].* = unc_nt_prefix;
    } else {
        dest[0..nt_path_prefix.len].* = nt_path_prefix;
    }

    return result_len;
}

inline fn wtf8ToWtf16LeCheckedLen(dest: []u16, src: []const u8) error{ NameTooLong, BadPath }!usize {
    const wide_len = std.unicode.calcWtf16LeLen(src) catch return error.BadPath;
    if (wide_len > dest.len) return error.NameTooLong;

    const actual_wide_len = std.unicode.wtf8ToWtf16Le(dest, src) catch unreachable;
    assert(actual_wide_len == wide_len);

    return wide_len;
}

inline fn eqlIgnoreCaseWtf16LiteralWtf8(head: []const u16, comptime name: []const u8) bool {
    return std.os.windows.eqlIgnoreCaseWtf16(head, std.unicode.utf8ToUtf16LeStringLiteral(name));
}

inline fn anyElementTooLong(nt_path: NtPath) bool {
    var it = std.mem.splitScalar(u16, nt_path.unicode_string.slice(), path_sep);
    while (it.next()) |element| {
        if (element.len > win32.NAME_MAX) return true;
    }

    return false;
}

test toNtPath {
    const t = std.testing;

    const test_nt_path_prefix: [4]u16 = .{ '\\', '?', '?', '\\' };
    const test_verbatim_prefix: [4]u16 = .{ '\\', '\\', '?', '\\' };

    const F = struct {
        pub fn testToNtPathAgainstRtl(unstripped_path: [:0]const u8, expected_path_type: ParsedPath.Type) !void {
            const parsed = try parsePath(unstripped_path);
            try t.expectEqual(expected_path_type, parsed.type);

            var path: []const u8 = unstripped_path;
            if (parsed.type != .verbatim) {
                while (path.len > 1 and isSep(path[path.len - 1])) {
                    if (path[path.len - 2] == ':') break;
                    path.len -= 1;
                }
            }

            var buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
            const result_or_err = toNtPath(cwd(), unstripped_path, &buf);

            var expected_name_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
            const expected_name_len = try std.unicode.wtf8ToWtf16Le(&expected_name_buf, path);
            expected_name_buf[expected_name_len] = 0;
            const expected_name = expected_name_buf[0..expected_name_len :0];

            var rtl_expected_unicode: win32.NT.UNICODE_STRING = undefined;
            switch (win32.NT.RtlDosPathNameToNtPathName_U_WithStatus(expected_name, &rtl_expected_unicode, null, null)) {
                else => |status| {
                    try t.expectEqual(win32.NTSTATUS.SUCCESS, status);

                    defer win32.NT.RtlFreeUnicodeString(&rtl_expected_unicode);

                    const result = try result_or_err;

                    var expected_result = rtl_expected_unicode.slice();

                    // std.debug.print("expected_result: '{f}'\n", .{std.unicode.fmtUtf16Le(expected_result)});

                    if (result.root_handle) |handle| {
                        try t.expectEqual(fs.cwd().handle, handle);
                        try t.expect(!result.is_device);

                        var handle_path_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
                        const handle_path_len = win32.GetFinalPathNameByHandleW(handle, &handle_path_buf, handle_path_buf.len + 1, .{ .VOLUME_NAME = .DOS });
                        try t.expect(handle_path_len != 0);
                        try t.expect(handle_path_len != handle_path_buf.len + 1);

                        var handle_path = handle_path_buf[0..handle_path_len :0];
                        try t.expectEqualSlices(u16, &test_verbatim_prefix, handle_path[0..test_verbatim_prefix.len]);
                        handle_path[0..test_nt_path_prefix.len].* = test_nt_path_prefix;

                        // std.debug.print("handle_path: '{f}'\n", .{std.unicode.fmtUtf16Le(handle_path)});

                        try t.expect(expected_result.len >= handle_path.len);
                        try t.expectEqualSlices(u16, handle_path, expected_result[0..handle_path.len]);

                        var expected_rem = expected_result[handle_path_len..];
                        // std.debug.print("expected_rem: '{f}'\n", .{std.unicode.fmtUtf16Le(expected_rem)});
                        try t.expect(expected_rem.len >= result.unicode_string.slice().len);

                        expected_result = expected_rem[expected_rem.len - result.unicode_string.slice().len .. :0];
                        expected_rem.len -= expected_result.len;

                        for (expected_rem) |char| try t.expectEqual('\\', char);
                    }

                    if (!std.mem.eql(u16, expected_result, result.unicode_string.slice())) {
                        std.debug.print("expected: '{f}', got: '{f}' (has_handle: {})\n", .{
                            std.unicode.fmtUtf16Le(expected_result),
                            std.unicode.fmtUtf16Le(result.unicode_string.slice()),
                            result.root_handle != null,
                        });
                        return error.TestExpectedEqual;
                    }
                },

                .OBJECT_NAME_INVALID => {
                    try t.expectError(error.BadPath, result_or_err);
                },
            }
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
            const dir_len = win32.GetFinalPathNameByHandleW(cwd().handle, &expected_buf, expected_buf.len + 1, .{ .VOLUME_NAME = .DOS });
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

    try testToNtPathAgainstRtl("...", .relative);
    try testToNtPathAgainstRtl("a.b. ", .relative);
    try testToNtPathAgainstRtl("a. . ", .relative);
    try testToNtPathAgainstRtl("x\\... ", .relative);

    try testToNtPathAgainstRtl("a.\\b", .relative);
    try testToNtPathAgainstRtl("a. \\b", .relative);
    try testToNtPathAgainstRtl("a \\b", .relative);
    try testToNtPathAgainstRtl("a..b", .relative);

    try testToNtPathAgainstRtl("a..\\y", .relative);
    try testToNtPathAgainstRtl("x\\...\\y", .relative);

    // verbatim
    try testToNtPathAgainstRtl("\\\\?\\C:\\foo", .verbatim);
    try testToNtPathAgainstRtl("\\\\?\\C:\\foo\\", .verbatim);
    try testToNtPathAgainstRtl("\\\\?\\C:\\foo\\..\\bar", .verbatim);
    try testToNtPathAgainstRtl("\\\\?\\C:\\foo.", .verbatim);
    try testToNtPathAgainstRtl("\\\\?\\C:\\foo ", .verbatim);
    try testToNtPathAgainstRtl("\\\\?\\C:\\", .verbatim);
    try testToNtPathAgainstRtl("\\\\?\\UNC\\server\\share\\foo", .verbatim);
    try testToNtPathAgainstRtl("\\\\?\\UNC\\", .verbatim);
    try testToNtPathAgainstRtl("\\\\?\\C:/foo", .verbatim);
    try testToNtPathAgainstRtl("\\\\?\\Volume{GUID}\\", .verbatim);
    try testToNtPathAgainstRtl("\\\\?\\GLOBALROOT\\Device\\HarddiskVolume1\\", .verbatim);
    try testToNtPathAgainstRtl("\\\\?\\C:", .verbatim);
    try testToNtPathAgainstRtl("\\\\?\\C:\\abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", .verbatim);

    // drive_absolute
    try testToNtPathAgainstRtl("C:\\foo", .drive_absolute);
    try testToNtPathAgainstRtl("C:/foo", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\foo\\", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\\\foo", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\foo\\..\\bar", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\foo\\.", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\foo ", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\foo. ", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\foo .", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\.", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\foo\\.", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\..\\foo", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\..\\..\\foo", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\foo:bar", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\foo:", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\foo::$DATA", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\CON", .drive_absolute);
    try testToNtPathAgainstRtl("c:\\CON ", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\foo*.txt", .drive_absolute);
    try testToNtPathAgainstRtl("c:\\foo", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\Foo\\BAR", .drive_absolute);
    try testToNtPathAgainstRtl("é:\\foo", .drive_absolute);
    try testToNtPathAgainstRtl("1:\\foo", .drive_absolute);
    try testToNtPathAgainstRtl("?:\\foo", .drive_absolute);
    try testToNtPathAgainstRtl("::\\foo", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\dir\\😀\\file", .drive_absolute);

    // local_device
    try testToNtPathAgainstRtl("\\\\.\\C:\\foo", .local_device);
    try testToNtPathAgainstRtl("\\\\.\\C:", .local_device);
    try testToNtPathAgainstRtl("\\\\.\\Volume{GUID}\\", .local_device);
    try testToNtPathAgainstRtl("\\\\.\\UNC\\server\\share\\foo", .local_device);
    try testToNtPathAgainstRtl("\\\\.\\PIPE\\name", .local_device);
    try testToNtPathAgainstRtl("\\\\.\\GLOBALROOT\\Device\\HarddiskVolume1\\", .local_device);
    try testToNtPathAgainstRtl("\\\\.\\COM1", .local_device);
    try testToNtPathAgainstRtl("\\\\.\\C:\\foo\\..\\bar", .local_device);
    try testToNtPathAgainstRtl("\\\\.\\unix\\path", .local_device);
    try testToNtPathAgainstRtl("//?/C:\\foo", .local_device);
    try testToNtPathAgainstRtl("//?/foo", .local_device);

    // unc
    try testToNtPathAgainstRtl("\\\\server\\share\\foo", .unc);
    try testToNtPathAgainstRtl("\\\\server\\share", .unc);
    try testToNtPathAgainstRtl("\\\\server\\share\\", .unc);
    try testToNtPathAgainstRtl("\\\\a\\b", .unc);
    try testToNtPathAgainstRtl("//server/share/foo", .unc);
    try testToNtPathAgainstRtl("\\\\server\\share\\foo\\..\\bar", .unc);
    try testToNtPathAgainstRtl("\\\\127.0.0.1\\c$\\foo", .unc);
    try testToNtPathAgainstRtl("\\\\127.0.0.1\\c$\\", .unc);
    try testToNtPathAgainstRtl("\\\\??\\C:\\foo", .unc);
    try testToNtPathAgainstRtl("\\\\server\\\\share", .unc);
    try testToNtPathAgainstRtl("\\\\fe80::1\\share", .unc);
    try testToNtPathAgainstRtl("\\\\srv\\é\\share", .unc);

    // rooted
    try testToNtPathAgainstRtl("\\foo", .rooted);
    try testToNtPathAgainstRtl("/foo", .rooted);
    try testToNtPathAgainstRtl("\\foo\\", .rooted);
    try testToNtPathAgainstRtl("\\", .rooted);
    try testToNtPathAgainstRtl("\\C:\\", .rooted);
    try testToNtPathAgainstRtl("\\foo\\..\\bar", .rooted);
    try testToNtPathAgainstRtl("\\..", .rooted);
    try testToNtPathAgainstRtl("\\Device\\HarddiskVolume1\\foo", .rooted);

    // drive_relative
    try testToNtPathAgainstRtl("C:foo", .drive_relative);
    try testToNtPathAgainstRtl("C:", .drive_relative);
    try testToNtPathAgainstRtl("C:a\\b", .drive_relative);
    try testToNtPathAgainstRtl("C::\\foo", .drive_relative);
    try testToNtPathAgainstRtl("c:foo", .drive_relative);
    try testToNtPathAgainstRtl("é:foo", .drive_relative);

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
    try testToNtPathRelativeNoEscape("a.", "a");
    try testToNtPathRelativeNoEscape("a ", "a");
    try testToNtPathRelativeNoEscape("...", "");
    try testToNtPathRelativeNoEscape("..a", "..a");
    try testToNtPathAgainstRtl("con.", .relative);
    try testToNtPathAgainstRtl("con ", .relative);
    try testToNtPathAgainstRtl("src\\con ", .relative); // Assumes .\\src is a dir

    // relative (escaping root handle)
    try testToNtPathRelativeEscaping("..", 1, "");
    try testToNtPathRelativeEscaping("..\\..", 2, "");
    try testToNtPathRelativeEscaping("../foo", 1, "\\foo");
    try testToNtPathRelativeEscaping("a/../../b", 1, "\\b");
    try testToNtPathRelativeEscaping("..\\foo", 1, "\\foo");
    try testToNtPathRelativeEscaping("..\\..\\a\\b", 2, "\\a\\b");
    try testToNtPathRelativeEscaping("a\\..\\..\\..\\b", 2, "\\b");

    try testToNtPathAgainstRtl("C:CON", .drive_relative);
    try testToNtPathAgainstRtl("C:\\COM1", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\AUX", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\NUL", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\LPT1", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\PRN", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\CONIN$", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\CONOUT$", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\COM1.abc", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\COM1:abc", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\COM1    .abc", .drive_absolute);
    try testToNtPathAgainstRtl("\\CON", .rooted);
    try testToNtPathAgainstRtl("\\\\?\\C:\\COM1", .verbatim);
    try testToNtPathAgainstRtl("\\\\server\\share\\COM1", .unc);

    try testToNtPathAgainstRtl("foo\\CON", .relative);
    try testToNtPathAgainstRtl("src\\CON", .relative);
    try testToNtPathAgainstRtl("C:\\Windows\\CON", .drive_absolute);
    try testToNtPathAgainstRtl("C:\\notvalid\\COM1", .drive_absolute);
    try testToNtPathAgainstRtl("CON", .relative);
    try testToNtPathAgainstRtl("..\\..\\CON", .relative);
    try testToNtPathAgainstRtl("\\.CON", .rooted);
    try testToNtPathAgainstRtl("\\\\.\\CON", .local_device);
    try testToNtPathAgainstRtl("\\.\\CON", .rooted);
    try testToNtPathAgainstRtl("..\\notvalid\\CON", .relative);
    try testToNtPathAgainstRtl("..\\..\\notvalid\\CON", .relative);
    try testToNtPathAgainstRtl("C:\\NUL\\CON", .drive_absolute);

    try testToNtPathAgainstRtl("C:\\CON\\", .drive_absolute);
    try testToNtPathAgainstRtl("CON\\", .relative);
    try testToNtPathAgainstRtl("src\\CON\\", .relative);
    try testToNtPathAgainstRtl("foo\\CON\\", .relative);

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

    var absolute_exact_buf: [win32.PATH_MAX_WIDE + 1]u8 = undefined;
    @memcpy(absolute_exact_buf[0..3], "C:\\");
    @memset(absolute_exact_buf[3..win32.PATH_MAX_WIDE], 'a');
    absolute_exact_buf[win32.PATH_MAX_WIDE] = 0;
    try testToNtPathLength(absolute_exact_buf[0..win32.PATH_MAX_WIDE :0], error.NameTooLong);

    var rooted_long_buf: [win32.PATH_MAX_WIDE + 1]u8 = undefined;
    rooted_long_buf[0] = '\\';
    @memset(rooted_long_buf[1..win32.PATH_MAX_WIDE], 'a');
    rooted_long_buf[win32.PATH_MAX_WIDE] = 0;
    try testToNtPathLength(rooted_long_buf[0..win32.PATH_MAX_WIDE :0], error.NameTooLong);

    {
        var dir_buf: [win32.PATH_MAX_WIDE:0]u16 = undefined;
        const dir_len = win32.GetFinalPathNameByHandleW(cwd().handle, &dir_buf, dir_buf.len, .{ .VOLUME_NAME = .DOS });
        if (dir_len == 0 or dir_len >= dir_buf.len) return error.TestUnexpected;

        const escape_head = "..\\";
        var escaping_buf: [win32.PATH_MAX_WIDE]u8 = undefined;
        const filler_len = win32.PATH_MAX_WIDE - dir_len - escape_head.len;
        @memcpy(escaping_buf[0..escape_head.len], escape_head);
        @memset(escaping_buf[escape_head.len..][0..filler_len], 'a');
        escaping_buf[escape_head.len + filler_len] = 0;
        try testToNtPathLength(escaping_buf[0 .. escape_head.len + filler_len :0], error.NameTooLong);
    }
    {
        const wide_count = 20000;
        var utf8_buf: [40010]u8 = undefined;
        @memcpy(utf8_buf[0..3], "..\\");
        var i: usize = 3;
        while (i < 3 + wide_count * 2) : (i += 2) @memcpy(utf8_buf[i..][0..2], "\u{00E9}");
        utf8_buf[i] = 0;

        var utf8_res: [win32.PATH_MAX_WIDE:0]u16 = undefined;
        const r = try toNtPath(cwd(), utf8_buf[0..i :0], &utf8_res);
        try t.expect(r.root_handle == null); // escaped the handle, so it resolved absolutely

        var tail: [wide_count]u16 = undefined;
        @memset(&tail, 0x00E9);
        try t.expect(std.mem.endsWith(u16, r.unicode_string.slice(), &tail));
    }
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
