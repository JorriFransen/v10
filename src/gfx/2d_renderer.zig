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
const Camera = gfx.Camera;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Rect = math.Rect;
const Index = u32;

const assert = std.debug.assert;

const arena_cap = mem.MiB * 10;
const buffer_init_cap = mem.MiB * 2;
const white = Vec4.scalar(1);

device: *Device = undefined,
layout: vk.PipelineLayout = .null_handle,
triangle_pipeline: Pipeline = .{},
line_pipeline: Pipeline = .{},

arena: mem.Arena = undefined,
commands: std.ArrayList(DrawCommand) = undefined,

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

pub const DrawOptions = struct {
    /// This color overrides the per-vertex color
    color: ?Vec4 = Vec4.scalar(1),
    texture: ?*const Texture = null,
    uv_rect: ?Rect = null,
};

// TODO: Remove drawOptions (move into data)
// TODO: Test triangle uv
// TODO: Use Vertex for lines
pub const DrawCommand = struct {
    options: DrawOptions,

    data: union(enum) {
        triangle: [3]Vertex,
        quad: struct { pos: Vec2, size: Vec2 },
        line: struct {
            positions: [2]Vec2,
            width: f32,
        },
    },
};

pub fn init(this: *Renderer, device: *Device, render_pass: vk.RenderPass) !void {
    this.device = device;

    this.layout = try this.createPipelineLayout(device);
    try this.createPipelines(render_pass, Pipeline.ConfigInfo.default2d());

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

    const index_count = buffer_init_cap / @sizeOf(Index);
    this.index_buffer_size = @sizeOf(Index) * index_count;

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
    this.index_staging_buffer_mapped = indices_mapped[0..index_count];

    this.default_white_texture = try Texture.initDefaultWhite(device);
}

