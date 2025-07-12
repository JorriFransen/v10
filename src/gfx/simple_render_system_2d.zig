const std = @import("std");
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const math = @import("../math.zig");
const mem = @import("memory");

const Device = gfx.Device;
const Pipeline = gfx.Pipeline;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

const assert = std.debug.assert;

const arena_cap = mem.MiB * 10;
const buffer_init_cap = mem.MiB * 2;

device: *Device = undefined,
layout: vk.PipelineLayout = .null_handle,
pipeline: Pipeline = .{},

arena: mem.Arena = undefined,
commands: std.ArrayList(DrawCommand) = undefined,

vertex_buffer_size: vk.DeviceSize = 0,
vertex_buffer: vk.Buffer = .null_handle,
vertex_buffer_memory: vk.DeviceMemory = .null_handle,
vertex_staging_buffer: vk.Buffer = .null_handle,
vertex_staging_buffer_memory: vk.DeviceMemory = .null_handle,
vertex_staging_buffer_mapped: []Vertex = undefined,

pub const Vertex = extern struct {
    pos: Vec2,
    color: Vec4,

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

pub const DrawOptions = struct {
    color: Vec4 = Vec4.scalar(1),
};

pub const DrawCommand = struct {
    options: DrawOptions,

    data: union(enum) {
        triangle: struct { p1: Vec2, p2: Vec2, p3: Vec2 },
        quad: struct { pos: Vec2, size: Vec2 },
    },
};

pub fn init(this: *@This(), device: *Device, render_pass: vk.RenderPass) !void {
    this.device = device;

    this.layout = try this.createPipelineLayout();
    this.pipeline = try this.createPipeline(render_pass);

    this.arena = try mem.Arena.init(.{ .virtual = .{ .reserved_capacity = arena_cap } });
    this.commands = std.ArrayList(DrawCommand).init(this.arena.allocator());

    const vertex_count = buffer_init_cap / @sizeOf(Vertex);
    this.vertex_buffer_size = @sizeOf(Vertex) * vertex_count;

    this.vertex_buffer = device.createBuffer(
        this.vertex_buffer_size,
        .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .{ .device_local_bit = true },
        &this.vertex_buffer_memory,
    ) catch return error.VulkanUnexpected;

    this.vertex_staging_buffer = device.createBuffer(
        this.vertex_buffer_size,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &this.vertex_staging_buffer_memory,
    ) catch return error.VulkanUnexpected;

    const vertex_data_opt = device.device.mapMemory(this.vertex_staging_buffer_memory, 0, this.vertex_buffer_size, .{}) catch return error.VulkanMapMemory;
    const vertex_data = vertex_data_opt orelse return error.VulkanMapMemory;

    const vertices_mapped: [*]Vertex = @ptrCast(@alignCast(vertex_data));
    this.vertex_staging_buffer_mapped = vertices_mapped[0..vertex_count];
}

pub fn destroy(this: *@This()) void {
    const vkd = this.device.device;

    vkd.destroyPipelineLayout(this.layout, null);
    this.pipeline.destroy();

    this.arena.deinit();

    vkd.destroyBuffer(this.vertex_buffer, null);
    vkd.freeMemory(this.vertex_buffer_memory, null);
    vkd.unmapMemory(this.vertex_staging_buffer_memory);
    vkd.destroyBuffer(this.vertex_staging_buffer, null);
    vkd.freeMemory(this.vertex_staging_buffer_memory, null);
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

pub fn beginDrawing(this: *@This()) void {
    this.commands.clearRetainingCapacity();
}

pub fn endDrawing(this: *@This(), cb: vk.CommandBufferProxy) void {
    const buf = this.vertex_staging_buffer_mapped;
    var vertex_count: usize = 0;

    for (this.commands.items) |command| {
        const color = command.options.color;

        switch (command.data) {
            .triangle => |t| {
                assert(vertex_count + 3 <= buf.len);
                const verts = [3]Vertex{
                    .{ .pos = t.p1, .color = color },
                    .{ .pos = t.p2, .color = color },
                    .{ .pos = t.p3, .color = color },
                };
                @memcpy(buf[vertex_count .. vertex_count + 3], &verts);
                vertex_count += 3;
            },
            .quad => |q| {
                assert(vertex_count + 6 <= buf.len);
                const p1 = q.pos;
                const p2 = p1.add(Vec2{ .x = q.size.x });
                const p3 = p1.add(q.size);
                const p4 = p1.add(Vec2{ .y = q.size.y });
                const verts = [6]Vertex{
                    .{ .pos = p1, .color = color },
                    .{ .pos = p2, .color = color },
                    .{ .pos = p3, .color = color },
                    .{ .pos = p1, .color = color },
                    .{ .pos = p3, .color = color },
                    .{ .pos = p4, .color = color },
                };
                @memcpy(buf[vertex_count .. vertex_count + 6], &verts);
                vertex_count += 6;
            },
        }
    }

    this.device.copyBuffer(this.vertex_staging_buffer, this.vertex_buffer, this.vertex_buffer_size);

    cb.bindPipeline(.graphics, this.pipeline.graphics_pipeline);
    cb.bindVertexBuffers(0, 1, &[_]vk.Buffer{this.vertex_buffer}, &[_]vk.DeviceSize{0});
    cb.draw(@intCast(vertex_count), 1, 0, 0);
}

pub fn drawTriangle(this: *@This(), p1: Vec2, p2: Vec2, p3: Vec2, options: DrawOptions) void {
    this.commands.append(.{ .options = options, .data = .{
        .triangle = .{ .p1 = p1, .p2 = p2, .p3 = p3 },
    } }) catch @panic("Command memory full");
}

pub fn drawQuad(this: *@This(), pos: Vec2, size: Vec2, options: DrawOptions) void {
    this.commands.append(.{ .options = options, .data = .{
        .quad = .{ .pos = pos, .size = size },
    } }) catch @panic("Command memory full");
}
