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
const OBJECT = win32.OBJECT;
const FILE = win32.FILE;

pub const NTSTATUS = @import("ntstatus.zig").NTSTATUS;
pub const CURRENT_PROCESS: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
pub const CURRENT_THREAD: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));

pub const LOGICAL = win32.BOOL;
comptime {
    assert(@sizeOf(LOGICAL) == @sizeOf(ULONG));
}

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

pub extern "ntdll" fn NtQueryAttributesFile(object_attributes: *const OBJECT.ATTRIBUTES, file_info_out: *FILE.BASIC_INFORMATION) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtQueryInformationProcess(process_handle: HANDLE, process_info_class: PROCESS.INFOCLASS, process_info: *anyopaque, process_info_len: ULONG, return_len: *ULONG) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtQueryInformationThread(thread_handle: HANDLE, thread_info_class: THREAD.INFOCLASS, thread_info: *anyopaque, thread_info_len: ULONG, return_len: *ULONG) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn RtlDosPathNameToNtPathName_U_WithStatus(dos_file_name: PCWSTR, nt_file_name_out: *UNICODE_STRING, file_part: ?PWSTR, relative_name: ?*RTL_RELATIVE_NAME_U) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn RtlFreeUnicodeString(unicode_string: *UNICODE_STRING) callconv(.winapi) void;
/// Returned length is in bytes!
pub extern "ntdll" fn RtlGetFullPathName_U(file_name: PCWSTR, buffer_length_bytes: ULONG, out_buffer: PWSTR, out_file_part: ?PWSTR) callconv(.winapi) ULONG;
pub extern "ntdll" fn RtlGetSystemTimePrecise() callconv(.winapi) ULONGLONG;
pub extern "ntdll" fn RtlIsDosDeviceName_U(dos_file_name: PCWSTR) callconv(.winapi) ULONG;
pub extern "ntdll" fn RtlQueryPerformanceCounter(perf_count: *LARGE_INTEGER) callconv(.winapi) LOGICAL;
pub extern "ntdll" fn RtlQueryPerformanceFrequency(freq: *LARGE_INTEGER) callconv(.winapi) LOGICAL;
