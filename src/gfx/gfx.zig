const glfw = @import("glfw");

pub const vk = @import("vulkan");

pub const Device = @import("device.zig");
pub const Pipeline = @import("pipeline.zig");
pub const Swapchain = @import("swapchain.zig");

pub var system: System = undefined;
pub const System = struct {
    vkb: vk.BaseWrapper,
    vki: vk.InstanceWrapper,
    vkd: vk.DeviceWrapper,

    pub fn init() !void {
        system = .{
            .vkb = vk.BaseWrapper.load(glfw.getInstanceProcAddress),
            .vki = undefined,
            .vkd = undefined,
        };
    }
};
