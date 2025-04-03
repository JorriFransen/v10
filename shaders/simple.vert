#version 450

struct Vertex {
    vec2 pos;
    vec3 color;
};

Vertex vertices[3]=Vertex[](
        Vertex(vec2(0.0, -0.5), vec3(1, 0, 0)),
        Vertex(vec2(0.5, 0.5), vec3(1, 1, 0)),
        Vertex(vec2(-0.5, 0.5), vec3(1, 0, 1))
);

layout (location = 1) out vec4 vert_color;

void main () {
    Vertex vertex = vertices[gl_VertexIndex];
    gl_Position = vec4(vertex.pos, 0.0, 1.0);
    vert_color = vec4(vertex.color, 1);
}
