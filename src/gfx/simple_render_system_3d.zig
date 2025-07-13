const std = @import("std");
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const math = @import("../math.zig");

const Device = gfx.Device;
const Pipeline = gfx.Pipeline;
const Camera = gfx.Camera;
const Entity = @import("../entity.zig");
const GpuModel = @import("model.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

device: *Device = undefined,
layout: vk.PipelineLayout = .null_handle,
pipeline: Pipeline = .{},

const PushConstantData = extern struct {
    transform: Mat4,
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

fn createPipeline(this: *@This(), render_pass: vk.RenderPass) !Pipeline {
    var pipeline_config = Pipeline.ConfigInfo.default3d();
    pipeline_config.render_pass = render_pass;
    pipeline_config.pipeline_layout = this.layout;

    pipeline_config.vertex_binding_descriptions = &.{GpuModel.Vertex.binding_description};
    pipeline_config.vertex_attribute_descriptions = &GpuModel.Vertex.attribute_descriptions;

    return try Pipeline.create(this.device, "shaders/simple.vert.spv", "shaders/simple.frag.spv", pipeline_config);
}

pub fn drawEntities(this: *@This(), cb: vk.CommandBufferProxy, entities: []const Entity, camera: *const Camera) void {
    // TODO: Move this to beginRenderpass or beginframe?
    cb.bindPipeline(.graphics, this.pipeline.graphics_pipeline);

    const projection_view = camera.projection_matrix.mul(camera.view_matrix);

    for (entities) |*entity| {
        var pcd = PushConstantData{
            .color = entity.color,
            .transform = projection_view.mul(entity.transform.mat4()),
        };
        cb.pushConstants(this.layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, @sizeOf(PushConstantData), &pcd);

        if (entity.model) |model| {
            model.bind(cb);
            model.draw(cb);
        }
    }
}
