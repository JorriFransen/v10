#version 450

layout (location = 0) in vec2 position;

layout (push_constant) uniform Push {
    mat4 transform;
    vec2 offset;
    vec3 color;
} push;

void main () {
    gl_Position = push.transform * vec4(position, 0, 1);
}
