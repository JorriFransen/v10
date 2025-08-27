const std = @import("std");
const builtin = @import("builtin");
const vklog = std.log.scoped(.vulkan);
const glfw = @import("glfw");
const mem = @import("memory");
const gfx = @import("../gfx.zig");
const vk = gfx.vk;

const Allocator = std.mem.Allocator;
const Window = @import("../window.zig");

const assert = std.debug.assert;

const enable_validation_layers: bool = builtin.mode == .Debug;
const validation_layers = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
const device_extensions = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
    vk.extensions.ext_index_type_uint_8.name,
};

const debug_messenger_create_info = vk.DebugUtilsMessengerCreateInfoEXT{
    .message_severity = .{ .warning_bit_ext = true, .error_bit_ext = true },
    .message_type = .{ .general_bit_ext = true, .validation_bit_ext = true, .performance_bit_ext = true },
    .pfn_user_callback = debugCallback,
    .p_user_data = null,
};

window: *const Window = undefined,
vki: vk.InstanceProxy = undefined,
debug_messenger: vk.DebugUtilsMessengerEXT = .null_handle,
surface: vk.SurfaceKHR = .null_handle,
device_info: DeviceInfo = undefined,
device: vk.DeviceProxy = undefined,
graphics_queue: vk.QueueProxy = undefined,
present_queue: vk.QueueProxy = undefined,
command_pool: vk.CommandPool = .null_handle,

// TODO: Move this to renderer?
descriptor_pool: vk.DescriptorPool = .null_handle,

linear_sampler: vk.Sampler = .null_handle,
nearest_sampler: vk.Sampler = .null_handle,
texture_sampler_set_layout: vk.DescriptorSetLayout = .null_handle,

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

    pub fn deinit(this: *@This(), allocator: Allocator) void {
        allocator.destroy(this);
        allocator.free(this.name);
        this.swapchain_support.deinit(allocator);
    }
};

pub const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,
    present_family: ?u32 = null,

    pub fn isComplete(this: @This()) bool {
        return this.graphics_family != null and this.present_family != null;
    }

    pub fn uniqueFamilies(this: @This(), allocator: Allocator) ![]u32 {
        assert(this.isComplete());

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

    pub fn deinit(this: @This(), allocator: Allocator) void {
        if (this.formats.len > 0) allocator.free(this.formats);
        if (this.present_modes.len > 0) allocator.free(this.present_modes);
    }
};

pub fn init(window: *const Window) !@This() {
    var this = @This(){
        .window = window,
    };

    try this.createInstance();
    try this.setupDebugMessenger();
    try this.createSurface();
    try this.pickPhysicalDevice();

    const l = this.device_info.properties.limits;
    // TODO: Do something with this! (assert or clamp?/warn);
    vklog.debug("min,max line width: {},{}", .{ l.line_width_range[0], l.line_width_range[1] });

    try this.createLogicalDevice();
    try this.createCommandPool();

    try this.createSamplerDescriptorSetLayout();
    this.linear_sampler = try this.createSampler(.linear);
    this.nearest_sampler = try this.createSampler(.nearest);
    try this.createDescriptorPool();

    return this;
}

pub fn deinit(this: *@This()) void {
    const device = this.device;
    const vki = this.vki;

    device.destroyDescriptorSetLayout(this.texture_sampler_set_layout, null);
    device.destroySampler(this.linear_sampler, null);
    device.destroySampler(this.nearest_sampler, null);
    device.destroyDescriptorPool(this.descriptor_pool, null);

    device.destroyCommandPool(this.command_pool, null);
    device.destroyDevice(null);

    if (enable_validation_layers) {
        vki.destroyDebugUtilsMessengerEXT(this.debug_messenger, null);
    }

    vki.destroySurfaceKHR(this.surface, null);
    vki.destroyInstance(null);
}

