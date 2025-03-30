const glfw = @import("glfw");

pub const vk = @import("vulkan");

pub const Device = @import("Device.zig");
pub const Pipeline = @import("Pipeline.zig");

pub var system: System = undefined;
pub const System = struct {
    vkb: vk.BaseWrapper,

    pub fn init() !void {
        system = .{
            .vkb = vk.BaseWrapper.load(glfw.getInstanceProcAddress),
        };
    }
};
