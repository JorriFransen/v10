const gfx = @import("gfx.zig");
const vk = @import("vulkan");

device: *gfx.Device,
graphics_pipeline: vk.Pipeline,
vert_shader_module: vk.ShaderModule,
frag_shader_module: vk.ShaderModule,

pub const ConfigInfo = struct {
    device: *gfx.Device,

    pub fn default(width: u32, height: u32) @This() {
        _ = width;
        _ = height;
        return .{};
    }
};

pub fn create(config: ConfigInfo) @This() {
    return .{
        .device = config.device,
        .graphics_pipeline = .null_handle,
        .vert_shader_module = .null_handle,
        .frag_shader_module = .null_handle,
    };
}

pub fn destroy(this: @This()) void {
    _ = this;
}

fn createShaderModule(code: []const u8, shader_module: *vk.ShaderModule) void {
    _ = code;
    _ = shader_module;
}
