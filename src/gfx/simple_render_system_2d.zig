const std = @import("std");
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const math = @import("../math.zig");

const Device = gfx.Device;
const Pipeline = gfx.Pipeline;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

device: *Device = undefined,
layout: vk.PipelineLayout = .null_handle,
pipeline: Pipeline = .{},

pub const Vertex = extern struct {
    pos: Vec3,

    // TODO: Make this external to enable reuse on different vertex structs
    const field_count = @typeInfo(Vertex).@"struct".fields.len;
    pub const binding_description = vk.VertexInputBindingDescription{ .binding = 0, .stride = @sizeOf(Vertex), .input_rate = .vertex };
    pub const attribute_descriptions: [field_count]vk.VertexInputAttributeDescription = blk: {
        var result: [field_count]vk.VertexInputAttributeDescription = undefined;

        for (&result, 0..) |*desc, i| {
            const field_info = @typeInfo(Vertex).@"struct".fields[i];

            desc.* = .{
                .location = i,
                .binding = 0,
                .format = switch (field_info.type) {
                    else => @compileError(std.fmt.comptimePrint("Unhandled Vertex member type '{}'", .{field_info.type})),
                    Vec2 => .r32g32_sfloat,
                    Vec3 => .r32g32b32_sfloat,
                    Vec4 => .r32g32b32a32_sfloat,
                },
                .offset = @offsetOf(Vertex, field_info.name),
            };
        }
        break :blk result;
    };
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
    const pipeline_layout_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = 0,
        .p_set_layouts = null,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = null,
    };

    return try this.device.device.createPipelineLayout(&pipeline_layout_info, null);
}

fn createPipeline(this: *@This(), render_pass: vk.RenderPass) !Pipeline {
    var pipeline_config = Pipeline.ConfigInfo.default2d();
    pipeline_config.render_pass = render_pass;
    pipeline_config.pipeline_layout = this.layout;

    pipeline_config.vertex_binding_descriptions = &.{Vertex.binding_description};
    pipeline_config.vertex_attribute_descriptions = &Vertex.attribute_descriptions;

    return try Pipeline.create(this.device, "shaders/simple_2d.vert.spv", "shaders/simple_2d.frag.spv", pipeline_config);
}
