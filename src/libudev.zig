const std = @import("std");
const log = std.log.scoped(.libudev);

const c = @cImport({
    @cInclude("libudev.h");
});

pub const Context = opaque {};
pub const Monitor = opaque {};
pub const Device = opaque {};
pub const Enumerator = opaque {};
pub const ListEntry = opaque {};

fn new_stub() callconv(.c) ?*Context {
    return null;
}
const FN_new = @TypeOf(new_stub);
pub var new: *const FN_new = undefined;

fn ref_stub(udev: *Context) callconv(.c) ?*Context {
    _ = udev;
    return null;
}
const FN_ref = @TypeOf(ref_stub);
pub var ref: *const FN_ref = undefined;

fn unref_stub(udev: *Context) callconv(.c) ?*Context {
    _ = udev;
    return null;
}
const FN_unref = @TypeOf(unref_stub);
pub var unref: *const FN_unref = undefined;

fn monitor_new_from_netlink_stub(udev: *Context, name: ?[*:0]const u8) callconv(.c) ?*Monitor {
    _ = udev;
    _ = name;
    return null;
}
const FN_monitor_new_from_netlink = @TypeOf(monitor_new_from_netlink_stub);
pub var monitor_new_from_netlink: *const FN_monitor_new_from_netlink = undefined;

fn monitor_ref_stub(monitor: *Monitor) callconv(.c) ?*Monitor {
    _ = monitor;
    return null;
}
const FN_monitor_ref = @TypeOf(monitor_ref_stub);
pub var monitor_ref: *const FN_monitor_ref = undefined;

fn monitor_unref_stub(monitor: *Monitor) callconv(.c) ?*Monitor {
    _ = monitor;
    return null;
}
const FN_monitor_unref = @TypeOf(monitor_unref_stub);
pub var monitor_unref: *const FN_monitor_unref = undefined;

fn monitor_get_fd_stub(monitor: *Monitor) callconv(.c) c_int {
    _ = monitor;
    return -1;
}
const FN_monitor_get_fd = @TypeOf(monitor_get_fd_stub);
pub var monitor_get_fd: *const FN_monitor_get_fd = undefined;

fn monitor_receive_device_stub(monitor: *Monitor) callconv(.c) ?*Device {
    _ = monitor;
    return null;
}
const FN_monitor_receive_device = @TypeOf(monitor_receive_device_stub);
pub var monitor_receive_device: *const FN_monitor_receive_device = undefined;

fn device_unref_stub(device: *Device) callconv(.c) ?*Device {
    _ = device;
    return null;
}
const FN_device_unref = @TypeOf(device_unref_stub);
pub var device_unref: *const FN_device_unref = undefined;

fn device_new_from_syspath_stub(udev: *Context, syspath: ?[*:0]const u8) callconv(.c) ?*Device {
    _ = udev;
    _ = syspath;
    return null;
}
const FN_device_new_from_syspath = @TypeOf(device_new_from_syspath_stub);
pub var device_new_from_syspath: *const FN_device_new_from_syspath = undefined;

fn monitor_enable_receiving_stub(monitor: *Monitor) callconv(.c) c_int {
    _ = monitor;
    return 0;
}
const FN_monitor_enable_receiving = @TypeOf(monitor_enable_receiving_stub);
pub var monitor_enable_receiving: *const FN_monitor_enable_receiving = undefined;

fn monitor_filter_add_match_subsystem_devtype_stub(monitor: *Monitor, subsystem: ?[*:0]const u8, devtype: ?[*:0]const u8) callconv(.c) c_int {
    _ = monitor;
    _ = subsystem;
    _ = devtype;
    return 0;
}
const FN_monitor_filter_add_match_subsystem_devtype = @TypeOf(monitor_filter_add_match_subsystem_devtype_stub);
pub var monitor_filter_add_match_subsystem_devtype: *const FN_monitor_filter_add_match_subsystem_devtype = undefined;

fn device_get_syspath_stub(device: *Device) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_device_get_syspath = @TypeOf(device_get_syspath_stub);
pub var device_get_syspath: *const FN_device_get_syspath = undefined;

fn device_get_sysname_stub(device: *Device) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_device_get_sysname = @TypeOf(device_get_sysname_stub);
pub var device_get_sysname: *const FN_device_get_sysname = undefined;

fn device_get_devtype_stub(device: *Device) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_device_get_devtype = @TypeOf(device_get_devtype_stub);
pub var device_get_devtype: *const FN_device_get_devtype = undefined;

fn device_get_subsystem_stub(device: *Device) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_device_get_subsystem = @TypeOf(device_get_subsystem_stub);
pub var device_get_subsystem: *const FN_device_get_subsystem = undefined;

fn device_get_driver_stub(device: *Device) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_device_get_driver = @TypeOf(device_get_driver_stub);
pub var device_get_driver: *const FN_device_get_driver = undefined;

fn device_get_action_stub(device: *Device) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_device_get_action = @TypeOf(device_get_action_stub);
pub var device_get_action: *const FN_device_get_action = undefined;

