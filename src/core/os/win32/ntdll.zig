const win32 = @import("win32.zig");
const assert = @import("../../assert.zig").assert;

const HANDLE = win32.HANDLE;
const THREAD = win32.THREAD;
const PROCESS = win32.PROCESS;
const USHORT = win32.USHORT;
const LONG = win32.LONG;
const ULONG = win32.ULONG;
const ULONGLONG = win32.ULONGLONG;
const LARGE_INTEGER = win32.LARGE_INTEGER;
const PWSTR = win32.PWSTR;
const PCWSTR = win32.PCWSTR;
const PVOID = win32.PVOID;
const LPVOID = win32.LPVOID;
const DWORD = win32.DWORD;
const BOOL = win32.BOOL;
const ULONG_PTR = win32.ULONG_PTR;

pub const NTSTATUS = @import("ntstatus.zig").NTSTATUS;
pub const CURRENT_PROCESS: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
pub const CURRENT_THREAD: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));

pub const LOGICAL = win32.BOOL;
comptime {
    assert(@sizeOf(LOGICAL) == @sizeOf(ULONG));
}

pub const OBJECT_ATTRIBUTES = extern struct {
    length: ULONG = @sizeOf(@This()),
    root_directory: ?HANDLE,
    object_name: *const UNICODE_STRING,
    attributes: FLAGS,
    security_descriptor: ?*anyopaque,
    security_quality_of_service: ?*anyopaque,

    pub const FLAGS = packed struct(ULONG) {
        __reserved0__: u1 = 0,
        INHERIT: bool = false,
        __reserved1__: u2 = 0,
        PERMANENT: bool = false,
        EXCLUSIVE: bool = false,
        CASE_INSENSITIVE: bool = false,
        OPENIF: bool = false,
        OPENLINK: bool = false,
        KERNEL_HANDLE: bool = false,
        FORCE_ACCESS_CHECK: bool = false,
        IGNORE_IMPERSONATED_DEVICEMAP: bool = false,
        DONT_REPARSE: bool = false,
        __reserved2__: u19 = 0,

        pub const default = FLAGS{ .CASE_INSENSITIVE = true };
    };
};

pub const FILE = struct {
    /// This must stay in sync with win32.FILE.FLAGS_AND_ATTRIBUTES.
    pub const ATTRIBUTES = packed struct(ULONG) {
        READONLY: bool = false,
        HIDDEN: bool = false,
        SYSTEM: bool = false,
        __reserved0__: u1 = 0,
        DIRECTORY: bool = false,
        ARCHIVE: bool = false,
        DEVICE: bool = false,
        NORMAL: bool = false,
        TEMPORARY: bool = false,
        SPARSE_FILE: bool = false,
        REPARSE_POINT: bool = false,
        COMPRESSED: bool = false,
        OFFLINE: bool = false,
        NOT_CONTENT_INDEXED: bool = false,
        ENCRYPTED: bool = false,
        INTEGRITY_STREAM: bool = false,
        VIRTUAL: bool = false,
        NO_SCRUB_DATA: bool = false,
        RECALL_ON_OPEN: bool = false,
        PINNED: bool = false,
        UNPINNED: bool = false,
        __reserved1__: u1 = 0,
        RECALL_ON_DATA_ACCESS: bool = false,
        __reserved2__: u6 = 0,
        STRICTLY_SEQUENTIAL: bool = false,
        __reserved3__: u2 = 0,

        pub const EA = @This(){ .RECALL_ON_OPEN = true };

        pub const default = @This(){ .NORMAL = true };
    };

    pub const BASIC_INFORMATION = extern struct {
        creation_time: LARGE_INTEGER,
        last_access_time: LARGE_INTEGER,
        last_write_time: LARGE_INTEGER,
        change_time: LARGE_INTEGER,
        file_attributes: ATTRIBUTES,
    };

    pub const SHARE = packed struct(DWORD) {
        READ: bool = false,
        WRITE: bool = false,
        DELETE: bool = false,
        __reserved__: @Int(.unsigned, @bitSizeOf(DWORD) - 3) = 0,
    };

    pub const MODE = packed struct(ULONG) {
        DIRECTORY_FILE: bool = false,
        WRITE_THROUGH: bool = false,
        SEQUENTIAL_ONLY: bool = false,
        NO_INTERMEDIATE_BUFFERING: bool = false,
        SYNCHRONOUS_IO_ALERT: bool = false,
        SYNCHRONOUS_IO_NONALERT: bool = false,
        NON_DIRECTORY_FILE: bool = false,
        CREATE_TREE_CONNECTION: bool = false,
        COMPLETE_IF_OPLOCKED: bool = false,
        NO_EA_KNOWLEDGE: bool = false,
        OPEN_REMOTE_INSTANCE: bool = false,
        RANDOM_ACCESS: bool = false,
        DELETE_ON_CLOSE: bool = false,
        OPEN_BY_FILE_ID: bool = false,
        OPEN_FOR_BACKUP_INTENT: bool = false,
        NO_COMPRESSION: bool = false,
        OPEN_REQUIRING_OPLOCK: bool = false,
        DISALLOW_EXCLUSIVE: bool = false,
        SESSION_AWARE: bool = false,
        __reserved0__: u1 = 0,
        RESERVE_OPFILTER: bool = false,
        OPEN_REPARSE_POINT: bool = false,
        OPEN_NO_RECALL: bool = false,
        OPEN_FOR_FREE_SPACE_QUERY: bool = false,
        __reserved1__: u8 = 0,
    };
};

