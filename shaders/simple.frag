#version 450

layout (location = 0) out vec4 out_color;

layout (location = 1) in vec4 vert_color;

void main () {
    out_color = vert_color;
}
