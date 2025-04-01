const std = @import("std");
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");

const vklog = std.log.scoped(.vulkan);

const glfw = @import("glfw");

const alloc = @import("../alloc.zig");

const gfx = @import("gfx.zig");
const vk = gfx.vk;

const Window = @import("../window.zig");

const enable_validation_layers: bool = builtin.mode == .Debug;
const validation_layers = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
const device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

const debug_messenger_create_info = vk.DebugUtilsMessengerCreateInfoEXT{
    .message_severity = .{ .warning_bit_ext = true, .error_bit_ext = true },
    .message_type = .{ .general_bit_ext = true, .validation_bit_ext = true, .performance_bit_ext = true },
    .pfn_user_callback = debugCallback,
    .p_user_data = null,
};

system: *gfx.System,
window: *const Window,
vki: vk.InstanceProxy = undefined,
debug_messenger: vk.DebugUtilsMessengerEXT = .null_handle,
surface: vk.SurfaceKHR = .null_handle,
device_info: DeviceInfo = undefined,
device: vk.DeviceProxy = undefined,
graphics_queue: vk.QueueProxy = undefined,
present_queue: vk.QueueProxy = undefined,
command_pool: vk.CommandPool = undefined,

pub const DeviceInfo = struct {
    physical_device: vk.PhysicalDevice,
    properties: vk.PhysicalDeviceProperties,
    queue_family_indices: QueueFamilyIndices,
};

pub const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,
    present_family: ?u32 = null,

    pub fn isComplete(this: @This()) bool {
        return this.graphics_family != null and this.present_family != null;
    }

    pub fn uniqueFamilies(this: @This(), allocator: Allocator) ![]u32 {
        std.debug.assert(this.isComplete());

        var _indices = [_]u32{ this.graphics_family.?, this.present_family.? };
        var indices: []u32 = &_indices;

        std.mem.sort(u32, indices, .{}, struct {
            fn f(_: @TypeOf(.{}), l: u32, r: u32) bool {
                return l < r;
            }
        }.f);

        { // Rewrite the sorted list to unique number only
            var last_index: i32 = -1;
            var write_index: usize = 0;
            for (indices) |fi| {
                defer last_index = @intCast(fi);

                if (fi == last_index) continue;

                indices[write_index] = fi;
                write_index += 1;
            }
            indices = indices[0..write_index];
            vklog.debug("unique queue family indices: {any}", .{indices});
        }

        const result = try allocator.alloc(u32, indices.len);
        std.mem.copyForwards(u32, result, indices);
        return result;
    }
};

pub const SwapchainSupportDetails = struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,

    pub fn free(this: @This(), allocator: Allocator) void {
        if (this.formats.len > 0) allocator.free(this.formats);
        if (this.present_modes.len > 0) allocator.free(this.present_modes);
    }
};

pub fn create(system: *gfx.System, window: *const Window) !@This() {
    var this = @This(){
        .system = system,
        .window = window,
    };

    try this.createInstance();
    try this.setupDebugMessenger();
    try this.createSurface();
    try this.pickPhysicalDevice(alloc.gpa);
    try this.createLogicalDevice(alloc.gpa);
    try this.createCommandPool();

    return this;
}

pub fn destroy(this: *@This()) void {
    const device = this.device;
    const vki = this.vki;

    device.destroyCommandPool(this.command_pool, null);
    device.destroyDevice(null);

    if (enable_validation_layers) {
        vki.destroyDebugUtilsMessengerEXT(this.debug_messenger, null);
    }

    vki.destroySurfaceKHR(this.surface, null);
    vki.destroyInstance(null);
}

fn createInstance(this: *@This()) !void {
    const vkb = this.system.vkb;

    if (enable_validation_layers and !try this.checkValidationLayerSupport()) {
        return error.vulkanValidationLayersUnavailable;
    }

    const app_info = vk.ApplicationInfo{
        .p_application_name = "v10 app name",
        .application_version = @bitCast(vk.makeApiVersion(0, 0, 1, 0)),
        .p_engine_name = "v10",
        .engine_version = @bitCast(vk.makeApiVersion(0, 0, 1, 0)),
        .api_version = @bitCast(vk.features.version_1_0.version),
    };

    const extensions = try this.getRequiredExtensions(alloc.gpa);
    defer alloc.gpa.free(extensions);

    vklog.debug("required_extensions: {}", .{extensions.len});
    for (extensions, 0..) |r_ext, i| {
        vklog.debug("required_extensions[{}]: {s}", .{ i, r_ext });
    }

    if (!try this.hasGlfwRequiredInstanceExtensions(extensions, alloc.gpa)) {
        return error.requirdExtensionUnavailable;
    }

    var debug_create_info: vk.DebugUtilsMessengerCreateInfoEXT = if (enable_validation_layers) debug_messenger_create_info else undefined;

    const create_info = vk.InstanceCreateInfo{
        .p_application_info = &app_info,
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
        .enabled_layer_count = if (enable_validation_layers) validation_layers.len else 0,
        .pp_enabled_layer_names = if (enable_validation_layers) @ptrCast(@alignCast(&validation_layers)) else null,
        .p_next = if (enable_validation_layers) &debug_create_info else null,
    };

    const instance = try vkb.createInstance(&create_info, null);
    this.system.vki = vk.InstanceWrapper.load(instance, vkb.dispatch.vkGetInstanceProcAddr.?);
    this.vki = vk.InstanceProxy.init(instance, &this.system.vki);
    vklog.debug("Instance created", .{});
    if (enable_validation_layers) vklog.debug("validation layers enabled", .{});
}

