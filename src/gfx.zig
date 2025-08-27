const glfw = @import("glfw");
const camera = @import("gfx/camera.zig");

pub const vk = @import("vulkan");

pub const Device = @import("gfx/device.zig");
pub const Pipeline = @import("gfx/pipeline.zig");
pub const Swapchain = @import("gfx/swapchain.zig");
pub const Renderer = @import("gfx/vulkan_renderer.zig");

/// GPU-side model
pub const Model = @import("gfx/model.zig");
/// CPU-side model
pub const Mesh = @import("gfx/mesh.zig");
/// GPU-side texture
pub const Texture = @import("gfx/texture.zig");
/// CPU-side texture
pub const Bitmap = @import("gfx/bitmap.zig");

pub const Sprite = @import("gfx/sprite.zig");
pub const Font = @import("gfx/font.zig");
pub const Camera2D = camera.Camera2D;
pub const Camera3D = camera.Camera3D;
pub const Renderer2D = @import("gfx/2d_renderer.zig");
pub const Renderer3D = @import("gfx/3d_renderer.zig");

pub var vkb: vk.BaseWrapper = undefined;
pub var vki: vk.InstanceWrapper = undefined;
pub var vkd: vk.DeviceWrapper = undefined;

pub var device: Device = .{};

const Window = @import("window.zig");

pub fn init(window: *const Window) !void {
    const FnType = *const fn (vk.Instance, [*:0]const u8) callconv(vk.vulkan_call_conv) vk.PfnVoidFunction;
    vkb = vk.BaseWrapper.load(@as(FnType, @ptrCast(glfw.getInstanceProcAddress)));

    device = try Device.init(window);
}

pub fn deinit() void {
    device.deinit();
}
