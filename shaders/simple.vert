#version 450

layout (location = 0) in vec3 position;

layout (push_constant) uniform Push {
    mat2 transform;
    vec3 offset;
    vec3 color;
} push;

void main () {
    // vec2 pos = (push.transform * vec3(position, 1)).xy;
    vec2 pos = push.transform * position.xy + push.offset.xy;
    gl_Position = vec4(pos, 0, 1);
}