fn setupDebugMessenger(this: *@This()) !void {
    if (!enable_validation_layers) return;

    const create_info = debug_messenger_create_info;
    this.debug_messenger = try this.vki.createDebugUtilsMessengerEXT(&create_info, null);
}

fn createSurface(this: *@This()) !void {
    try this.window.createWindowSurface(this.vki.handle, &this.surface);
    vklog.debug("Surface created", .{});
}

fn pickPhysicalDevice(this: *@This(), allocator: Allocator) !void {
    var device_count: u32 = undefined;
    if (try this.vki.enumeratePhysicalDevices(&device_count, null) != .success) {
        return error.vkEnumeratePhysicalDevicesFailed;
    }

    if (device_count == 0) {
        return error.noGPUWithVulkanSupportFound;
    }

    vklog.debug("{} physical devices found", .{device_count});

    const devices = try allocator.alloc(vk.PhysicalDevice, device_count);
    defer allocator.free(devices);

    if (try this.vki.enumeratePhysicalDevices(&device_count, devices.ptr) != .success) {
        return error.vkEnumeratePhysicalDevicesFailed;
    }

    var device_index: i64 = -1;
    for (devices, 0..) |pdev, i| {
        const properties = this.vki.getPhysicalDeviceProperties(pdev);
        vklog.debug("devices[{}]: {s}", .{ i, properties.device_name });

        const dev_info = DeviceInfo{
            .physical_device = pdev,
            .properties = properties,
            .queue_family_indices = try this.findQueueFamilies(pdev, allocator),
        };

        if (try this.isDeviceSuitable(dev_info, allocator)) {
            if (device_index < 0) {
                device_index = @intCast(i);
                this.device_info = dev_info;
            }
        }
    }

    if (device_index < 0) {
        return error.NoSuitableGPUFound;
    }

    vklog.debug("using physical device {}", .{device_index});
}

fn createLogicalDevice(this: *@This(), allocator: Allocator) !void {
    const indices = &this.device_info.queue_family_indices;

    const unique_families = try indices.uniqueFamilies(allocator);
    defer allocator.free(unique_families);

    const queue_create_infos = try allocator.alloc(vk.DeviceQueueCreateInfo, unique_families.len);
    defer allocator.free(queue_create_infos);

    const prio = &[_]f32{1};
    for (unique_families, queue_create_infos) |family_index, *qci| {
        qci.* = .{
            .queue_family_index = family_index,
            .queue_count = 1,
            .p_queue_priorities = prio,
        };
    }

    const device_features = vk.PhysicalDeviceFeatures{
        .sampler_anisotropy = vk.TRUE,
    };

    const create_info = vk.DeviceCreateInfo{
        .queue_create_info_count = @intCast(queue_create_infos.len),
        .p_queue_create_infos = queue_create_infos.ptr,
        .p_enabled_features = &device_features,
        .enabled_extension_count = @intCast(device_extensions.len),
        .pp_enabled_extension_names = @ptrCast(&device_extensions),
        .enabled_layer_count = if (enable_validation_layers) validation_layers.len else 0,
        .pp_enabled_layer_names = if (enable_validation_layers) @ptrCast(&validation_layers) else null,
    };

    const device = try this.vki.createDevice(this.device_info.physical_device, &create_info, null);
    this.system.vkd = vk.DeviceWrapper.load(device, this.system.vki.dispatch.vkGetDeviceProcAddr.?);
    this.device = vk.DeviceProxy.init(device, &this.system.vkd);

    const graphics_queue = this.device.getDeviceQueue(indices.graphics_family.?, 0);
    this.graphics_queue = vk.QueueProxy.init(graphics_queue, &this.system.vkd);
    const present_queue = this.device.getDeviceQueue(indices.present_family.?, 0);
    this.present_queue = vk.QueueProxy.init(present_queue, &this.system.vkd);
}

