const std = @import("std");
const log = std.log.scoped(.r2d);
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const math = @import("../math.zig");
const mem = @import("memory");

const Renderer = @This();
const Device = gfx.Device;
const Pipeline = gfx.Pipeline;
const Texture = gfx.Texture;
const Sprite = gfx.Sprite;
const Font = gfx.Font;
const Camera = gfx.Camera2D;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Rect = math.Rect;
const Index = u32;

const assert = std.debug.assert;

// Buffer sizes are for typical use cases.
// Implement dynamic resizing if these limits prove too small.
const arena_cap = mem.MiB * 10;
const buffer_init_cap = mem.MiB * 2;

const white = Vec4.scalar(1);

device: *Device = undefined,
layout: vk.PipelineLayout = .null_handle,
triangle_pipeline: Pipeline = .{},
text_pipeline: Pipeline = .{},
line_pipeline: Pipeline = .{},

arena: mem.Arena = undefined,
commands: std.ArrayList(DrawCommand) = undefined,

/// Offset for the next vertex to be written in the staging buffer, reset in beginFrame
vertex_offset: u32 = 0,
/// Offset for the next index to be written in the staging buffer, reset in beginFrame
index_offset: u32 = 0,

vertex_buffer_size: vk.DeviceSize = 0,
vertex_buffer: vk.Buffer = .null_handle,
vertex_buffer_memory: vk.DeviceMemory = .null_handle,
vertex_staging_buffer: vk.Buffer = .null_handle,
vertex_staging_buffer_memory: vk.DeviceMemory = .null_handle,
vertex_staging_buffer_mapped: []Vertex = undefined,

index_buffer_size: vk.DeviceSize = 0,
index_buffer: vk.Buffer = .null_handle,
index_buffer_memory: vk.DeviceMemory = .null_handle,
index_staging_buffer: vk.Buffer = .null_handle,
index_staging_buffer_memory: vk.DeviceMemory = .null_handle,
index_staging_buffer_mapped: []Index = undefined,

default_white_texture: Texture = undefined,

pub const Vertex = extern struct {
    pos: Vec2,
    color: Vec4 = Vec4.scalar(1),
    uv: Vec2 = Vec2.scalar(0),

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

const PushConstantData = extern struct {
    projection: Mat4,
    view: Mat4,
};

pub const CommandType = enum(u8) {
    line,
    triangle,
    quad,
    text,
};

pub const DrawCommand = struct {
    type: CommandType,
    texture: ?*const Texture,
    line_width: f32 = 1,

    /// Offset of the first vertex of this command into the staging buffer
    vertex_offset: u32,
    vertex_count: u32,
};

pub fn init(this: *Renderer, device: *Device, render_pass: vk.RenderPass) !void {
    this.device = device;

    this.layout = try this.createPipelineLayout(device);
    try this.createPipelines(render_pass, Pipeline.ConfigInfo.default2d());

    this.arena = try mem.Arena.init(.{ .virtual = .{ .reserved_capacity = arena_cap } });
    this.commands = std.ArrayList(DrawCommand).init(this.arena.allocator());

    const total_vertex_count = buffer_init_cap / @sizeOf(Vertex);
    this.vertex_buffer_size = @sizeOf(Vertex) * total_vertex_count;

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
    this.vertex_staging_buffer_mapped = vertices_mapped[0..total_vertex_count];

    const total_index_count = buffer_init_cap / @sizeOf(Index);
    this.index_buffer_size = @sizeOf(Index) * total_index_count;

    this.index_buffer = device.createBuffer(
        this.index_buffer_size,
        .{ .transfer_dst_bit = true, .index_buffer_bit = true },
        .{ .device_local_bit = true },
        &this.index_buffer_memory,
    ) catch return error.VulkanUnexpected;

    this.index_staging_buffer = device.createBuffer(
        this.index_buffer_size,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &this.index_staging_buffer_memory,
    ) catch return error.VulkanUnexpected;

    const index_data_opt = device.device.mapMemory(this.index_staging_buffer_memory, 0, this.index_buffer_size, .{}) catch return error.VulkanMapMemory;
    const index_data = index_data_opt orelse return error.VulkanMapMemory;

    const indices_mapped: [*]Index = @ptrCast(@alignCast(index_data));
    this.index_staging_buffer_mapped = indices_mapped[0..total_index_count];

    this.default_white_texture = try Texture.initDefaultWhite(device);
}

pub fn destroy(this: *Renderer) void {
    const vkd = &this.device.device;

    vkd.destroyPipelineLayout(this.layout, null);
    this.text_pipeline.destroy();
    this.triangle_pipeline.destroy();
    this.line_pipeline.destroy();

    this.arena.deinit();

    vkd.destroyBuffer(this.vertex_buffer, null);
    vkd.freeMemory(this.vertex_buffer_memory, null);
    vkd.unmapMemory(this.vertex_staging_buffer_memory);
    vkd.destroyBuffer(this.vertex_staging_buffer, null);
    vkd.freeMemory(this.vertex_staging_buffer_memory, null);

    vkd.destroyBuffer(this.index_buffer, null);
    vkd.freeMemory(this.index_buffer_memory, null);
    vkd.unmapMemory(this.index_staging_buffer_memory);
    vkd.destroyBuffer(this.index_staging_buffer, null);
    vkd.freeMemory(this.index_staging_buffer_memory, null);

    this.default_white_texture.deinit(this.device);
}

fn createPipelineLayout(this: *Renderer, device: *Device) !vk.PipelineLayout {
    const descriptor_set_layout = device.texture_sampler_set_layout;

    const push_constant_ranges = [_]vk.PushConstantRange{.{
        .offset = 0,
        .size = @sizeOf(PushConstantData),
        .stage_flags = .{ .vertex_bit = true },
    }};

    const pipeline_layout_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&descriptor_set_layout),
        .push_constant_range_count = push_constant_ranges.len,
        .p_push_constant_ranges = &push_constant_ranges,
    };

    return try this.device.device.createPipelineLayout(&pipeline_layout_info, null);
}

