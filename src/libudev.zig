const std = @import("std");
const log = std.log.scoped(.libudev);

const c = @cImport({
    @cInclude("libudev.h");
});

pub const UDev = opaque {};
pub const UDevMonitor = opaque {};
pub const UDevDevice = opaque {};
pub const UDevEnumerate = opaque {};
pub const UDevListEntry = opaque {};

fn udev_new_stub() callconv(.c) ?*UDev {
    return null;
}
const FN_udev_new = @TypeOf(udev_new_stub);
pub var udev_new: *const FN_udev_new = undefined;

fn udev_ref_stub(udev: *UDev) callconv(.c) ?*UDev {
    _ = udev;
    return null;
}
const FN_udev_ref = @TypeOf(udev_ref_stub);
pub var udev_ref: *const FN_udev_ref = undefined;

fn udev_unref_stub(udev: *UDev) callconv(.c) ?*UDev {
    _ = udev;
    return null;
}
const FN_udev_unref = @TypeOf(udev_unref_stub);
pub var udev_unref: *const FN_udev_unref = undefined;

fn udev_monitor_new_from_netlink_stub(udev: *UDev, name: ?[*:0]const u8) callconv(.c) ?*UDevMonitor {
    _ = udev;
    _ = name;
    return null;
}
const FN_udev_monitor_new_from_netlink = @TypeOf(udev_monitor_new_from_netlink_stub);
pub var udev_monitor_new_from_netlink: *const FN_udev_monitor_new_from_netlink = undefined;

fn udev_monitor_ref_stub(monitor: *UDevMonitor) callconv(.c) ?*UDevMonitor {
    _ = monitor;
    return null;
}
const FN_udev_monitor_ref = @TypeOf(udev_monitor_ref_stub);
pub var udev_monitor_ref: *const FN_udev_monitor_ref = undefined;

fn udev_monitor_unref_stub(monitor: *UDevMonitor) callconv(.c) ?*UDevMonitor {
    _ = monitor;
    return null;
}
const FN_udev_monitor_unref = @TypeOf(udev_monitor_unref_stub);
pub var udev_monitor_unref: *const FN_udev_monitor_unref = undefined;

fn udev_monitor_get_fd_stub(monitor: *UDevMonitor) callconv(.c) c_int {
    _ = monitor;
    return -1;
}
const FN_udev_monitor_get_fd = @TypeOf(udev_monitor_get_fd_stub);
pub var udev_monitor_get_fd: *const FN_udev_monitor_get_fd = undefined;

fn udev_monitor_receive_device_stub(monitor: *UDevMonitor) callconv(.c) ?*UDevDevice {
    _ = monitor;
    return null;
}
const FN_udev_monitor_receive_device = @TypeOf(udev_monitor_receive_device_stub);
pub var udev_monitor_receive_device: *const FN_udev_monitor_receive_device = undefined;

fn udev_device_unref_stub(device: *UDevDevice) callconv(.c) ?*UDevDevice {
    _ = device;
    return null;
}
const FN_udev_device_unref = @TypeOf(udev_device_unref_stub);
pub var udev_device_unref: *const FN_udev_device_unref = undefined;

fn udev_device_new_from_syspath_stub(udev: *UDev, syspath: ?[*:0]const u8) callconv(.c) ?*UDevDevice {
    _ = udev;
    _ = syspath;
    return null;
}
const FN_udev_device_new_from_syspath = @TypeOf(udev_device_new_from_syspath_stub);
pub var udev_device_new_from_syspath: *const FN_udev_device_new_from_syspath = undefined;

fn udev_monitor_enable_receiving_stub(monitor: *UDevMonitor) callconv(.c) c_int {
    _ = monitor;
    return 0;
}
const FN_udev_monitor_enable_receiving = @TypeOf(udev_monitor_enable_receiving_stub);
pub var udev_monitor_enable_receiving: *const FN_udev_monitor_enable_receiving = undefined;