fn createCommandPool(this: *@This()) !void {
    const indices = this.device_info.queue_family_indices;
    const pool_create_info = vk.CommandPoolCreateInfo{
        .queue_family_index = indices.graphics_family.?,
        .flags = .{ .transient_bit = true, .reset_command_buffer_bit = true },
    };

    this.command_pool = try this.device.createCommandPool(&pool_create_info, null);
}

fn checkValidationLayerSupport(this: *@This()) !bool {
    const vkb = this.system.vkb;

    var layer_count: u32 = undefined;
    if (try vkb.enumerateInstanceLayerProperties(&layer_count, null) != .success) {
        return error.vkEnumerateInstanceLayerPropertiesFailed;
    }

    const available_layers = try alloc.gpa.alloc(vk.LayerProperties, layer_count);
    defer alloc.gpa.free(available_layers);

    if (try vkb.enumerateInstanceLayerProperties(&layer_count, available_layers.ptr) != .success) {
        return error.vkEnumerateInstanceLayerPropertiesFailed;
    }

    for (validation_layers) |_required_name| {
        const required_name = std.mem.span(@as([*:0]const u8, _required_name));

        var layer_found = false;
        for (available_layers) |layer_properties| {
            const available_name = std.mem.span(@as([*:0]const u8, @ptrCast(&layer_properties.layer_name)));
            if (std.mem.eql(u8, required_name, available_name)) {
                layer_found = true;
                break;
            }
        }

        if (!layer_found) {
            return false;
        }
    }

    vklog.debug("all requested layers available!", .{});

    return true;
}
fn getRequiredExtensions(this: *const @This(), allocator: Allocator) ![]const [*:0]const u8 {
    _ = this;

    var glfw_extension_count: u32 = undefined;
    const _glfw_extensions = glfw.getRequiredInstanceExtensions(&glfw_extension_count) orelse return error.glfwGetRequiredInstanceExtensionsFailed;
    const glfw_extensions = _glfw_extensions[0..glfw_extension_count];

    vklog.debug("glfw_extensions: {}", .{glfw_extension_count});
    for (glfw_extensions, 0..) |glfw_extension, i| {
        vklog.debug("glfw_extensions[{}]: {s}", .{ i, glfw_extension });
    }

    const required_extension_count = if (enable_validation_layers) 1 + glfw_extension_count else glfw_extension_count;
    const required_extensions = try allocator.alloc([*:0]const u8, required_extension_count);

    for (glfw_extensions, 0..) |glfw_extension, i| {
        required_extensions[i] = glfw_extension;
    }

    if (enable_validation_layers) {
        required_extensions[glfw_extension_count] = vk.extensions.ext_debug_utils.name;
    }

    return required_extensions;
}

fn hasGlfwRequiredInstanceExtensions(this: *@This(), required_exts: []const [*:0]const u8, allocator: Allocator) !bool {
    const vkb = this.system.vkb;

    var extension_count: u32 = undefined;
    if (try vkb.enumerateInstanceExtensionProperties(null, &extension_count, null) != .success) {
        return error.vkEnumerateInstanceExtensionPropertiesFailed;
    }
    vklog.debug("available_extensions: {}", .{extension_count});

    const available_extensions = try allocator.alloc(vk.ExtensionProperties, extension_count);
    defer allocator.free(available_extensions);

    if (try vkb.enumerateInstanceExtensionProperties(null, &extension_count, available_extensions.ptr) != .success) {
        return error.vkEnumerateInstanceExtensionPropertiesFailed;
    }

    for (required_exts) |required| {
        var found: bool = false;
        for (available_extensions) |properties| {
            const available = std.mem.span(@as([*:0]const u8, @ptrCast(&properties.extension_name)));
            if (std.mem.eql(u8, available, std.mem.span(required))) {
                found = true;
                break;
            }
        }

        if (!found) {
            vklog.err("Required extension '{s}' unavailable", .{required});
            return false;
        }
    }
    return true;
}

fn isDeviceSuitable(this: *@This(), dev_info: DeviceInfo, allocator: Allocator) !bool {
    if (!dev_info.queue_family_indices.isComplete()) return false;

    if (!try this.checkDeviceExtensionSupport(dev_info.physical_device, allocator)) return false;

    const swapchain_support = try this.querySwapchainSupport(dev_info.physical_device, allocator);
    defer swapchain_support.free(allocator);
    if (swapchain_support.formats.len == 0 or
        swapchain_support.present_modes.len == 0) return false;

    const supported_features = this.vki.getPhysicalDeviceFeatures(dev_info.physical_device);
    if (supported_features.sampler_anisotropy == 0) return false;

    return true;
}