fn createInstance(this: *@This()) !void {
    const vkb = gfx.vkb;

    if (enable_validation_layers and !try checkValidationLayerSupport()) {
        return error.vulkanValidationLayersUnavailable;
    }

    const app_info = vk.ApplicationInfo{
        .p_application_name = "v10 app name",
        .application_version = @bitCast(vk.makeApiVersion(0, 0, 1, 0)),
        .p_engine_name = "v10",
        .engine_version = @bitCast(vk.makeApiVersion(0, 0, 1, 0)),
        .api_version = @bitCast(vk.features.version_1_2.version),
    };

    var tmp = mem.get_temp();
    defer tmp.release();

    const extensions = try this.getRequiredExtensions(tmp.allocator());

    vklog.debug("required_extensions: {}", .{extensions.len});
    for (extensions, 0..) |r_ext, i| {
        vklog.debug("required_extensions[{}]: {s}", .{ i, r_ext });
    }

    if (!try hasGlfwRequiredInstanceExtensions(extensions)) {
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
    gfx.vki = vk.InstanceWrapper.load(instance, vkb.dispatch.vkGetInstanceProcAddr.?);
    this.vki = vk.InstanceProxy.init(instance, &gfx.vki);
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

    var tmp = mem.get_temp();
    defer tmp.release();

    const devices = try tmp.allocator().alloc(vk.PhysicalDevice, device_count);

    if (try this.vki.enumeratePhysicalDevices(&device_count, devices.ptr) != .success) {
        return error.vkEnumeratePhysicalDevicesFailed;
    }

    var device_index: i64 = -1;
    var high_score: i64 = -1;

    for (devices, 0..) |pdev, i| {
        const properties = this.vki.getPhysicalDeviceProperties(pdev);
        const name = std.mem.span(@as([*:0]const u8, @ptrCast(&properties.device_name)));

        vklog.debug("devices[{}]: '{s}'", .{ i, name });

        const dev_info = DeviceInfo{
            .name = name,
            .physical_device = pdev,
            .properties = properties,
            .queue_family_indices = try this.findQueueFamilies(pdev),
            .swapchain_support = try this.querySwapchainSupport(pdev, tmp.allocator()),
        };

        if (try this.isDeviceSuitable(dev_info)) {
            var score: i64 = 0;
            score += switch (dev_info.properties.device_type) {
                .discrete_gpu => 5,
                .integrated_gpu => 4,
                .virtual_gpu => 3,
                .other, .cpu => 2,
                else => 1,
            };

            if (score > high_score) {
                high_score = score;
                device_index = @intCast(i);
                this.device_info = try dev_info.copy(mem.persistent_arena.allocator());
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

    var tmp = mem.get_temp();
    defer tmp.release();

    const unique_families = try indices.uniqueFamilies(tmp.allocator());
    const queue_create_infos = try tmp.allocator().alloc(vk.DeviceQueueCreateInfo, unique_families.len);

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
        .wide_lines = vk.TRUE,
    };

    const index_type_uint8_features = vk.PhysicalDeviceIndexTypeUint8FeaturesKHR{
        .index_type_uint_8 = vk.TRUE,
    };

    const create_info = vk.DeviceCreateInfo{
        .queue_create_info_count = @intCast(queue_create_infos.len),
        .p_queue_create_infos = queue_create_infos.ptr,
        .p_enabled_features = &device_features,
        .enabled_extension_count = @intCast(device_extensions.len),
        .pp_enabled_extension_names = @ptrCast(&device_extensions),
        .enabled_layer_count = if (enable_validation_layers) validation_layers.len else 0,
        .pp_enabled_layer_names = if (enable_validation_layers) @ptrCast(&validation_layers) else null,
        .p_next = &index_type_uint8_features,
    };

    const device = try this.vki.createDevice(this.device_info.physical_device, &create_info, null);
    gfx.vkd = vk.DeviceWrapper.load(device, gfx.vki.dispatch.vkGetDeviceProcAddr.?);
    this.device = vk.DeviceProxy.init(device, &gfx.vkd);

    const graphics_queue = this.device.getDeviceQueue(indices.graphics_family.?, 0);
    this.graphics_queue = vk.QueueProxy.init(graphics_queue, &gfx.vkd);
    const present_queue = this.device.getDeviceQueue(indices.present_family.?, 0);
    this.present_queue = vk.QueueProxy.init(present_queue, &gfx.vkd);
}

fn createCommandPool(this: *@This()) !void {
    const indices = this.device_info.queue_family_indices;
    const pool_create_info = vk.CommandPoolCreateInfo{
        .queue_family_index = indices.graphics_family.?,
        .flags = .{ .transient_bit = true, .reset_command_buffer_bit = true },
    };

    this.command_pool = try this.device.createCommandPool(&pool_create_info, null);
}

fn createSamplerDescriptorSetLayout(this: *@This()) !void {
    const sampler_layout_binding = vk.DescriptorSetLayoutBinding{
        .binding = 0,
        .descriptor_count = 1,
        .descriptor_type = .combined_image_sampler,
        .p_immutable_samplers = null,
        .stage_flags = .{ .fragment_bit = true },
    };

    const layout_info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = 1,
        .p_bindings = @ptrCast(&sampler_layout_binding),
    };

    this.texture_sampler_set_layout = try this.device.createDescriptorSetLayout(&layout_info, null);
}

const CreateTextureSamplerError = vk.DeviceProxy.CreateSamplerError;

fn createSampler(this: *@This(), filter: gfx.Texture.Filter) CreateTextureSamplerError!vk.Sampler {
    const filter_mode: vk.Filter = switch (filter) {
        .nearest => .nearest,
        .linear => .linear,
    };

    const mipmap_mode: vk.SamplerMipmapMode = switch (filter) {
        .nearest => .nearest,
        .linear => .linear,
    };

    const sampler_info = vk.SamplerCreateInfo{
        .mag_filter = filter_mode,
        .min_filter = filter_mode,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .anisotropy_enable = vk.TRUE,
        .max_anisotropy = this.device_info.properties.limits.max_sampler_anisotropy,
        .border_color = .int_opaque_black,
        .unnormalized_coordinates = vk.FALSE,
        .compare_enable = vk.FALSE,
        .compare_op = .always,
        .mipmap_mode = mipmap_mode,
        .mip_lod_bias = 0,
        .min_lod = 0,
        .max_lod = 0,
    };
    return try this.device.createSampler(&sampler_info, null);
}

const CreateDescriptorPoolError = vk.DeviceProxy.CreateDescriptorPoolError;
fn createDescriptorPool(this: *@This()) CreateDescriptorPoolError!void {
    const pool_sizes = [_]vk.DescriptorPoolSize{.{
        .type = .combined_image_sampler,
        .descriptor_count = 128,
    }};

    const pool_info = vk.DescriptorPoolCreateInfo{
        .pool_size_count = @intCast(pool_sizes.len),
        .p_pool_sizes = &pool_sizes,
        .max_sets = 128,
    };

    this.descriptor_pool = try this.device.createDescriptorPool(&pool_info, null);
}

fn checkValidationLayerSupport() !bool {
    const vkb = gfx.vkb;

    var layer_count: u32 = undefined;
    if (try vkb.enumerateInstanceLayerProperties(&layer_count, null) != .success) {
        return error.vkEnumerateInstanceLayerPropertiesFailed;
    }

    var tmp = mem.get_temp();
    defer tmp.release();

    const available_layers = try tmp.allocator().alloc(vk.LayerProperties, layer_count);

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

fn hasGlfwRequiredInstanceExtensions(required_exts: []const [*:0]const u8) !bool {
    const vkb = gfx.vkb;

    var extension_count: u32 = undefined;
    if (try vkb.enumerateInstanceExtensionProperties(null, &extension_count, null) != .success) {
        return error.vkEnumerateInstanceExtensionPropertiesFailed;
    }
    vklog.debug("available_extensions: {}", .{extension_count});

    var tmp = mem.get_temp();
    defer tmp.release();

    const available_extensions = try tmp.allocator().alloc(vk.ExtensionProperties, extension_count);

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

fn isDeviceSuitable(this: *@This(), dev_info: DeviceInfo) !bool {
    if (!dev_info.queue_family_indices.isComplete()) return false;

    if (!try this.checkDeviceExtensionSupport(dev_info.physical_device)) return false;

    if (dev_info.swapchain_support.formats.len == 0 or
        dev_info.swapchain_support.present_modes.len == 0) return false;

    const supported_features = this.vki.getPhysicalDeviceFeatures(dev_info.physical_device);
    if (supported_features.sampler_anisotropy == 0) return false;
    if (supported_features.wide_lines == 0) return false;

    return true;
}

fn findQueueFamilies(this: *@This(), device: vk.PhysicalDevice) !QueueFamilyIndices {
    var result = QueueFamilyIndices{};

    var family_count: u32 = 0;
    this.vki.getPhysicalDeviceQueueFamilyProperties(device, &family_count, null);
    vklog.debug("Queue family count: {}", .{family_count});

    var tmp = mem.get_temp();
    defer tmp.release();

    const family_properties = try tmp.allocator().alloc(vk.QueueFamilyProperties, family_count);

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

fn checkDeviceExtensionSupport(this: *@This(), device: vk.PhysicalDevice) !bool {
    var extension_count: u32 = 0;
    if (try this.vki.enumerateDeviceExtensionProperties(device, null, &extension_count, null) != .success) {
        return error.vkEnumerateDeviceExtensionPropertiesFailed;
    }
    vklog.debug("Device has {} extensions", .{extension_count});

    var tmp = mem.get_temp();
    defer tmp.release();

    const available_extensions = try tmp.allocator().alloc(vk.ExtensionProperties, extension_count);

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
        // assert(false);
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

pub const CreateImageError = error{} ||
    vk.DeviceProxy.CreateImageError ||
    vk.DeviceProxy.AllocateMemoryError;

pub fn createImageWithInfo(this: *@This(), image_info: *const vk.ImageCreateInfo, properties: vk.MemoryPropertyFlags, memory: *vk.DeviceMemory) CreateImageError!vk.Image {
    const result = try this.device.createImage(image_info, null);
    const mem_req = this.device.getImageMemoryRequirements(result);

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_req.size,
        .memory_type_index = this.findMemoryType(mem_req.memory_type_bits, properties),
    };

    memory.* = try this.device.allocateMemory(&alloc_info, null);
    try this.device.bindImageMemory(result, memory.*, 0);

    return result;
}

pub const CreateImageViewError = vk.DeviceWrapper.CreateImageViewError;

pub fn createImageView(this: *@This(), image: vk.Image, format: vk.Format) CreateImageViewError!vk.ImageView {
    const view_info = vk.ImageViewCreateInfo{
        .image = image,
        .view_type = .@"2d",
        .format = format,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
    };

    return this.device.createImageView(&view_info, null);
}

pub fn findMemoryType(this: *@This(), type_filter: u32, properties: vk.MemoryPropertyFlags) u32 {
    const props = this.vki.getPhysicalDeviceMemoryProperties(this.device_info.physical_device);
    for (0..props.memory_type_count) |i| {
        if ((type_filter & (@as(@TypeOf(i), 1) << @intCast(i)) != 0) and props.memory_types[i].property_flags.contains(properties)) {
            return @intCast(i);
        }
    }

    @panic("No suitable memory type found");
}

pub const CreateBufferError = error{} ||
    vk.DeviceProxy.CreateBufferError ||
    vk.DeviceProxy.AllocateMemoryError;

pub fn createBuffer(this: *@This(), size: vk.DeviceSize, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags, memory: *vk.DeviceMemory) CreateBufferError!vk.Buffer {
    const buffer_info = vk.BufferCreateInfo{
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
    };

    const buffer = try this.device.createBuffer(&buffer_info, null);
    const mem_req = this.device.getBufferMemoryRequirements(buffer);

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_req.size,
        .memory_type_index = this.findMemoryType(mem_req.memory_type_bits, properties),
    };

    memory.* = try this.device.allocateMemory(&alloc_info, null);
    try this.device.bindBufferMemory(buffer, memory.*, 0);

    return buffer;
}

pub fn copyBuffer(_: *@This(), cb: vk.CommandBufferProxy, src: vk.Buffer, dst: vk.Buffer, size: vk.DeviceSize) void {
    assert(size > 0);

    const copy_region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };

    cb.copyBuffer(src, dst, 1, @ptrCast(&copy_region));
}

pub fn transitionImageLayout(_: *@This(), cb: vk.CommandBufferProxy, image: vk.Image, format: vk.Format, old_layout: vk.ImageLayout, new_layout: vk.ImageLayout) void {
    const opts: struct {
        src_access_mask: vk.AccessFlags,
        dst_access_mask: vk.AccessFlags,
        src_stage: vk.PipelineStageFlags,
        dst_stage: vk.PipelineStageFlags,
    } = if (old_layout == .undefined and new_layout == .transfer_dst_optimal) .{
        .src_access_mask = .{},
        .dst_access_mask = .{ .transfer_write_bit = true },
        .src_stage = .{ .top_of_pipe_bit = true },
        .dst_stage = .{ .transfer_bit = true },
    } else if (old_layout == .transfer_dst_optimal and new_layout == .shader_read_only_optimal) .{
        .src_access_mask = .{ .transfer_write_bit = true },
        .dst_access_mask = .{ .shader_read_bit = true },
        .src_stage = .{ .transfer_bit = true },
        .dst_stage = .{ .fragment_shader_bit = true },
    } else {
        @panic("Invalid image transition");
    };

    const barrier = vk.ImageMemoryBarrier{
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .src_access_mask = opts.src_access_mask,
        .dst_access_mask = opts.dst_access_mask,
    };

    cb.pipelineBarrier(opts.src_stage, opts.dst_stage, .{}, 0, null, 0, null, 1, @ptrCast(&barrier));
    _ = format;
}

pub fn copyBufferToImage(_: *@This(), cb: vk.CommandBufferProxy, buffer: vk.Buffer, image: vk.Image, width: u32, height: u32) void {
    const region = vk.BufferImageCopy{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_extent = .{ .width = width, .height = height, .depth = 1 },
    };

    cb.copyBufferToImage(buffer, image, .transfer_dst_optimal, 1, @ptrCast(&region));
}

pub fn beginSingleTimeCommands(this: *@This()) vk.CommandBufferProxy {
    const alloc_info = vk.CommandBufferAllocateInfo{
        .level = .primary,
        .command_pool = this.command_pool,
        .command_buffer_count = 1,
    };

    var command_buffer: vk.CommandBuffer = .null_handle;
    this.device.allocateCommandBuffers(&alloc_info, @ptrCast(&command_buffer)) catch @panic("vkAllocateCommandBuffers failed");

    const proxy = vk.CommandBufferProxy.init(command_buffer, this.device.wrapper);

    const begin_info = vk.CommandBufferBeginInfo{
        .flags = .{ .one_time_submit_bit = true },
    };

    proxy.beginCommandBuffer(&begin_info) catch @panic("vkBeginCommandBuffer failed");

    return proxy;
}

pub fn endSingleTimeCommands(this: *@This(), command_buffer: vk.CommandBufferProxy) void {
    command_buffer.endCommandBuffer() catch @panic("vkEndCommandBuffer failed");

    const handle = command_buffer.handle;
    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&handle),
    };

    this.graphics_queue.submit(1, @ptrCast(&submit_info), .null_handle) catch @panic("vkQueueSubmit failed");
    this.graphics_queue.waitIdle() catch @panic("vkQueueWaitIdle failed");

    this.device.freeCommandBuffers(this.command_pool, 1, @ptrCast(&handle));
}
