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
    name: []const u8,
    physical_device: vk.PhysicalDevice,
    properties: vk.PhysicalDeviceProperties,
    queue_family_indices: QueueFamilyIndices,
    swapchain_support: SwapchainSupportDetails,

    pub fn copy(this: *const @This(), allocator: Allocator) !@This() {
        var result: @This() = undefined;
        result.name = try allocator.alloc(u8, this.name.len);
        @memcpy(@constCast(result.name), this.name);
        result.physical_device = this.physical_device;
        result.properties = this.properties;
        result.queue_family_indices = this.queue_family_indices;
        result.swapchain_support = try this.swapchain_support.copy(allocator);
        return result;
    }

    pub fn destroy(this: *@This(), allocator: Allocator) void {
        allocator.destroy(this);
        allocator.free(this.name);
        this.swapchain_support.destroy(allocator);
    }
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

    pub fn copy(this: *const @This(), allocator: Allocator) !@This() {
        var result: @This() = undefined;
        result.capabilities = this.capabilities;
        result.formats = try allocator.alloc(vk.SurfaceFormatKHR, this.formats.len);
        @memcpy(result.formats, this.formats);
        result.present_modes = try allocator.alloc(vk.PresentModeKHR, this.present_modes.len);
        @memcpy(result.present_modes, this.present_modes);
        return result;
    }

    pub fn destroy(this: @This(), allocator: Allocator) void {
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
    try this.pickPhysicalDevice();
    try this.createLogicalDevice();
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

    const ta = alloc.temp_arena_data.allocator();
    defer _ = alloc.temp_arena_data.reset(.retain_capacity);

    if (enable_validation_layers and !try this.checkValidationLayerSupport(ta)) {
        return error.vulkanValidationLayersUnavailable;
    }

    const app_info = vk.ApplicationInfo{
        .p_application_name = "v10 app name",
        .application_version = @bitCast(vk.makeApiVersion(0, 0, 1, 0)),
        .p_engine_name = "v10",
        .engine_version = @bitCast(vk.makeApiVersion(0, 0, 1, 0)),
        .api_version = @bitCast(vk.features.version_1_0.version),
    };

    const extensions = try this.getRequiredExtensions(ta);

    vklog.debug("required_extensions: {}", .{extensions.len});
    for (extensions, 0..) |r_ext, i| {
        vklog.debug("required_extensions[{}]: {s}", .{ i, r_ext });
    }

    if (!try this.hasGlfwRequiredInstanceExtensions(extensions, ta)) {
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

fn pickPhysicalDevice(this: *@This()) !void {
    var device_count: u32 = undefined;
    if (try this.vki.enumeratePhysicalDevices(&device_count, null) != .success) {
        return error.vkEnumeratePhysicalDevicesFailed;
    }

    if (device_count == 0) {
        return error.noGPUWithVulkanSupportFound;
    }

    vklog.debug("{} physical devices found", .{device_count});

    const ta = alloc.temp_arena_data.allocator();
    defer _ = alloc.temp_arena_data.reset(.retain_capacity);

    const ga = alloc.gfx_arena_data.allocator();

    const devices = try ta.alloc(vk.PhysicalDevice, device_count);

    if (try this.vki.enumeratePhysicalDevices(&device_count, devices.ptr) != .success) {
        return error.vkEnumeratePhysicalDevicesFailed;
    }

    var device_index: i64 = -1;
    for (devices, 0..) |pdev, i| {
        const properties = this.vki.getPhysicalDeviceProperties(pdev);
        const name = std.mem.span(@as([*:0]const u8, @ptrCast(&properties.device_name)));

        vklog.debug("devices[{}]: '{s}'", .{ i, name });

        const dev_info = DeviceInfo{
            .name = name,
            .physical_device = pdev,
            .properties = properties,
            .queue_family_indices = try this.findQueueFamilies(pdev, ta),
            .swapchain_support = try this.querySwapchainSupport(pdev, ta),
        };

        var chosen = false;
        if (try this.isDeviceSuitable(dev_info, ta)) {
            if (device_index < 0) {
                device_index = @intCast(i);
                this.device_info = try dev_info.copy(ga);
                chosen = true;
            }
        }
    }

    if (device_index < 0) {
        return error.NoSuitableGPUFound;
    }

    vklog.info("Using physical device {} ('{s}')", .{ device_index, this.device_info.name });
}

fn createLogicalDevice(this: *@This()) !void {
    const indices = &this.device_info.queue_family_indices;

    const ta = alloc.temp_arena_data.allocator();
    defer _ = alloc.temp_arena_data.reset(.retain_capacity);

    const unique_families = try indices.uniqueFamilies(ta);
    const queue_create_infos = try ta.alloc(vk.DeviceQueueCreateInfo, unique_families.len);

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

fn checkValidationLayerSupport(this: *@This(), allocator: Allocator) !bool {
    const vkb = this.system.vkb;

    var layer_count: u32 = undefined;
    if (try vkb.enumerateInstanceLayerProperties(&layer_count, null) != .success) {
        return error.vkEnumerateInstanceLayerPropertiesFailed;
    }

    const available_layers = try allocator.alloc(vk.LayerProperties, layer_count);
    defer allocator.free(available_layers);

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

    if (dev_info.swapchain_support.formats.len == 0 or
        dev_info.swapchain_support.present_modes.len == 0) return false;

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

pub fn findSupportedFormat(this: *@This(), candidates: []const vk.Format, tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) !vk.Format {
    for (candidates) |format| {
        const props = this.vki.getPhysicalDeviceFormatProperties(this.device_info.physical_device, format);

        if (tiling == .linear and (props.linear_tiling_features.contains(features))) {
            return format;
        } else if (tiling == .optimal and (props.optimal_tiling_features.contains(features))) {
            return format;
        }
    }

    return error.findSupportedFormatFailed;
}

pub fn createImageWithInfo(this: *@This(), image_info: *const vk.ImageCreateInfo, properties: vk.MemoryPropertyFlags, memory: *vk.DeviceMemory) !vk.Image {
    const result = try this.device.createImage(image_info, null);
    const mem_req = this.device.getImageMemoryRequirements(result);

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_req.size,
        .memory_type_index = try this.findMemoryType(mem_req.memory_type_bits, properties),
    };

    memory.* = try this.device.allocateMemory(&alloc_info, null);
    try this.device.bindImageMemory(result, memory.*, 0);

    return result;
}

pub fn findMemoryType(this: *@This(), type_filter: u32, properties: vk.MemoryPropertyFlags) !u32 {
    const props = this.vki.getPhysicalDeviceMemoryProperties(this.device_info.physical_device);
    for (0..props.memory_type_count) |i| {
        if ((type_filter & (@as(@TypeOf(i), 1) << @intCast(i)) != 0) and props.memory_types[i].property_flags.contains(properties)) {
            return @intCast(i);
        }
    }

    return error.NoSuitableMemoryTypeFound;
}
