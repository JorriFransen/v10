#version 450

layout (location = 0) in vec3 position;
layout (location = 1) in vec3 color;

layout (location = 0) out vec3 frag_color;

layout (push_constant) uniform Push {
    mat4 transform;
    vec3 color;
} push;

void main () {
    vec4 pos = push.transform * vec4(position, 1);
    gl_Position = pos;
    frag_color = color;
}