fn createPipelines(this: *Renderer, render_pass: vk.RenderPass, default_config: Pipeline.ConfigInfo) !void {
    var triangle_config = default_config;
    // TODO: Make defaultconfig take these as params?
    triangle_config.render_pass = render_pass;
    triangle_config.pipeline_layout = this.layout;
    triangle_config.vertex_binding_descriptions = &.{Vertex.binding_description};
    triangle_config.vertex_attribute_descriptions = &Vertex.attribute_descriptions;

    this.triangle_pipeline = try Pipeline.create(
        this.device,
        "shaders/simple_2d.vert.spv",
        "shaders/simple_2d.frag.spv",
        triangle_config,
    );

    const text_config = triangle_config;

    this.text_pipeline = try Pipeline.create(
        this.device,
        "shaders/text.vert.spv",
        "shaders/text.frag.spv",
        text_config,
    );

    var line_config = default_config;
    line_config.render_pass = render_pass;
    line_config.pipeline_layout = this.layout;
    line_config.vertex_binding_descriptions = &.{Vertex.binding_description};
    line_config.vertex_attribute_descriptions = &Vertex.attribute_descriptions;

    line_config.input_assembly_info.topology = .line_list;
    line_config.rasterization_info.line_width = 1;

    // var dynamic_states = [_]vk.DynamicState{ .viewport, .scissor, .line_width };
    var dynamic_states = Pipeline.ConfigInfo.default_dynamic_state_enables ++ .{.line_width};
    line_config.dynamic_state_enables = &dynamic_states;
    line_config.dynamic_state_info = vk.PipelineDynamicStateCreateInfo{
        .dynamic_state_count = dynamic_states.len,
        .p_dynamic_states = &dynamic_states,
        .flags = .{},
    };

    this.line_pipeline = try Pipeline.create(
        this.device,
        "shaders/line.vert.spv",
        "shaders/line.frag.spv",
        line_config,
    );
}

pub fn beginFrame(this: *Renderer, cb: vk.CommandBufferProxy) void {
    this.vertex_offset = 0;
    this.index_offset = 0;

    cb.bindVertexBuffers(0, 1, &[_]vk.Buffer{this.vertex_buffer}, &[_]vk.DeviceSize{0});
    const index_type = comptime switch (Index) {
        else => @panic(std.fmt.comptimePrint("Invalid type for vulkan vertex index '{}'", .{Index})),
        u8 => .uint8_khr,
        u16 => .uint16,
        u32 => .uint32,
    };
    cb.bindIndexBuffer(this.index_buffer, 0, index_type);
}

