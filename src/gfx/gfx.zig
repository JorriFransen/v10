const glfw = @import("glfw");

pub const vk = @import("vulkan");

pub const Device = @import("device.zig");
pub const Pipeline = @import("pipeline.zig");

pub var system: System = undefined;
pub const System = struct {
    vkb: vk.BaseWrapper,
    vki: vk.InstanceWrapper,

    pub fn init() !void {
        system = .{
            .vkb = vk.BaseWrapper.load(glfw.getInstanceProcAddress),
            .vki = undefined,
        };
    }
};
