#version 450

layout (location = 0) in vec2 position;

layout (push_constant) uniform Push {
    mat3 transform;
    vec2 offset;
    vec3 color;
} push;

void main () {
    vec2 pos = (push.transform * vec3(position, 1)).xy;
    gl_Position = vec4(pos, 0, 1);
}