fn udev_monitor_filter_add_match_subsystem_devtype_stub(monitor: *UDevMonitor, subsystem: ?[*:0]const u8, devtype: ?[*:0]const u8) callconv(.c) c_int {
    _ = monitor;
    _ = subsystem;
    _ = devtype;
    return 0;
}
const FN_udev_monitor_filter_add_match_subsystem_devtype = @TypeOf(udev_monitor_filter_add_match_subsystem_devtype_stub);
pub var udev_monitor_filter_add_match_subsystem_devtype: *const FN_udev_monitor_filter_add_match_subsystem_devtype = undefined;

fn udev_device_get_syspath_stub(device: *UDevDevice) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_udev_device_get_syspath = @TypeOf(udev_device_get_syspath_stub);
pub var udev_device_get_syspath: *const FN_udev_device_get_syspath = undefined;

fn udev_device_get_sysname_stub(device: *UDevDevice) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_udev_device_get_sysname = @TypeOf(udev_device_get_sysname_stub);
pub var udev_device_get_sysname: *const FN_udev_device_get_sysname = undefined;

fn udev_device_get_devtype_stub(device: *UDevDevice) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_udev_device_get_devtype = @TypeOf(udev_device_get_devtype_stub);
pub var udev_device_get_devtype: *const FN_udev_device_get_devtype = undefined;

fn udev_device_get_subsystem_stub(device: *UDevDevice) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_udev_device_get_subsystem = @TypeOf(udev_device_get_subsystem_stub);
pub var udev_device_get_subsystem: *const FN_udev_device_get_subsystem = undefined;

fn udev_device_get_driver_stub(device: *UDevDevice) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_udev_device_get_driver = @TypeOf(udev_device_get_driver_stub);
pub var udev_device_get_driver: *const FN_udev_device_get_driver = undefined;

fn udev_device_get_action_stub(device: *UDevDevice) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_udev_device_get_action = @TypeOf(udev_device_get_action_stub);
pub var udev_device_get_action: *const FN_udev_device_get_action = undefined;

fn udev_device_get_devnode_stub(device: *UDevDevice) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_udev_device_get_devnode = @TypeOf(udev_device_get_devnode_stub);
pub var udev_device_get_devnode: *const FN_udev_device_get_devnode = undefined;

fn udev_device_get_devpath_stub(device: *UDevDevice) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_udev_device_get_devpath = @TypeOf(udev_device_get_devpath_stub);
pub var udev_device_get_devpath: *const FN_udev_device_get_devpath = undefined;

fn udev_device_get_property_value_stub(device: *UDevDevice, key: ?[*:0]const u8) callconv(.c) ?[*:0]const u8 {
    _ = device;
    _ = key;
    return null;
}
const FN_udev_device_get_property_value = @TypeOf(udev_device_get_property_value_stub);
pub var udev_device_get_property_value: *const FN_udev_device_get_property_value = undefined;

fn udev_device_get_parent_stub(device: *UDevDevice) callconv(.c) ?*UDevDevice {
    _ = device;
    return null;
}
const FN_udev_device_get_parent = @TypeOf(udev_device_get_parent_stub);
pub var udev_device_get_parent: *const FN_udev_device_get_parent = undefined;

fn udev_device_get_parent_with_subsystem_devtype_stub(device: *UDevDevice, subsystem: ?[*:0]const u8, devtype: ?[*:0]const u8) callconv(.c) ?*UDevDevice {
    _ = device;
    _ = subsystem;
    _ = devtype;
    return null;
}
const FN_udev_device_get_parent_with_subsystem_devtype = @TypeOf(udev_device_get_parent_with_subsystem_devtype_stub);
pub var udev_device_get_parent_with_subsystem_devtype: *const FN_udev_device_get_parent_with_subsystem_devtype = undefined;

fn udev_enumerate_new_stub(udev: *UDev) callconv(.c) ?*UDevEnumerate {
    _ = udev;
    return null;
}
const FN_udev_enumerate_new = @TypeOf(udev_enumerate_new_stub);
pub var udev_enumerate_new: *const FN_udev_enumerate_new = undefined;

