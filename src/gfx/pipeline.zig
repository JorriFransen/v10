const std = @import("std");
const gfx = @import("../gfx.zig");
const vk = @import("vulkan");
const mem = @import("../memory.zig");
const vklog = std.log.scoped(.vulkan);

const Device = gfx.Device;
const Model = gfx.Model;
const Allocator = std.mem.Allocator;

const assert = std.debug.assert;

device: *Device = undefined,
config: ConfigInfo = .{},
graphics_pipeline: vk.Pipeline = .null_handle,
vert_shader_module: vk.ShaderModule = .null_handle,
frag_shader_module: vk.ShaderModule = .null_handle,

pub const ConfigInfo = struct {
    viewport_info: vk.PipelineViewportStateCreateInfo = .{},
    input_assembly_info: vk.PipelineInputAssemblyStateCreateInfo = undefined,
    rasterization_info: vk.PipelineRasterizationStateCreateInfo = undefined,
    multisample_info: vk.PipelineMultisampleStateCreateInfo = undefined,
    color_blend_attachment: vk.PipelineColorBlendAttachmentState = undefined,
    color_blend_info: vk.PipelineColorBlendStateCreateInfo = undefined,
    depth_stencil_info: vk.PipelineDepthStencilStateCreateInfo = undefined,
    dynamic_state_enables: []vk.DynamicState = &.{},
    dynamic_state_info: vk.PipelineDynamicStateCreateInfo = .{},
    pipeline_layout: vk.PipelineLayout = .null_handle,
    render_pass: vk.RenderPass = .null_handle,
    sub_pass: u32 = 0,

    pub fn default() @This() {
        const viewport_info = vk.PipelineViewportStateCreateInfo{
            .viewport_count = 1,
            .p_viewports = null,
            .scissor_count = 1,
            .p_scissors = null,
        };

        const input_assembly_info = vk.PipelineInputAssemblyStateCreateInfo{
            .topology = .triangle_list,
            .primitive_restart_enable = vk.FALSE,
        };

        const rasterization_info = vk.PipelineRasterizationStateCreateInfo{
            .depth_clamp_enable = vk.FALSE,
            .rasterizer_discard_enable = vk.FALSE,
            .polygon_mode = .fill,
            .line_width = 1,
            .cull_mode = .{ .back_bit = false },
            .front_face = .counter_clockwise,
            .depth_bias_enable = vk.FALSE,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
        };

        const multisample_info = vk.PipelineMultisampleStateCreateInfo{
            .sample_shading_enable = vk.FALSE,
            .rasterization_samples = .{ .@"1_bit" = true },
            .min_sample_shading = 1,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = vk.FALSE,
            .alpha_to_one_enable = vk.FALSE,
        };

        const color_blend_attachment = vk.PipelineColorBlendAttachmentState{
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
            .blend_enable = vk.FALSE,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .one,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .one,
            .alpha_blend_op = .add,
        };

        const color_blend_info = vk.PipelineColorBlendStateCreateInfo{
            .logic_op_enable = vk.FALSE,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&color_blend_attachment),
            .blend_constants = .{ 0, 0, 0, 0 },
        };

        const depth_stencil_info = vk.PipelineDepthStencilStateCreateInfo{
            .depth_test_enable = vk.TRUE,
            .depth_write_enable = vk.TRUE,
            .depth_compare_op = .less,
            .depth_bounds_test_enable = vk.FALSE,
            .min_depth_bounds = 0,
            .max_depth_bounds = 1,
            .stencil_test_enable = vk.FALSE,
            .front = std.mem.zeroInit(vk.StencilOpState, .{}),
            .back = std.mem.zeroInit(vk.StencilOpState, .{}),
        };

        const dynamic_state_enables: []vk.DynamicState = @constCast(&default_dynamic_state_enables);
        const dynamic_state_info = vk.PipelineDynamicStateCreateInfo{
            .dynamic_state_count = dynamic_state_enables.len,
            .p_dynamic_states = dynamic_state_enables.ptr,
            .flags = .{},
        };

        return .{
            .viewport_info = viewport_info,
            .input_assembly_info = input_assembly_info,
            .rasterization_info = rasterization_info,
            .multisample_info = multisample_info,
            .color_blend_attachment = color_blend_attachment,
            .color_blend_info = color_blend_info,
            .depth_stencil_info = depth_stencil_info,
            .dynamic_state_enables = dynamic_state_enables,
            .dynamic_state_info = dynamic_state_info,
        };
    }

    const default_dynamic_state_enables = [_]vk.DynamicState{ .viewport, .scissor };
};