pub fn endFrame(this: *Renderer) void {
    // TODO: Consistent command buffer for this?
    const ccb = this.device.beginSingleTimeCommands();
    this.device.copyBuffer(ccb, this.vertex_staging_buffer, this.vertex_buffer, this.vertex_offset * @sizeOf(Vertex));
    this.device.copyBuffer(ccb, this.index_staging_buffer, this.index_buffer, this.index_offset * @sizeOf(Index));
    this.device.endSingleTimeCommands(ccb);
}

pub fn beginBatch(this: *Renderer, cb: vk.CommandBufferProxy, camera: *const Camera) Batch {
    this.commands.clearRetainingCapacity();

    return .{
        .camera = camera,
        .renderer = this,
        .command_buffer = cb,
    };
}

pub const DrawLineOptions = struct {
    color: Vec4 = white,
    width: f32 = 1,
};

pub const DrawTriangleOptions = struct {
    texture: ?*const Texture = null,
    color: Vec4 = white,
    uv_coords: [3]Vec2 = .{ Vec2.scalar(0), Vec2.scalar(0), Vec2.scalar(0) },
};

pub const DrawRectOptions = struct {
    texture: ?*const Texture = null,
    color: Vec4 = white,
    uv_rect: Rect = .{ .pos = Vec2.scalar(0), .size = Vec2.scalar(1) },
};