fn findQueueFamilies(this: *@This(), device: vk.PhysicalDevice, allocator: Allocator) !QueueFamilyIndices {
    var result = QueueFamilyIndices{};

    var family_count: u32 = 0;
    this.vki.getPhysicalDeviceQueueFamilyProperties(device, &family_count, null);
    vklog.debug("Queue family count: {}", .{family_count});

    const family_properties = try allocator.alloc(vk.QueueFamilyProperties, family_count);
    defer allocator.free(family_properties);
    this.vki.getPhysicalDeviceQueueFamilyProperties(device, &family_count, family_properties.ptr);

    for (family_properties, 0..) |fprops, i| {
        if (fprops.queue_count > 0 and fprops.queue_flags.graphics_bit) {
            result.graphics_family = @intCast(i);
        }

        const present_support = try this.vki.getPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), this.surface);
        if (fprops.queue_count > 0 and present_support == vk.TRUE) {
            result.present_family = @intCast(i);
        }

        if (result.isComplete()) break;
    }

    return result;
}

fn checkDeviceExtensionSupport(this: *@This(), device: vk.PhysicalDevice, allocator: Allocator) !bool {
    var extension_count: u32 = 0;
    if (try this.vki.enumerateDeviceExtensionProperties(device, null, &extension_count, null) != .success) {
        return error.vkEnumerateDeviceExtensionPropertiesFailed;
    }
    vklog.debug("Device has {} extensions", .{extension_count});

    const available_extensions = try allocator.alloc(vk.ExtensionProperties, extension_count);
    defer allocator.free(available_extensions);
    if (try this.vki.enumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.ptr) != .success) {
        return error.vkEnumerateDeviceExtensionPropertiesFailed;
    }

    for (device_extensions) |device_extension| {
        var found = false;

        for (available_extensions) |available_ext| {
            const available_name = std.mem.span(@as([*:0]const u8, @ptrCast(&available_ext.extension_name)));
            if (std.mem.eql(u8, std.mem.span(device_extension), available_name)) {
                found = true;
                break;
            }
        }

        if (!found) {
            vklog.err("Required device extension unavailable: '{s}'", .{device_extension});
            return error.RequiredDeviceExtensionNotAvailable;
        }
    }

    vklog.debug("All required device extensions available", .{});
    return true;
}

pub fn querySwapchainSupport(this: *@This(), device: vk.PhysicalDevice, allocator: Allocator) !SwapchainSupportDetails {
    const capabilities = try this.vki.getPhysicalDeviceSurfaceCapabilitiesKHR(device, this.surface);

    var format_count: u32 = 0;
    var formats: []vk.SurfaceFormatKHR = &.{};

    if (try this.vki.getPhysicalDeviceSurfaceFormatsKHR(device, this.surface, &format_count, null) != .success) {
        return error.vkGetPhysicalDeviceSurfaceFormatsKHRFailed;
    }

    if (format_count != 0) {
        formats = try allocator.alloc(vk.SurfaceFormatKHR, format_count);

        if (try this.vki.getPhysicalDeviceSurfaceFormatsKHR(device, this.surface, &format_count, formats.ptr) != .success) {
            return error.vkGetPhysicalDeviceSurfaceFormatsKHRFailed;
        }
    }

    var present_mode_count: u32 = 0;
    var present_modes: []vk.PresentModeKHR = &.{};

    if (try this.vki.getPhysicalDeviceSurfacePresentModesKHR(device, this.surface, &present_mode_count, null) != .success) {
        return error.vkGetPhysicalDeviceSurfacePresentModesKHRFailed;
    }

    if (present_mode_count != 0) {
        present_modes = try allocator.alloc(vk.PresentModeKHR, present_mode_count);

        if (try this.vki.getPhysicalDeviceSurfacePresentModesKHR(device, this.surface, &present_mode_count, present_modes.ptr) != .success) {
            return error.vkGetPhysicalDeviceSurfacePresentModesKHRFailed;
        }
    }

    return .{
        .capabilities = capabilities,
        .formats = formats,
        .present_modes = present_modes,
    };
}

pub fn debugCallback(message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, message_type: vk.DebugUtilsMessageTypeFlagsEXT, p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, p_user_data: ?*anyopaque) callconv(vk.vulkan_call_conv) vk.Bool32 {
    _ = message_type;
    _ = p_user_data;

    const fmt = "validation layer: {s}";
    const args = .{p_callback_data.?.p_message.?};

    if (message_severity.error_bit_ext) {
        vklog.err(fmt, args);
    } else if (message_severity.warning_bit_ext) {
        vklog.warn(fmt, args);
    } else if (message_severity.verbose_bit_ext) {
        vklog.debug(fmt, args);
    } else if (message_severity.info_bit_ext) {
        vklog.info(fmt, args);
    } else {
        vklog.err(fmt, args);
    }

    return vk.FALSE;
}
