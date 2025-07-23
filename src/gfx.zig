const glfw = @import("glfw");

pub const vk = @import("vulkan");

pub const Device = @import("gfx/device.zig");
pub const Pipeline = @import("gfx/pipeline.zig");
pub const Swapchain = @import("gfx/swapchain.zig");
pub const Renderer = @import("gfx/renderer.zig");
pub const GpuModel = @import("gfx/gpu_model.zig");
pub const Camera = @import("gfx/camera.zig");
pub const SimpleRenderSystem = @import("gfx/simple_render_system.zig");

pub var system: System = undefined;
pub const System = struct {
    vkb: vk.BaseWrapper,
    vki: vk.InstanceWrapper,
    vkd: vk.DeviceWrapper,

    pub fn init() !void {
        const FnType = *const fn (vk.Instance, [*:0]const u8) callconv(vk.vulkan_call_conv) vk.PfnVoidFunction;
        system = .{
            .vkb = vk.BaseWrapper.load(@as(FnType, @ptrCast(glfw.getInstanceProcAddress))),
            .vki = undefined,
            .vkd = undefined,
        };
    }
};