pub const Batch = struct {
    camera: *const Camera,
    renderer: *Renderer,
    command_buffer: vk.CommandBufferProxy,

    pub inline fn pushCommand(batch: *Batch, cmd: DrawCommand) void {
        batch.renderer.commands.append(cmd) catch @panic("Command memory full");
    }

    /// Draws a line segment between two points
    pub fn drawDebugLine(batch: *Batch, p0: Vec2, p1: Vec2, options: DrawLineOptions) void {
        const renderer = batch.renderer;

        const vbuf = batch.renderer.vertex_staging_buffer_mapped;
        const vstart = renderer.vertex_offset;
        if (vstart + 2 > vbuf.len) @panic("Vertex buffer full");

        const vertices = vbuf[vstart .. vstart + 2];

        vertices[0] = .{ .pos = p0, .color = options.color, .uv = Vec2.scalar(0) };
        vertices[1] = .{ .pos = p1, .color = options.color, .uv = Vec2.scalar(0) };

        renderer.vertex_offset += 2;

        batch.pushCommand(.{
            .type = .line,
            .texture = &batch.renderer.default_white_texture,
            .line_width = options.width,
            .vertex_offset = vstart,
            .vertex_count = 2,
        });
    }

    /// Draws a triangle with the specified vertices and options
    pub fn drawTriangle(batch: *Batch, p1: Vec2, p2: Vec2, p3: Vec2, options: DrawTriangleOptions) void {
        const renderer = batch.renderer;

        const vbuf = batch.renderer.vertex_staging_buffer_mapped;
        const vstart = renderer.vertex_offset;
        if (vstart + 3 > vbuf.len) @panic("Vertex buffer full");

        const vertices = vbuf[vstart .. vstart + 3];

        vertices[0] = .{ .pos = p1, .color = options.color, .uv = options.uv_coords[0] };
        vertices[1] = .{ .pos = p2, .color = options.color, .uv = options.uv_coords[1] };
        vertices[2] = .{ .pos = p3, .color = options.color, .uv = options.uv_coords[2] };

        renderer.vertex_offset += 3;

        batch.pushCommand(.{
            .type = .triangle,
            .texture = options.texture,
            .vertex_offset = vstart,
            .vertex_count = 3,
        });
    }

    /// Draws the specified rectangle with options (texture, color, uv_rect)
    pub fn drawRect(batch: *Batch, rect: Rect, options: DrawRectOptions) void {
        const renderer = batch.renderer;

        const vbuf = batch.renderer.vertex_staging_buffer_mapped;
        const vstart = renderer.vertex_offset;
        if (vstart + 4 > vbuf.len) @panic("Vertex buffer full");

        const vertices = vbuf[vstart .. vstart + 4];
        const uv_rect = options.uv_rect;

        vertices[0] = .{ .pos = rect.pos, .uv = uv_rect.pos, .color = options.color };
        vertices[1] = .{ .pos = rect.pos.add(.{ .x = rect.size.x }), .uv = uv_rect.pos.add(.{ .x = uv_rect.size.x }), .color = options.color };
        vertices[2] = .{ .pos = rect.pos.add(rect.size), .uv = uv_rect.pos.add(uv_rect.size), .color = options.color };
        vertices[3] = .{ .pos = rect.pos.add(.{ .y = rect.size.y }), .uv = uv_rect.pos.add(.{ .y = uv_rect.size.y }), .color = options.color };

        renderer.vertex_offset += 4;

        batch.pushCommand(.{
            .type = .quad,
            .texture = options.texture,
            .vertex_offset = vstart,
            .vertex_count = 4,
        });
    }

    /// Draws a sprite at the specified position, scaled by the sprites ppu
    pub fn drawSprite(batch: *Batch, sprite: *const Sprite, pos: Vec2) void {
        const size = sprite.texture.getSize().divScalar(sprite.ppu);
        const rect = Rect{ .pos = pos, .size = size };
        batch.drawRect(rect, .{ .texture = sprite.texture, .color = white, .uv_rect = sprite.uv_rect });
    }

    /// Draws a sprite at the specified rectangle
    pub fn drawSpriteRect(batch: *Batch, sprite: *Sprite, rect: Rect) void {
        batch.drawRect(rect, .{ .texture = sprite.texture, .color = white, .uv_rect = sprite.uv_rect });
    }

    pub fn drawText(batch: *Batch, font: *Font, pos: Vec2, text: []const u8) void {
        _ = text;
        const renderer = batch.renderer;

        const vbuf = batch.renderer.vertex_staging_buffer_mapped;
        const vstart = renderer.vertex_offset;
        // const vcount: u32 = @intCast(text.len * 4);
        const vcount = 4;
        if (vstart + vcount > vbuf.len) @panic("Vertex buffer full");

        const vertices = vbuf[vstart .. vstart + vcount];

        const uv_rect: Rect = .{ .pos = Vec2.scalar(0), .size = Vec2.scalar(1) };
        const color = white;
        const size = font.texture.getSize();

        vertices[0] = .{ .pos = pos, .uv = uv_rect.pos, .color = color };
        vertices[1] = .{ .pos = pos.add(.{ .x = size.x }), .uv = uv_rect.pos.add(.{ .x = uv_rect.size.x }), .color = color };
        vertices[2] = .{ .pos = pos.add(size), .uv = uv_rect.pos.add(uv_rect.size), .color = color };
        vertices[3] = .{ .pos = pos.add(.{ .y = size.y }), .uv = uv_rect.pos.add(.{ .y = uv_rect.size.y }), .color = color };

        renderer.vertex_offset += 4;

        batch.pushCommand(.{
            .type = .text,
            .texture = &font.texture,
            .vertex_offset = vstart,
            .vertex_count = vcount,
        });
    }

    pub fn end(batch: *const Batch) void {
        const renderer = batch.renderer;
        const cb = batch.command_buffer;

        if (renderer.commands.items.len < 1) return;

        // std.mem.sort(DrawCommand, this.commands.items, this, struct {
        //     fn f(ctx: @TypeOf(this), l: DrawCommand, r: DrawCommand) bool {
        //         const default = ctx.default_white_texture.descriptor_set;
        //         const l_tex_set = if (l.options.texture) |t| t.descriptor_set else default;
        //         const r_tex_set = if (r.options.texture) |t| t.descriptor_set else default;
        //         return @intFromEnum(l_tex_set) < @intFromEnum(r_tex_set);
        //     }
        // }.f);

        const pcd = PushConstantData{
            .projection = batch.camera.projection_matrix,
            .view = batch.camera.view_matrix,
        };
        cb.pushConstants(renderer.layout, .{ .vertex_bit = true }, 0, @sizeOf(PushConstantData), &pcd);

        // Number of indices for the current drawcall
        var batch_index_count: u32 = 0;

        var current_pipeline = switch (renderer.commands.items[0].type) {
            .line => &renderer.line_pipeline,
            .triangle, .quad => &renderer.triangle_pipeline,
            .text => &renderer.text_pipeline,
        };
        current_pipeline.bind(cb);

        var current_line_width: f32 = 1;
        if (renderer.commands.items[0].type == .line) {
            current_line_width = renderer.commands.items[0].line_width;
            cb.setLineWidth(current_line_width);
        }

        var current_texture = renderer.commands.items[0].texture orelse &renderer.default_white_texture;
        if (renderer.commands.items[0].type != .line) current_texture.bind(cb, renderer.layout);

        for (renderer.commands.items) |*command| {
            const command_pipeline = switch (command.type) {
                .line => &renderer.line_pipeline,
                .triangle, .quad => &renderer.triangle_pipeline,
                .text => &renderer.text_pipeline,
            };

            const is_line_command = command.type == .line;
            const switch_pipeline = current_pipeline != command_pipeline;
            const switch_texture = !is_line_command and current_texture != command.texture;
            const switch_line_width = is_line_command and (switch_pipeline or current_line_width != command.line_width);
            const flush = batch_index_count > 0 and (switch_pipeline or switch_texture or switch_line_width);

            if (flush) {
                cb.drawIndexed(batch_index_count, 1, renderer.index_offset, 0, 0);
                renderer.index_offset += batch_index_count;
                batch_index_count = 0;
            }

            if (switch_pipeline) {
                current_pipeline = command_pipeline;
                current_pipeline.bind(cb);
            }
            if (switch_texture) {
                current_texture = command.texture orelse &renderer.default_white_texture;
                current_texture.bind(cb, renderer.layout);
            } else if (switch_line_width) {
                current_line_width = command.line_width;
                cb.setLineWidth(current_line_width);
            }

            const ibuf = renderer.index_staging_buffer_mapped;
            const fi: Index = @intCast(command.vertex_offset);
            const istart = renderer.index_offset + batch_index_count;

            switch (command.type) {
                .line => {
                    assert(command.vertex_count == 2);
                    const icount = 2;
                    if (ibuf.len - istart < icount) @panic("Index buffer full");

                    ibuf[istart] = fi;
                    ibuf[istart + 1] = fi + 1;

                    batch_index_count += icount;
                },

                .triangle => {
                    assert(command.vertex_count % 3 == 0);
                    const triangle_count = command.vertex_count / 3;
                    const icount = 3 * triangle_count;
                    if (ibuf.len - istart < icount) @panic("Index buffer full");

                    for (0..triangle_count) |ti| {
                        const offset: u32 = @intCast(ti * 3);

                        ibuf[istart + offset] = fi + offset;
                        ibuf[istart + offset + 1] = fi + offset + 1;
                        ibuf[istart + offset + 2] = fi + offset + 2;
                    }

                    batch_index_count += icount;
                },

                .quad => {
                    assert(command.vertex_count % 4 == 0);
                    const quad_count = command.vertex_count / 4;
                    const icount = 6 * quad_count;
                    if (ibuf.len - istart < icount) @panic("Index buffer full");

                    for (0..quad_count) |qi| {
                        const offset: u32 = @intCast(qi * 4);

                        ibuf[istart + offset] = fi + offset;
                        ibuf[istart + offset + 1] = fi + offset + 1;
                        ibuf[istart + offset + 2] = fi + offset + 2;

                        ibuf[istart + offset + 3] = fi + offset;
                        ibuf[istart + offset + 4] = fi + offset + 2;
                        ibuf[istart + offset + 5] = fi + offset + 3;
                    }
                    batch_index_count += icount;
                },

                .text => {
                    assert(command.vertex_count % 4 == 0);
                    const quad_count = command.vertex_count / 4;
                    const icount = 6 * quad_count;
                    if (ibuf.len - istart < icount) @panic("Index buffer full");

                    for (0..quad_count) |qi| {
                        const offset: u32 = @intCast(qi * 4);

                        ibuf[istart + offset] = fi + offset;
                        ibuf[istart + offset + 1] = fi + offset + 1;
                        ibuf[istart + offset + 2] = fi + offset + 2;

                        ibuf[istart + offset + 3] = fi + offset;
                        ibuf[istart + offset + 4] = fi + offset + 2;
                        ibuf[istart + offset + 5] = fi + offset + 3;
                    }
                    batch_index_count += icount;
                },
            }
        }

        cb.drawIndexed(batch_index_count, 1, renderer.index_offset, 0, 0);
        renderer.index_offset += batch_index_count;
    }
};
