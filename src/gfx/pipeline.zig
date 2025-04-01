const std = @import("std");
const vklog = std.log.scoped(.vulkan);

const gfx = @import("gfx.zig");
const vk = @import("vulkan");

const alloc = @import("../alloc.zig");

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

pub fn create(config: ConfigInfo) !@This() {
    var vert_code: [:0]align(4) const u8 = undefined;
    {
        const file = try std.fs.cwd().openFile("shaders/simple.vert.spv", .{});
        defer file.close();
        vert_code = try file.readToEndAllocOptions(alloc.gpa, try file.getEndPos(), null, 4, 0);
    }
    defer alloc.gpa.free(vert_code);
    vklog.debug("vert_code.len: {}", .{vert_code.len});

    var frag_code: [:0]align(4) const u8 = undefined;
    {
        const file = try std.fs.cwd().openFile("shaders/simple.frag.spv", .{});
        defer file.close();
        frag_code = try file.readToEndAllocOptions(alloc.gpa, try file.getEndPos() + 8, null, 4, 0);
    }
    defer alloc.gpa.free(frag_code);
    vklog.debug("frag_code.len: {}", .{frag_code.len});

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