pub fn destroy(this: *Renderer) void {
    const vkd = &this.device.device;

    vkd.destroyPipelineLayout(this.layout, null);
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

pub fn beginBatch(this: *Renderer, cb: vk.CommandBufferProxy, camera: *const Camera) Batch {
    this.commands.clearRetainingCapacity();

    return .{
        .camera = camera,
        .renderer = this,
        .command_buffer = cb,
    };
}

pub const Batch = struct {
    camera: *const Camera,
    renderer: *Renderer,
    command_buffer: vk.CommandBufferProxy,
    line_width: f32 = 1,

    inline fn pushCommand(this: *const Batch, cmd: DrawCommand) void {
        this.renderer.commands.append(cmd) catch @panic("Command memory full");
    }

    pub fn drawTriangle(this: *const Batch, vertices: [3]Vertex, options: DrawOptions) void {
        this.pushCommand(.{ .options = options, .data = .{
            .triangle = vertices,
        } });
    }

    pub fn drawRect(this: *const Batch, pos: Vec2, size: Vec2, options: DrawOptions) void {
        this.pushCommand(.{ .options = options, .data = .{
            .quad = .{ .pos = pos, .size = size },
        } });
    }

    pub fn drawTexture(this: *const Batch, texture: *const Texture, pos: Vec2) void {
        const size = texture.getSize();
        this.pushCommand(.{
            .options = .{ .texture = texture, .color = white },
            .data = .{ .quad = .{ .pos = pos, .size = size } },
        });
    }

    pub fn drawTextureRect(this: *const Batch, texture: *const Texture, rect: Rect) void {
        this.pushCommand(.{
            .options = .{ .texture = texture, .color = white },
            .data = .{ .quad = .{ .pos = rect.pos, .size = rect.size } },
        });
    }

    pub fn drawTextureRectUv(this: *const Batch, texture: *const Texture, rect: Rect, uv_rect: Rect) void {
        this.pushCommand(.{
            .options = .{ .texture = texture, .color = white, .uv_rect = uv_rect },
            .data = .{ .quad = .{ .pos = rect.pos, .size = rect.size } },
        });
    }

    pub fn drawSprite(this: *const Batch, sprite: *const Sprite, pos: Vec2) void {
        const size = sprite.texture.getSize().divScalar(sprite.ppu);
        this.pushCommand(.{
            .options = .{ .texture = sprite.texture, .color = white, .uv_rect = sprite.uv_rect },
            .data = .{ .quad = .{ .pos = pos, .size = size } },
        });
    }

    pub fn drawSpriteRect(this: *const Batch, sprite: *const Sprite, rect: Rect) void {
        const size = sprite.texture.getSize().divScalar(sprite.ppu);
        this.pushCommand(.{
            .options = .{ .texture = sprite.texture, .color = white, .uv_rect = sprite.uv_rect },
            .data = .{ .quad = .{ .pos = rect.pos, .size = size.mul(rect.size) } },
        });
    }

    /// Line width is fixed in screen pixels. For world-space scaling, use drawRect or calculate width via ppu.
    pub fn drawLine(this: *const Batch, p1: Vec2, p2: Vec2, width: f32, color: Vec4) void {
        this.pushCommand(.{
            .options = .{ .color = color },
            .data = .{ .line = .{ .positions = .{ p1, p2 }, .width = width } },
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

        var current_pipeline = &renderer.triangle_pipeline;
        if (renderer.commands.items[0].data == .line) {
            current_pipeline = &renderer.line_pipeline;
        }
        current_pipeline.bind(cb);

        const pcd = PushConstantData{
            .projection = batch.camera.projection_matrix,
            .view = batch.camera.view_matrix,
        };

        cb.pushConstants(renderer.layout, .{ .vertex_bit = true }, 0, @sizeOf(PushConstantData), &pcd);

        cb.bindVertexBuffers(0, 1, &[_]vk.Buffer{renderer.vertex_buffer}, &[_]vk.DeviceSize{0});
        const index_type = comptime switch (Index) {
            else => @panic(std.fmt.comptimePrint("Invalid type for vulkan vertex index '{}'", .{Index})),
            u8 => .uint8_khr,
            u16 => .uint16,
            u32 => .uint32,
        };
        cb.bindIndexBuffer(renderer.index_buffer, 0, index_type);

        const vbuf = renderer.vertex_staging_buffer_mapped;
        const ibuf = renderer.index_staging_buffer_mapped;

        var vertex_count: usize = 0;
        var index_count: usize = 0;

        var batch_index_count: u32 = 0;
        var batch_index_offset: u32 = 0;

        var current_texture: *const Texture =
            renderer.commands.items[0].options.texture orelse
            &renderer.default_white_texture;

        current_texture.bind(cb, renderer.layout);

        for (renderer.commands.items) |*command| {
            const options = &command.options;
            const command_pipeline = switch (command.data) {
                .line => &renderer.line_pipeline,
                else => &renderer.triangle_pipeline,
            };
            const command_texture = options.texture orelse &renderer.default_white_texture;

            const switch_pipeline = current_pipeline != command_pipeline;
            const switch_texure = current_texture != command_texture;

            if (switch_pipeline or switch_texure) {
                if (batch_index_count > 0) {
                    cb.drawIndexed(batch_index_count, 1, batch_index_offset, 0, 0);
                }

                if (switch_pipeline) {
                    current_pipeline = command_pipeline;
                    current_pipeline.bind(cb);
                    if (current_pipeline == &renderer.line_pipeline) {
                        cb.setLineWidth(batch.line_width);
                    }
                }

                if (switch_texure) {
                    current_texture = command_texture;
                    current_texture.bind(cb, renderer.layout);
                }

                batch_index_offset = @intCast(index_count);
                batch_index_count = 0;
            }

            switch (command.data) {
                .triangle => |*t| {
                    if (options.color) |color| {
                        inline for (t) |*e| e.color = color;
                    }

                    const fi: Index = @intCast(vertex_count);
                    const indices = [3]Index{ fi, fi + 1, fi + 2 };

                    assert(vertex_count + t.len <= vbuf.len);
                    assert(index_count + indices.len <= ibuf.len);

                    @memcpy(vbuf[vertex_count .. vertex_count + t.len], t);
                    @memcpy(ibuf[index_count .. index_count + indices.len], &indices);

                    vertex_count += t.len;
                    index_count += indices.len;
                    batch_index_count += indices.len;
                },
                .quad => |q| {
                    const color = options.color orelse white;

                    const uvs: [4]Vec2 = if (options.uv_rect) |uvr|
                        .{
                            uvr.pos,
                            Vec2.new(uvr.pos.x + uvr.size.x, uvr.pos.y),
                            uvr.pos.add(uvr.size),
                            Vec2.new(uvr.pos.x, uvr.pos.y + uvr.size.y),
                        }
                    else
                        .{ Vec2.scalar(0), Vec2.new(1, 0), Vec2.scalar(1), Vec2.new(0, 1) };

                    const verts = [4]Vertex{
                        .{ .pos = q.pos, .color = color, .uv = uvs[0] },
                        .{ .pos = q.pos.add(Vec2{ .x = q.size.x }), .color = color, .uv = uvs[1] },
                        .{ .pos = q.pos.add(q.size), .color = color, .uv = uvs[2] },
                        .{ .pos = q.pos.add(Vec2{ .y = q.size.y }), .color = color, .uv = uvs[3] },
                    };

                    const fi: Index = @intCast(vertex_count);
                    const indices = [6]Index{
                        fi, fi + 1, fi + 2,
                        fi, fi + 2, fi + 3,
                    };

                    assert(vertex_count + verts.len <= vbuf.len);
                    assert(index_count + indices.len <= ibuf.len);

                    @memcpy(vbuf[vertex_count .. vertex_count + verts.len], &verts);
                    @memcpy(ibuf[index_count .. index_count + indices.len], &indices);

                    vertex_count += verts.len;
                    index_count += indices.len;
                    batch_index_count += indices.len;
                },
                .line => |l| {
                    if (batch.line_width != l.width) {
                        cb.setLineWidth(l.width);
                    }

                    const color = if (options.color) |c| c else white;

                    const verts = [2]Vertex{
                        .{ .pos = l.positions[0], .color = color },
                        .{ .pos = l.positions[1], .color = color },
                    };

                    const fi: Index = @intCast(vertex_count);
                    const indices = [2]Index{ fi, fi + 1 };

                    assert(vertex_count + verts.len <= vbuf.len);
                    assert(index_count + indices.len <= ibuf.len);

                    @memcpy(vbuf[vertex_count .. vertex_count + verts.len], &verts);
                    @memcpy(ibuf[index_count .. index_count + indices.len], &indices);

                    vertex_count += verts.len;
                    index_count += indices.len;
                    batch_index_count += indices.len;
                },
            }
        }

        cb.drawIndexed(batch_index_count, 1, batch_index_offset, 0, 0);

        // TODO: Consistent command buffer for this?
        const ccb = renderer.device.beginSingleTimeCommands();
        renderer.device.copyBuffer(ccb, renderer.vertex_staging_buffer, renderer.vertex_buffer, renderer.vertex_buffer_size);
        renderer.device.copyBuffer(ccb, renderer.index_staging_buffer, renderer.index_buffer, renderer.index_buffer_size);
        renderer.device.endSingleTimeCommands(ccb);
    }
};
