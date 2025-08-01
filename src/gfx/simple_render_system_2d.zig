const std = @import("std");
const log = std.log.scoped(.r2d);
const vk = @import("vulkan");
const gfx = @import("../gfx.zig");
const math = @import("../math.zig");
const mem = @import("memory");

const RenderSystem2D = @This();
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
pipeline: Pipeline = .{},

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

// TODO: Allow uv coords for triangle
pub const DrawCommand = struct {
    options: DrawOptions,

    data: union(enum) {
        triangle: [3]Vertex,
        quad: struct { pos: Vec2, size: Vec2 },
    },
};

pub fn init(this: *RenderSystem2D, device: *Device, render_pass: vk.RenderPass) !void {
    this.device = device;

    this.layout = try this.createPipelineLayout(device);
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

pub fn destroy(this: *RenderSystem2D) void {
    const vkd = &this.device.device;

    vkd.destroyPipelineLayout(this.layout, null);
    this.pipeline.destroy();

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

fn createPipelineLayout(this: *RenderSystem2D, device: *Device) !vk.PipelineLayout {
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

fn createPipeline(this: *RenderSystem2D, render_pass: vk.RenderPass) !Pipeline {
    var pipeline_config = Pipeline.ConfigInfo.default2d();
    pipeline_config.render_pass = render_pass;
    pipeline_config.pipeline_layout = this.layout;

    pipeline_config.vertex_binding_descriptions = &.{Vertex.binding_description};
    pipeline_config.vertex_attribute_descriptions = &Vertex.attribute_descriptions;

    return try Pipeline.create(this.device, "shaders/simple_2d.vert.spv", "shaders/simple_2d.frag.spv", pipeline_config);
}

pub fn beginBatch(this: *RenderSystem2D, cb: vk.CommandBufferProxy, camera: *const Camera) Batch {
    this.commands.clearRetainingCapacity();

    return .{
        .camera = camera,
        .system = this,
        .command_buffer = cb,
    };
}

pub const Batch = struct {
    camera: *const Camera,
    system: *RenderSystem2D,
    command_buffer: vk.CommandBufferProxy,

    inline fn pushCommand(this: *const Batch, cmd: DrawCommand) void {
        this.system.commands.append(cmd) catch @panic("Command memory full");
    }

    pub fn drawTriangle(this: *const Batch, vertices: [3]Vertex, options: DrawOptions) void {
        this.pushCommand(.{ .options = options, .data = .{
            .triangle = vertices,
        } });
    }

    pub fn drawQuad(this: *const Batch, pos: Vec2, size: Vec2, options: DrawOptions) void {
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
        const size = sprite.texture.getSize().div_scalar(sprite.ppu);
        this.pushCommand(.{
            .options = .{ .texture = sprite.texture, .color = white, .uv_rect = sprite.uv_rect },
            .data = .{ .quad = .{ .pos = pos, .size = size } },
        });
    }

    pub fn drawSpriteRect(this: *const Batch, sprite: *const Sprite, rect: Rect) void {
        const size = sprite.texture.getSize().div_scalar(sprite.ppu);
        this.pushCommand(.{
            .options = .{ .texture = sprite.texture, .color = white, .uv_rect = sprite.uv_rect },
            .data = .{ .quad = .{ .pos = rect.pos, .size = size.mul(rect.size) } },
        });
    }

    pub fn end(batch: *const Batch) void {
        const system = batch.system;
        const cb = batch.command_buffer;

        if (system.commands.items.len < 1) return;

        // std.mem.sort(DrawCommand, this.commands.items, this, struct {
        //     fn f(ctx: @TypeOf(this), l: DrawCommand, r: DrawCommand) bool {
        //         const default = ctx.default_white_texture.descriptor_set;
        //         const l_tex_set = if (l.options.texture) |t| t.descriptor_set else default;
        //         const r_tex_set = if (r.options.texture) |t| t.descriptor_set else default;
        //         return @intFromEnum(l_tex_set) < @intFromEnum(r_tex_set);
        //     }
        // }.f);

        cb.bindPipeline(.graphics, system.pipeline.graphics_pipeline);

        const pcd = PushConstantData{
            .projection = batch.camera.projection_matrix,
            .view = batch.camera.view_matrix,
        };

        cb.pushConstants(system.layout, .{ .vertex_bit = true }, 0, @sizeOf(PushConstantData), &pcd);

        cb.bindVertexBuffers(0, 1, &[_]vk.Buffer{system.vertex_buffer}, &[_]vk.DeviceSize{0});
        const index_type = comptime switch (Index) {
            else => @panic(std.fmt.comptimePrint("Invalid type for vulkan vertex index '{}'", .{Index})),
            u8 => .uint8_khr,
            u16 => .uint16,
            u32 => .uint32,
        };
        cb.bindIndexBuffer(system.index_buffer, 0, index_type);

        const vbuf = system.vertex_staging_buffer_mapped;
        const ibuf = system.index_staging_buffer_mapped;

        var vertex_count: usize = 0;
        var index_count: usize = 0;

        var batch_index_count: u32 = 0;
        var batch_index_offset: u32 = 0;

        var current_texture: *const Texture =
            system.commands.items[0].options.texture orelse
            &system.default_white_texture;

        current_texture.bind(cb, system.layout);

        for (system.commands.items) |*command| {
            const options = &command.options;
            const command_texture = options.texture orelse &system.default_white_texture;

            if (current_texture != command_texture) {
                if (batch_index_count > 0) {
                    cb.drawIndexed(batch_index_count, 1, batch_index_offset, 0, 0);
                }

                current_texture = command_texture;
                current_texture.bind(cb, system.layout);
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
            }
        }

        cb.drawIndexed(batch_index_count, 1, batch_index_offset, 0, 1);

        // TODO: Consistent command buffer for this?
        const ccb = system.device.beginSingleTimeCommands();
        system.device.copyBuffer(ccb, system.vertex_staging_buffer, system.vertex_buffer, system.vertex_buffer_size);
        system.device.copyBuffer(ccb, system.index_staging_buffer, system.index_buffer, system.index_buffer_size);
        system.device.endSingleTimeCommands(ccb);
    }
};
