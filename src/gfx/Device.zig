const std = @import("std");
const builtin = @import("builtin");

const vklog = std.log.scoped(.vulkan);

const glfw = @import("glfw");

const alloc = @import("../alloc.zig");

const gfx = @import("gfx.zig");
const vk = gfx.vk;

const Window = @import("../Window.zig");

const enable_validation_layers: bool = builtin.mode == .Debug;
const validation_layers = [_][:0]const u8{"VK_LAYER_KHRONOS_validation"};

system: *gfx.System,
window: *const Window,
instance: vk.Instance,

pub fn create(system: *gfx.System, window: *const Window) !@This() {
    var this = @This(){
        .system = system,
        .window = window,
        .instance = .null_handle,
    };

    try this.createInstance();
    // this.setupDebugMessenger();
    // this.createSurface();
    // this.pickPhysicalDevice();
    // this.createLogicalDevice();
    // this.createCommandPool();

    return this;
}

pub fn destroy(this: *@This()) void {
    _ = this;
}

fn createInstance(this: *@This()) !void {
    const vkb = this.system.vkb;

    if (enable_validation_layers and !try this.checkValidationLayerSupport()) {
        return error.vulkanValidationLayersUnavailable;
    }

    const app_info = vk.ApplicationInfo{
        .p_application_name = "v10 app name",
        .application_version = @bitCast(vk.Version{ .major = 0, .minor = 0, .patch = 0, .variant = 0 }),
        .p_engine_name = "v10",
        .engine_version = @bitCast(vk.Version{ .major = 0, .minor = 0, .patch = 0, .variant = 0 }),
        .api_version = @bitCast(vk.API_VERSION_1_0),
    };

    const extensions = try this.getRequiredExtensions(alloc.gpa);
    defer alloc.gpa.free(extensions);

    var debug_create_info: vk.DebugUtilsMessengerCreateInfoEXT = if (enable_validation_layers) .{
        .message_severity = .{ .warning_bit_ext = true, .error_bit_ext = true },
        .message_type = .{ .general_bit_ext = true, .validation_bit_ext = true, .performance_bit_ext = true },
        .pfn_user_callback = debugCallback,
        .p_user_data = null,
    } else undefined;

    const create_info = vk.InstanceCreateInfo{
        .p_application_info = &app_info,
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
        .enabled_layer_count = if (enable_validation_layers) validation_layers.len else 0,
        .pp_enabled_layer_names = if (enable_validation_layers) @ptrCast(@alignCast(validation_layers[0])) else null,
        .p_next = if (enable_validation_layers) &debug_create_info else null,
    };

    this.instance = try vkb.createInstance(&create_info, null);
}

fn setupDebugMessenger(this: *@This()) !void {
    _ = this;
}

fn createSurface(this: *@This()) !void {
    _ = this;
}

fn pickPhysicalDevice(this: *@This()) !void {
    _ = this;
}

fn createLogicalDevice(this: *@This()) !void {
    _ = this;
}

fn createCommandPool(this: *@This()) !void {
    _ = this;
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

    for (validation_layers) |required_name| {
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

    return true;
}
pub fn getRequiredExtensions(this: *const @This(), allocator: std.mem.Allocator) ![]const [*:0]const u8 {
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

    vklog.debug("required_extensions: {}", .{required_extension_count});
    for (required_extensions, 0..) |r_ext, i| {
        vklog.debug("required_extensions[{}]: {s}", .{ i, r_ext });
    }

    return required_extensions;
}

pub fn debugCallback(message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, message_type: vk.DebugUtilsMessageTypeFlagsEXT, p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, p_user_data: ?*anyopaque) callconv(vk.vulkan_call_conv) vk.Bool32 {
    _ = message_severity;
    _ = message_type;
    _ = p_user_data;
    vklog.debug("validation layer: {s}", .{p_callback_data.?.p_message.?});
    return vk.FALSE;
}