fn device_get_devnode_stub(device: *Device) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_device_get_devnode = @TypeOf(device_get_devnode_stub);
pub var device_get_devnode: *const FN_device_get_devnode = undefined;

fn device_get_devpath_stub(device: *Device) callconv(.c) ?[*:0]const u8 {
    _ = device;
    return null;
}
const FN_device_get_devpath = @TypeOf(device_get_devpath_stub);
pub var device_get_devpath: *const FN_device_get_devpath = undefined;

fn device_get_property_value_stub(device: *Device, key: ?[*:0]const u8) callconv(.c) ?[*:0]const u8 {
    _ = device;
    _ = key;
    return null;
}
const FN_device_get_property_value = @TypeOf(device_get_property_value_stub);
pub var device_get_property_value: *const FN_device_get_property_value = undefined;

fn device_get_parent_stub(device: *Device) callconv(.c) ?*Device {
    _ = device;
    return null;
}
const FN_device_get_parent = @TypeOf(device_get_parent_stub);
pub var device_get_parent: *const FN_device_get_parent = undefined;

fn device_get_parent_with_subsystem_devtype_stub(device: *Device, subsystem: ?[*:0]const u8, devtype: ?[*:0]const u8) callconv(.c) ?*Device {
    _ = device;
    _ = subsystem;
    _ = devtype;
    return null;
}
const FN_device_get_parent_with_subsystem_devtype = @TypeOf(device_get_parent_with_subsystem_devtype_stub);
pub var device_get_parent_with_subsystem_devtype: *const FN_device_get_parent_with_subsystem_devtype = undefined;

fn enumerate_new_stub(udev: *Context) callconv(.c) ?*Enumerator {
    _ = udev;
    return null;
}
const FN_enumerate_new = @TypeOf(enumerate_new_stub);
pub var enumerate_new: *const FN_enumerate_new = undefined;

fn enumerate_unref_stub(enumerate: *Enumerator) callconv(.c) ?*Enumerator {
    _ = enumerate;
    return null;
}
const FN_enumerate_unref = @TypeOf(enumerate_unref_stub);
pub var enumerate_unref: *const FN_enumerate_unref = undefined;

fn enumerate_add_match_subsystem_stub(enumerate: *Enumerator, subsystem: ?[*:0]const u8) callconv(.c) c_int {
    _ = enumerate;
    _ = subsystem;
    return 0;
}
const FN_enumerate_add_match_subsystem = @TypeOf(enumerate_add_match_subsystem_stub);
pub var enumerate_add_match_subsystem: *const FN_enumerate_add_match_subsystem = undefined;

fn enumerate_add_match_parent_stub(enumerate: *Enumerator, parent: *Device) callconv(.c) c_int {
    _ = enumerate;
    _ = parent;
    return 0;
}
const FN_enumerate_add_match_parent = @TypeOf(enumerate_add_match_parent_stub);
pub var enumerate_add_match_parent: *const FN_enumerate_add_match_parent = undefined;

fn enumerate_scan_devices_stub(enumerate: *Enumerator) callconv(.c) c_int {
    _ = enumerate;
    return 0;
}
const FN_enumerate_scan_devices = @TypeOf(enumerate_scan_devices_stub);
pub var enumerate_scan_devices: *const FN_enumerate_scan_devices = undefined;

fn enumerate_get_list_entry_stub(enumerate: *Enumerator) callconv(.c) ?*ListEntry {
    _ = enumerate;
    return null;
}
const FN_enumerate_get_list_entry = @TypeOf(enumerate_get_list_entry_stub);
pub var enumerate_get_list_entry: *const FN_enumerate_get_list_entry = undefined;

fn list_entry_get_next_stub(entry: *ListEntry) callconv(.c) ?*ListEntry {
    _ = entry;
    return null;
}
const FN_list_entry_get_next = @TypeOf(list_entry_get_next_stub);
pub var list_entry_get_next: *const FN_list_entry_get_next = undefined;

fn list_entry_get_name_stub(entry: *ListEntry) callconv(.c) ?[*:0]const u8 {
    _ = entry;
    return null;
}
const FN_list_entry_get_name = @TypeOf(list_entry_get_name_stub);
pub var list_entry_get_name: *const FN_list_entry_get_name = undefined;

pub fn load() void {
    var lib = std.DynLib.open("libudev.so");

    var loaded = true;
    if (lib) |*l| {
        const struct_info = @typeInfo(@This()).@"struct";
        inline for (struct_info.decls) |decl| {
            const decl_type = @TypeOf(@field(@This(), decl.name));
            const decl_info = @typeInfo(decl_type);

            if (decl_info == .pointer and @typeInfo(decl_info.pointer.child) == .@"fn") {
                @field(@This(), decl.name) = l.lookup(decl_type, "udev_" ++ decl.name) orelse {
                    log.warn("Failed to load 'udev_{s}'", .{decl.name});
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