fn udev_enumerate_unref_stub(enumerate: *UDevEnumerate) callconv(.c) ?*UDevEnumerate {
    _ = enumerate;
    return null;
}
const FN_udev_enumerate_unref = @TypeOf(udev_enumerate_unref_stub);
pub var udev_enumerate_unref: *const FN_udev_enumerate_unref = undefined;

fn udev_enumerate_add_match_subsystem_stub(enumerate: *UDevEnumerate, subsystem: ?[*:0]const u8) callconv(.c) c_int {
    _ = enumerate;
    _ = subsystem;
    return 0;
}
const FN_udev_enumerate_add_match_subsystem = @TypeOf(udev_enumerate_add_match_subsystem_stub);
pub var udev_enumerate_add_match_subsystem: *const FN_udev_enumerate_add_match_subsystem = undefined;

fn udev_enumerate_add_match_parent_stub(enumerate: *UDevEnumerate, parent: *UDevDevice) callconv(.c) c_int {
    _ = enumerate;
    _ = parent;
    return 0;
}
const FN_udev_enumerate_add_match_parent = @TypeOf(udev_enumerate_add_match_parent_stub);
pub var udev_enumerate_add_match_parent: *const FN_udev_enumerate_add_match_parent = undefined;

fn udev_enumerate_scan_devices_stub(enumerate: *UDevEnumerate) callconv(.c) c_int {
    _ = enumerate;
    return 0;
}
const FN_udev_enumerate_scan_devices = @TypeOf(udev_enumerate_scan_devices_stub);
pub var udev_enumerate_scan_devices: *const FN_udev_enumerate_scan_devices = undefined;

fn udev_enumerate_get_list_entry_stub(enumerate: *UDevEnumerate) callconv(.c) ?*UDevListEntry {
    _ = enumerate;
    return null;
}
const FN_udev_enumerate_get_list_entry = @TypeOf(udev_enumerate_get_list_entry_stub);
pub var udev_enumerate_get_list_entry: *const FN_udev_enumerate_get_list_entry = undefined;

fn udev_list_entry_get_next_stub(entry: *UDevListEntry) callconv(.c) ?*UDevListEntry {
    _ = entry;
    return null;
}
const FN_udev_list_entry_get_next = @TypeOf(udev_list_entry_get_next_stub);
pub var udev_list_entry_get_next: *const FN_udev_list_entry_get_next = undefined;

fn udev_list_entry_get_name_stub(entry: *UDevListEntry) callconv(.c) ?[*:0]const u8 {
    _ = entry;
    return null;
}
const FN_udev_list_entry_get_name = @TypeOf(udev_list_entry_get_name_stub);
pub var udev_list_entry_get_name: *const FN_udev_list_entry_get_name = undefined;

pub fn load() void {
    var lib = std.DynLib.open("libudev.so");

    var loaded = true;
    if (lib) |*l| {
        const struct_info = @typeInfo(@This()).@"struct";
        inline for (struct_info.decls) |decl| {
            const decl_type = @TypeOf(@field(@This(), decl.name));
            const decl_info = @typeInfo(decl_type);

            if (decl_info == .pointer and @typeInfo(decl_info.pointer.child) == .@"fn") {
                @field(@This(), decl.name) = l.lookup(decl_type, decl.name) orelse {
                    log.warn("Failed to load '{s}'", .{decl.name});
                    loaded = false;
                    break;
                };
            }
        }
    } else |_| {
        loaded = false;
    }

    if (!loaded) {
        log.warn("Udev not available, loading stubs", .{});
        loadStubs();
    }
}

fn loadStubs() void {
    const struct_info = @typeInfo(@This()).@"struct";
    inline for (struct_info.decls) |decl| {
        const decl_type = @TypeOf(@field(@This(), decl.name));
        const decl_info = @typeInfo(decl_type);

        if (decl_info == .pointer and @typeInfo(decl_info.pointer.child) == .@"fn") {
            @field(@This(), decl.name) = @field(@This(), decl.name ++ "_stub");
        }
    }
}