const ReadFileAllocError = error{
    Unexpected,
    FileNotFound,
    OutOfMemory,
};

fn readShaderFile(allocator: Allocator, path: []const u8) ReadFileAllocError![:0]align(4) const u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        else => return error.Unexpected,
        error.FileNotFound => {
            std.log.err("Unable to open file: '{s}'", .{path});
            return error.FileNotFound;
        },
    };
    defer file.close();

    const size = file.getEndPos() catch return error.Unexpected;
    assert(size % 4 == 0); // .spv file size must be divisable by 4

    const buf = allocator.alignedAlloc(u8, .@"4", size + 1) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };

    const read = file.readAll(buf) catch return error.Unexpected;
    assert(read == size);
    buf[read] = 0;

    return @ptrCast(buf[0..read]);
}

pub fn create(device: *Device, vert_path: []const u8, frag_path: []const u8, config: ConfigInfo) !@This() {
    assert(config.pipeline_layout != .null_handle);
    assert(config.render_pass != .null_handle);

    const vkd = device.device;

    // TODO: CLEANUP: Temp allocator
    var tmp = mem.get_temp();
    defer tmp.release();

    const vert_code = try readShaderFile(tmp.allocator(), vert_path);
    vklog.debug("vert_code.len: {}", .{vert_code.len});

    const frag_code = try readShaderFile(tmp.allocator(), frag_path);
    vklog.debug("frag_code.len: {}", .{frag_code.len});

    var this = @This(){
        .device = device,
        .config = config,
        .graphics_pipeline = .null_handle,
        .vert_shader_module = .null_handle,
        .frag_shader_module = .null_handle,
    };

    this.vert_shader_module = try this.createShaderModule(vert_code);
    this.frag_shader_module = try this.createShaderModule(frag_code);

    const shader_stage_infos = [2]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex_bit = true },
            .module = this.vert_shader_module,
            .p_name = "main",
            .flags = vk.PipelineShaderStageCreateFlags.fromInt(0),
            .p_next = null,
            .p_specialization_info = null,
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = this.frag_shader_module,
            .p_name = "main",
            .flags = .{},
            .p_next = null,
            .p_specialization_info = null,
        },
    };

    const binding_descriptions = Model.Vertex.binding_description;
    const attribute_descriptions = Model.Vertex.attribute_descriptions;

    const vertex_input_info = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&binding_descriptions),
        .vertex_attribute_description_count = attribute_descriptions.len,
        .p_vertex_attribute_descriptions = @ptrCast(&attribute_descriptions),
    };

    const pipeline_info = vk.GraphicsPipelineCreateInfo{
        .stage_count = shader_stage_infos.len,
        .p_stages = @ptrCast(&shader_stage_infos),
        .p_vertex_input_state = &vertex_input_info,
        .p_input_assembly_state = &config.input_assembly_info,
        .p_viewport_state = &config.viewport_info,
        .p_rasterization_state = &config.rasterization_info,
        .p_multisample_state = &config.multisample_info,
        .p_color_blend_state = &config.color_blend_info,
        .p_depth_stencil_state = &config.depth_stencil_info,
        .p_dynamic_state = &config.dynamic_state_info,
        .layout = config.pipeline_layout,
        .render_pass = config.render_pass,
        .subpass = 0,
        .base_pipeline_index = -1,
        .base_pipeline_handle = .null_handle,
    };

    if (try vkd.createGraphicsPipelines(.null_handle, 1, @ptrCast(&pipeline_info), null, @ptrCast(&this.graphics_pipeline)) != .success) {
        return error.vkCreateGraphicsPipelinesFailed;
    }

    return this;
}

pub fn destroy(this: *@This()) void {
    const vkd = this.device.device;

    vkd.destroyShaderModule(this.vert_shader_module, null);
    vkd.destroyShaderModule(this.frag_shader_module, null);

    vkd.destroyPipeline(this.graphics_pipeline, null);
}

fn createShaderModule(this: *@This(), code: []const u8) !vk.ShaderModule {
    const vkd = this.device.device;

    const create_info = vk.ShaderModuleCreateInfo{
        .code_size = code.len,
        .p_code = @ptrCast(@alignCast(code.ptr)),
    };

    return try vkd.createShaderModule(&create_info, null);
}