pub const KERNEL_USER_TIMES = extern struct {
    create_time: LARGE_INTEGER,
    exit_time: LARGE_INTEGER,
    kernel_time: LARGE_INTEGER,
    user_time: LARGE_INTEGER,
};

pub const UNICODE_STRING = extern struct {
    /// !! In bytes !!
    length: USHORT,
    /// !! In bytes !!
    maximum_length: USHORT,
    buffer: PWSTR,

    pub fn init(wide_str: [:0]u16) UNICODE_STRING {
        return .{
            .length = @intCast(wide_str.len * @sizeOf(u16)),
            .maximum_length = @intCast((wide_str.len + 1) * @sizeOf(u16)),
            .buffer = wide_str.ptr,
        };
    }

    pub fn slice(this: *const UNICODE_STRING) [:0]u16 {
        return this.buffer[0 .. this.length / @sizeOf(u16) :0];
    }
};

pub const RTL_RELATIVE_NAME_U = extern struct {
    relative_name: UNICODE_STRING,
    containing_directory: HANDLE,
    cur_dir_ref: *RTLP_CURDIR_REF,
};

pub const RTLP_CURDIR_REF = extern struct {
    reference_count: LONG,
    directory_handle: HANDLE,
};

pub const OVERLAPPED = extern struct {
    internal: *ULONG,
    internal_high: *ULONG,

    dummy_union: extern union {
        dummy_struct: extern struct {
            offset: DWORD,
            offset_high: DWORD,
        },
        pointer: PVOID,
    },

    event: HANDLE,
};

pub const IO_STATUS_BLOCK = extern struct {
    u: extern union {
        status: NTSTATUS,
        pointer: ?PVOID,
    },
    information: ULONG_PTR,
};

pub const SECURITY_ATTRIBUTES = extern struct {
    length: DWORD = @sizeOf(@This()),
    security_descriptor: LPVOID,
    inherit_handle: BOOL,
};

