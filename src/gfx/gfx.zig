const glfw = @import("glfw");

pub const vk = @import("vulkan");
pub const math = @import("../lm.zig");

pub const Device = @import("device.zig");
pub const Pipeline = @import("pipeline.zig");
pub const Swapchain = @import("swapchain.zig");
pub const Model = @import("model.zig");

pub const Vec2 = math.Vec2f32;
pub const Vec3 = math.Vec3f32;
pub const Vec4 = math.Vec4f32;
pub const Mat2 = math.Mat2f32;
pub const Mat3 = math.Mat3f32;
pub const Mat4 = math.Mat4f32;

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
