
#version 450

layout (set = 0, binding = 0) uniform sampler2D tex_sampler;

layout (location = 0) in vec4 frag_color;
layout (location = 1) in vec2 frag_uv;

layout (location = 0) out vec4 out_color;

void main () {
    out_color = frag_color * texture(tex_sampler, frag_uv);
}
