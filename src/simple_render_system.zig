const std = @import("std");
const gfx = @import("gfx/gfx.zig");
const vk = @import("vulkan");
const math = @import("math");

const Device = gfx.Device;
const Pipeline = gfx.Pipeline;
const Entity = @import("entity.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

device: *Device,
layout: vk.PipelineLayout,
pipeline: Pipeline,

const PushConstantData = extern struct {
    transform: Mat4,
    offset: Vec3 align(8),
    color: Vec3 align(16),
};

pub fn init(this: *@This(), device: *Device, render_pass: vk.RenderPass) !void {
    this.device = device;

    this.layout = try this.createPipelineLayout();
    this.pipeline = try this.createPipeline(render_pass);
}

pub fn destroy(this: *@This()) void {
    this.device.device.destroyPipelineLayout(this.layout, null);
    this.pipeline.destroy();
}

fn createPipeline(this: *@This(), render_pass: vk.RenderPass) !Pipeline {
    var pipeline_config = Pipeline.ConfigInfo.default();
    pipeline_config.render_pass = render_pass;
    pipeline_config.pipeline_layout = this.layout;

    return try Pipeline.create(this.device, "shaders/simple.vert.spv", "shaders/simple.frag.spv", pipeline_config);
}

fn createPipelineLayout(this: *@This()) !vk.PipelineLayout {
    const push_constant_range = vk.PushConstantRange{
        .offset = 0,
        .size = @sizeOf(PushConstantData),
        .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
    };

    const pipeline_layout_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = 0,
        .p_set_layouts = null,
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    };

    return try this.device.device.createPipelineLayout(&pipeline_layout_info, null);
}

pub fn drawEntities(this: *@This(), cb: *const vk.CommandBufferProxy, entities: []const Entity) void {
    cb.bindPipeline(.graphics, this.pipeline.graphics_pipeline);

    for (entities) |*entity| {
        var pcd = PushConstantData{
            .offset = entity.transform.translation,
            .color = entity.color,
            .transform = entity.transform.mat4(),
        };
        cb.pushConstants(this.layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, @sizeOf(PushConstantData), &pcd);

        entity.model.bind(cb.handle);
        entity.model.draw(cb.handle);
    }
}