pub const ACCESS_MASK = packed struct(DWORD) {
    specific: packed union(u16) {
        FILE: ACCESS_MASK.FILE,
        // TODO: KEY_*, PROCESS_*, THREAD_*
    } = .{ .FILE = .{} },

    DELETE: bool = false,
    READ_CONTROL: bool = false,
    WRITE_DAC: bool = false,
    WRITE_OWNER: bool = false,
    SYNCHRONIZE: bool = false,
    __reserved0__: u3 = 0,

    SYSTEM_SECURITY: bool = false,
    MAXIMUM_ALLOWED: bool = false,
    __reserved1__: u2 = 0,
    GENERIC_ALL: bool = false,
    GENERIC_EXECUTE: bool = false,
    GENERIC_WRITE: bool = false,
    GENERIC_READ: bool = false,

    pub const FILE = packed struct(u16) {
        READ_DATA: bool = false,
        WRITE_DATA: bool = false,
        APPEND_DATA: bool = false,
        READ_EA: bool = false,
        WRITE_EA: bool = false,
        EXECUTE: bool = false,
        DELETE_CHILD: bool = false,
        READ_ATTRIBUTES: bool = false,
        WRITE_ATTRIBUTES: bool = false,
        __reserved__: u7 = 0,

        pub const LIST_DIRECTORY = @This(){ .READ_DATA = true };
        pub const ADD_FILE = @This(){ .WRITE_DATA = true };
        pub const ADD_SUBDIRECTORY = @This(){ .APPEND_DATA = true };
        pub const CREATE_PIPE_INSTANCE = @This(){ .APPEND_DATA = true };
        pub const TRAVERSE = @This(){ .EXECUTE = true };
    };

    pub const SPECIFIC_RIGHTS_ALL: ACCESS_MASK = @bitCast(@as(DWORD, 0xFFFF));

    pub const STANDARD_RIGHTS_REQUIRED = ACCESS_MASK{ .DELETE = true, .READ_CONTROL = true, .WRITE_DAC = true, .WRITE_OWNER = true };
    pub const STANDARD_RIGHTS_READ = ACCESS_MASK{ .READ_CONTROL = true };
    pub const STANDARD_RIGHTS_WRITE = ACCESS_MASK{ .READ_CONTROL = true };
    pub const STANDARD_RIGHTS_EXECUTE = ACCESS_MASK{ .READ_CONTROL = true };
    pub const STANDARD_RIGHTS_ALL = ACCESS_MASK{ .DELETE = true, .READ_CONTROL = true, .WRITE_DAC = true, .WRITE_OWNER = true, .SYNCHRONIZE = true };
};

pub const FILETIME = extern union {
    u: extern struct {
        low: DWORD = 0,
        high: DWORD = 0,
    },

    // 100ns ticks
    ticks: u64 align(@alignOf(DWORD)),
};

pub extern "ntdll" fn NtQueryAttributesFile(object_attributes: *const OBJECT_ATTRIBUTES, file_info_out: *FILE.BASIC_INFORMATION) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtQueryInformationProcess(process_handle: HANDLE, process_info_class: PROCESS.INFOCLASS, process_info: *anyopaque, process_info_len: ULONG, return_len: *ULONG) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtQueryInformationThread(thread_handle: HANDLE, thread_info_class: THREAD.INFOCLASS, thread_info: *anyopaque, thread_info_len: ULONG, return_len: *ULONG) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtOpenFile(out_handle: *HANDLE, desired_access: ACCESS_MASK, object_attributes: *const OBJECT_ATTRIBUTES, out_io_status_block: *IO_STATUS_BLOCK, share_access: FILE.SHARE, open_options: FILE.MODE) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtClose(handle: HANDLE) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn RtlDosPathNameToNtPathName_U_WithStatus(dos_file_name: PCWSTR, nt_file_name_out: *UNICODE_STRING, file_part: ?PWSTR, relative_name: ?*RTL_RELATIVE_NAME_U) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn RtlFreeUnicodeString(unicode_string: *UNICODE_STRING) callconv(.winapi) void;
/// Returned length is in bytes!
pub extern "ntdll" fn RtlGetFullPathName_U(file_name: PCWSTR, buffer_length_bytes: ULONG, out_buffer: PWSTR, out_file_part: ?PWSTR) callconv(.winapi) ULONG;
pub extern "ntdll" fn RtlGetSystemTimePrecise() callconv(.winapi) ULONGLONG;
pub extern "ntdll" fn RtlIsDosDeviceName_U(dos_file_name: PCWSTR) callconv(.winapi) ULONG;
pub extern "ntdll" fn RtlQueryPerformanceCounter(perf_count: *LARGE_INTEGER) callconv(.winapi) LOGICAL;
pub extern "ntdll" fn RtlQueryPerformanceFrequency(freq: *LARGE_INTEGER) callconv(.winapi) LOGICAL;
