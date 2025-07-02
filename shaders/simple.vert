#version 450

layout (location = 0) in vec3 position;
layout (location = 1) in vec3 color;
layout (location = 2) in vec3 normal;
layout (location = 3) in vec2 texcoord;

layout (location = 0) out vec3 frag_color;

layout (push_constant) uniform Push {
    mat4 transform;
    vec3 color;
} push;

void main () {
    vec4 pos = push.transform * vec4(position, 1);
    gl_Position = pos;

    frag_color = normal * 0.5 + 0.5;

    // vec3 c = normal;
    // if (c.r < 0) c.r = c.r * -0.1;
    // if (c.g < 0) c.g = c.g * -0.1;
    // if (c.b < 0) c.b = c.b * -0.1;
    //
    // frag_color = c;
}
