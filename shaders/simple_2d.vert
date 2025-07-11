
#version 450

layout (location = 0) in vec2 position;

layout (location = 0) out vec3 frag_color;


void main () {
    gl_Position = vec4(position, 0, 1);
    frag_color = vec3(1, 0, 0);
}
