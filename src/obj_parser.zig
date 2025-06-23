const std = @import("std");
const log = std.log.scoped(.obj_parser);
const gfx = @import("gfx.zig");
const mem = @import("memory.zig");
const math = @import("math.zig");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const Arena = mem.Arena;
const TempArena = mem.TempArena;
const SplitIterator = std.mem.SplitIterator(u8, .scalar);
const TokenIterator = std.mem.TokenIterator(u8, .scalar);
const LinkedList = std.DoublyLinkedList;

const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);

const assert = std.debug.assert;

const GEOM_EPS = 1e-6;

pub const ParseFlags = packed struct(u8) {
    vertex_colors: bool = true,
    __reserved__: u7 = 0,
};

pub const ParseOptions = struct {
    /// Contents of an obj file.
    buffer: []const u8,
    /// Filename or other identifier used in error messages.
    name: []const u8 = "",
    flags: ParseFlags = .{},
};

pub const ObjParseError = error{
    Syntax,
    OutOfMemory,
    TriangulationFailed,
};

pub const Object = struct {
    name: []const u8 = "",
    faces: []const Face = &.{},
};

pub const Face = struct {
    indices: []const Index = &.{},
};

pub const Index = struct {
    vertex: u32 = 0,
    texcoord: u32 = 0,
    normal: u32 = 0,
};

const Model = struct {
    vertices: []const Vec3,
    colors: []const Vec3,
    normals: []const Vec3,
    texcoords: []const @Vector(2, f32),
    indices: []const Index = &.{},
    faces: []const Face = &.{},
    objects: []const Object = &.{},
};

const ProjectedVertex = struct {
    pos: Vec2,
    idx: Index,
    node: LinkedList.Node = .{},
};

pub fn parse(allocator: Allocator, options: ParseOptions) ObjParseError!Model {
    const buffer = options.buffer;

    var num_objects: usize = 0;
    var num_verts: u32 = 0;
    var num_normals: u32 = 0;
    var num_uvs: u32 = 0;
    var num_indices: usize = 0;
    var num_faces: usize = 0;
    var need_triangulation = false;

    var line_it = tokenize(buffer, '\n'); // TODO: Make this work with CRLF
    var line_num: usize = 1;

    while (line_it.next()) |line| : (line_num += 1) {
        errdefer log.err("{s}:{}: Invalid line: '{s}'", .{ options.name, line_num, line });

        var field_it = split(line, ' ');
        const field = field_it.next() orelse return error.Syntax;

        if (eq(field, "v")) {
            num_verts += 1;
        } else if (eq(field, "vn")) {
            num_normals += 1;
        } else if (eq(field, "vt")) {
            num_uvs += 1;
        } else if (eq(field, "f")) {
            const face_indices = findFaceIndexCount(field_it.rest());
            assert(face_indices >= 3);
            if (face_indices > 3) {
                need_triangulation = true;
            }

            num_indices += face_indices;
            num_faces += 1;
        } else if (eq(field, "o")) {
            num_objects += 1;
        } else if (eq(field, "s")) {
            // ok, skip
        } else if (eq(field, "mtllib")) {
            // ok, skip
        } else if (eq(field, "usemtl")) {
            // ok, skip
        } else if (eq(field, "#")) {
            // ok, skip
        } else {
            return error.Syntax;
        }
    }

    var vertices = try std.ArrayListUnmanaged(Vec3).initCapacity(allocator, num_verts);
    var normals = try std.ArrayListUnmanaged(Vec3).initCapacity(allocator, num_normals);
    var texcoords = try std.ArrayListUnmanaged(@Vector(2, f32)).initCapacity(allocator, num_uvs);
    var objects = try std.ArrayListUnmanaged(Object).initCapacity(allocator, num_objects);

    var colors: std.ArrayListUnmanaged(Vec3) = undefined;
    var parse_vector_fn = &parseVector;
    if (options.flags.vertex_colors) {
        colors = try std.ArrayListUnmanaged(Vec3).initCapacity(allocator, num_verts);
        parse_vector_fn = parseVectorAndColor;
    }

    var ta = mem.get_scratch(@ptrCast(@alignCast(allocator.ptr)));
    defer ta.release();

    const face_alloc = if (need_triangulation) ta.allocator() else allocator;
    var faces = try std.ArrayListUnmanaged(Face).initCapacity(face_alloc, num_faces);
    var indices = try std.ArrayListUnmanaged(Index).initCapacity(face_alloc, num_indices);

    var current_object: ?*Object = null;
    var obj_face_offset: usize = 0;

    line_it = tokenize(buffer, '\n'); // TODO: Make this work with CRLF
    line_num = 1;
    while (line_it.next()) |line| : (line_num += 1) {
        errdefer log.err("{s}:{}: Invalid line: '{s}'", .{ options.name, line_num, line });

        var field_it = tokenize(line, ' ');
        const field = field_it.next() orelse return error.Syntax;

        if (eq(field, "v")) {
            parse_vector_fn(&field_it, &vertices, &colors);
        } else if (eq(field, "vn")) {
            normals.appendAssumeCapacity(parseVec3(&field_it));
        } else if (eq(field, "vt")) {
            texcoords.appendAssumeCapacity(parseVec2(&field_it));
        } else if (eq(field, "f")) {
            const face = try parseFace(field_it.rest(), @intCast(vertices.items.len), num_uvs, @intCast(normals.items.len), &indices);
            faces.appendAssumeCapacity(face);
        } else if (eq(field, "o")) {
            if (current_object) |obj| {
                obj.faces = faces.items[obj_face_offset..faces.items.len];
            }
            obj_face_offset = faces.items.len;

            const obj = objects.addOneAssumeCapacity();
            obj.name = field_it.rest();
            current_object = obj;
        } else if (eq(field, "s")) {
            // ok, skip
        } else if (eq(field, "mtllib")) {
            // ok, skip
        } else if (eq(field, "usemtl")) {
            // ok, skip
        } else if (eq(field, "#")) {
            // ok, skip
        } else {
            return error.Syntax;
        }
    }
    if (current_object) |obj| {
        obj.faces = faces.items[obj_face_offset..faces.items.len];
    }

    assert(vertices.items.len == num_verts);
    if (options.flags.vertex_colors) assert(colors.items.len == num_verts);
    assert(texcoords.items.len == num_uvs);
    assert(normals.items.len == num_normals);
    assert(indices.items.len == num_indices);
    assert(faces.items.len == num_faces);
    assert(objects.items.len == num_objects);

    if (need_triangulation) {
        var triangle_face_count: usize = 0;
        for (faces.items) |face| {
            assert(face.indices.len >= 3);
            triangle_face_count += face.indices.len - 2;
        }

        var fta = TempArena.init(ta.arena);

        var new_faces = try std.ArrayListUnmanaged(Face).initCapacity(allocator, triangle_face_count);
        var new_indices = try std.ArrayListUnmanaged(Index).initCapacity(allocator, triangle_face_count * 3);

        for (faces.items, 0..) |face, fi| {
            assert(face.indices.len >= 3);

            var normal_sum = Vec3{ 0, 0, 0 };
            for (0..face.indices.len) |i| {
                const p_cur_idx = face.indices[i].vertex;
                const p_next_idx = face.indices[(i + 1) % face.indices.len].vertex;

                const p_cur = vertices.items[p_cur_idx];
                const p_next = vertices.items[p_next_idx];

                normal_sum[0] += (p_cur[1] * p_next[2]) - (p_cur[2] * p_next[1]); // X component
                normal_sum[1] += (p_cur[2] * p_next[0]) - (p_cur[0] * p_next[2]); // Y component
                normal_sum[2] += (p_cur[0] * p_next[1]) - (p_cur[1] * p_next[0]); // Z component
            }
            const fn_mag_sq = dot(normal_sum, normal_sum);
            if (fn_mag_sq < GEOM_EPS * GEOM_EPS) return error.TriangulationFailed;
            const face_normal = normalize(normal_sum);

            const nx = @abs(face_normal[0]);
            const ny = @abs(face_normal[1]);
            const nz = @abs(face_normal[2]);

            const Mask = struct {
                u: usize,
                v: usize,
                s: f32,
            };

            // Third element is sign of projection
            const mask: Mask =
                if (nx >= ny and nx >= nz)
                    .{ .u = 1, .v = 2, .s = if (face_normal[0] > 0) 1 else -1 }
                else if (ny >= nx and ny >= nz)
                    .{ .u = 0, .v = 2, .s = if (face_normal[1] > 0) 1 else -1 }
                else
                    .{ .u = 0, .v = 1, .s = if (face_normal[2] > 0) 1 else -1 };

            var u_basis = Vec3{ 0, 0, 0 };
            var v_basis = Vec3{ 0, 0, 0 };
            u_basis[mask.u] = 1;
            v_basis[mask.v] = 1;
            const basis_cross = cross(u_basis, v_basis);
            const bdot = dot(basis_cross, face_normal);
            const plane_handedness_factor: f32 = if (bdot > 0) 1 else -1; // Controls winding order of indices added to the final list

            fta.release();
            const projected_vertices_mem = try fta.allocator().alloc(ProjectedVertex, face.indices.len);
            var vertex_list: LinkedList = .{};

            for (face.indices, projected_vertices_mem) |idx, *pv| {
                const v = vertices.items[idx.vertex];
                const p: Vec2 = .{ v[mask.u], v[mask.v] };

                pv.* = .{ .pos = p, .idx = idx };

                // TODO: Don't append duplicates
                // TODO: Remove collinear intermidate vertices
                vertex_list.append(&pv.node);
            }

            {
                // TODO: Abstract to function so we can merge this code with test code.
                var winding_sum: f32 = 0.0; // Determines (c)cw (cw is reversed to ccw later)
                var current_node = vertex_list.first;

                // Calculate the *original* winding sum of the projected polygon
                while (current_node) |node| {
                    const pv_cur: *ProjectedVertex = @alignCast(@fieldParentPtr("node", node));
                    const pv_next_node = node.next orelse vertex_list.first.?;
                    const pv_next: *ProjectedVertex = @alignCast(@fieldParentPtr("node", pv_next_node));

                    winding_sum += (pv_cur.pos[0] * pv_next.pos[1]) - (pv_next.pos[0] * pv_cur.pos[1]);
                    current_node = node.next;
                }

                if (winding_sum < -GEOM_EPS) {
                    // log.debug("Face {} effective winding is negative. Reversing winding order for consistent PD.", .{fi});
                    var temp_list: LinkedList = .{};
                    while (vertex_list.pop()) |node| {
                        temp_list.append(node);
                    }
                    vertex_list = temp_list;
                } else if (winding_sum > GEOM_EPS) {
                    // log.debug("Face {} effective winding is positive. No reversal needed.", .{fi});
                } else {
                    log.warn("Face {} has a near-zero effective winding sum. Skipping triangulation (likely degenerate).", .{fi});
                    continue;
                }
            }

            var num_vertices = face.indices.len;
            var it = vertex_list.first;

            clip_loop: while (num_vertices > 3) {
                const node = it.?;
                const prev: *ProjectedVertex = @alignCast(@fieldParentPtr("node", node.prev orelse vertex_list.last.?));
                const cur: *ProjectedVertex = @alignCast(@fieldParentPtr("node", node));
                const next: *ProjectedVertex = @alignCast(@fieldParentPtr("node", node.next orelse vertex_list.first.?));

                if (!convex(prev.pos, cur.pos, next.pos)) {
                    it = node.next orelse vertex_list.first;
                    continue;
                }

                var c_it = next.node.next orelse vertex_list.first;
                while (c_it) |c_node| {
                    if (c_node == &prev.node) break;

                    const c: *ProjectedVertex = @alignCast(@fieldParentPtr("node", c_node));

                    if (inTriangle(c.pos, prev.pos, cur.pos, next.pos)) {
                        it = node.next orelse vertex_list.first;
                        continue :clip_loop;
                    }

                    c_it = c_node.next orelse vertex_list.first;
                }

                // Found ear
                const new_triangle: [3]Index = if (plane_handedness_factor > 0)
                    .{ prev.idx, cur.idx, next.idx }
                else
                    .{ prev.idx, next.idx, cur.idx };

                const start_idx = new_indices.items.len;
                new_indices.appendSliceAssumeCapacity(&new_triangle);
                new_faces.appendAssumeCapacity(.{ .indices = new_indices.items[start_idx .. start_idx + 3] });

                it = &next.node;
                vertex_list.remove(&cur.node);

                num_vertices -= 1;
            }

            assert(num_vertices == 3);
            const n0 = vertex_list.first.?;
            const n1 = n0.next.?;
            const n2 = n1.next.?;
            assert(n1.next == n2);
            const lv0: *ProjectedVertex = @alignCast(@fieldParentPtr("node", n0));
            const lv1: *ProjectedVertex = @alignCast(@fieldParentPtr("node", n1));
            const lv2: *ProjectedVertex = @alignCast(@fieldParentPtr("node", n2));
            const last_triangle: [3]Index = if (plane_handedness_factor > 0)
                .{ lv0.idx, lv1.idx, lv2.idx }
            else
                .{ lv0.idx, lv2.idx, lv1.idx };

            const start_idx = new_indices.items.len;
            new_indices.appendSliceAssumeCapacity(&last_triangle);
            new_faces.appendAssumeCapacity(.{ .indices = new_indices.items[start_idx .. start_idx + 3] });
        }

        indices = new_indices;
        faces = new_faces;
    }

    return .{
        .vertices = vertices.items,
        .colors = colors.items,
        .normals = normals.items,
        .texcoords = texcoords.items,
        .indices = indices.items,
        .faces = faces.items,
        .objects = objects.items,
    };
}
inline fn inTriangle(p: Vec2, ta: Vec2, tb: Vec2, tc: Vec2) bool {
    const v0 = tc - ta;
    const v1 = tb - ta;
    const v2 = p - ta;

    const dot00 = dot(v0, v0);
    const dot01 = dot(v0, v1);
    const dot02 = dot(v0, v2);
    const dot11 = dot(v1, v1);
    const dot12 = dot(v1, v2);

    const DENOM_EPS = 1e-9;
    const denom = dot00 * dot11 - dot01 * dot01;
    if (@abs(denom) < DENOM_EPS) {
        log.warn("Found degenerate triangle in 'inTriangle({}, {}, {}, {})'", .{ p, ta, tb, tc });
        return false;
    }

    const u = (dot11 * dot02 - dot01 * dot12) / denom;
    const v = (dot00 * dot12 - dot01 * dot02) / denom;

    return u > GEOM_EPS and v > GEOM_EPS and (u + v) < (1 - GEOM_EPS);
}

inline fn cross(a: Vec3, b: Vec3) Vec3 {
    const v1 = Vec3{ a[1], a[2], a[0] };
    const v2 = Vec3{ b[2], b[0], b[1] };
    const v3 = Vec3{ a[2], a[0], a[1] };
    const v4 = Vec3{ b[1], b[2], b[0] };
    return (v1 * v2) - (v3 * v4);
}

inline fn cross2d(a: Vec2, b: Vec2) f32 {
    return (a[0] * b[1]) - (a[1] * b[0]);
}

inline fn convex(prev: Vec2, cur: Vec2, next: Vec2) bool {
    const vec_in = cur - prev;
    const vec_out = next - cur;
    const pd = cross2d(vec_in, vec_out);

    if (pd > -GEOM_EPS) return true;
    return false;
}

inline fn dot(a: anytype, b: anytype) @typeInfo(@TypeOf(a)).vector.child {
    assert(@TypeOf(a) == @TypeOf(b));
    return @reduce(.Add, a * b);
}

inline fn normalize(v: anytype) @TypeOf(v) {
    const one_over_len = 1.0 / @sqrt(@reduce(.Add, v * v));
    return v * @as(@TypeOf(v), @splat(one_over_len));
}

fn findFaceIndexCount(str: []const u8) usize {
    var index_it = tokenize(str, ' ');
    var r: usize = 0;
    while (index_it.next()) |_| r += 1;
    return r;
}

fn parseFace(str: []const u8, num_verts: u32, num_texcoords: u32, num_normals: u32, indices: *std.ArrayListUnmanaged(Index)) !Face {
    var r = Face{};
    var index_it = tokenize(str, ' ');

    const start_idx = indices.items.len;

    while (index_it.next()) |fields| {
        var field_it = split(fields, '/');
        const vertex = parseInt64(field_it.next() orelse "") - 1;
        const texcoord = parseInt64(field_it.next() orelse "") - 1;
        const normal = parseInt64(field_it.next() orelse "") - 1;

        if (vertex >= num_verts) {
            log.err("Invalid vertex index: {}", .{vertex + 1});
            return error.Syntax;
        }
        if (texcoord >= num_texcoords) {
            log.err("Invalid texcoord index: {}", .{texcoord + 1});
            return error.Syntax;
        }
        if (normal >= num_normals) {
            log.err("Invalid normal index: {}", .{normal + 1});
            return error.Syntax;
        }

        indices.appendAssumeCapacity(.{
            .vertex = @intCast(if (vertex < 0) (vertex + (1 + num_verts)) else (vertex)),
            .texcoord = @intCast(if (texcoord < 0) (texcoord + (1 + num_texcoords)) else (texcoord)),
            .normal = @intCast(if (normal < 0) (normal + (1 + num_normals)) else (normal)),
        });
    }

    r.indices = indices.items[start_idx..];

    return r;
}

fn parseVector(field_it: *TokenIterator, vertices: *std.ArrayListUnmanaged(Vec3), colors: *std.ArrayListUnmanaged(Vec3)) void {
    _ = colors;
    vertices.appendAssumeCapacity(parseVec3(field_it));
}

fn parseVectorAndColor(field_it: *TokenIterator, vertices: *std.ArrayListUnmanaged(Vec3), colors: *std.ArrayListUnmanaged(Vec3)) void {
    vertices.appendAssumeCapacity(parseVec3(field_it));
    colors.appendAssumeCapacity(if (field_it.rest().len == 0) .{ 1, 1, 1 } else parseVec3(field_it));
}

inline fn parseVec3(field_it: *TokenIterator) Vec3 {
    return .{
        parseFloat(field_it.next() orelse ""),
        parseFloat(field_it.next() orelse ""),
        parseFloat(field_it.next() orelse ""),
    };
}

inline fn parseVec2(field_it: *TokenIterator) @Vector(2, f32) {
    return .{
        parseFloat(field_it.next() orelse ""),
        parseFloat(field_it.next() orelse ""),
    };
}

fn parseFloat(str: []const u8) f32 {
    var r: f32 = 0;
    var sign: f32 = 1;
    var exp: f32 = 0;

    loop: for (0..str.len) |i| {
        switch (str[i]) {
            '+' => {},
            '-' => sign = -1,
            '.' => exp = 1,
            'e', 'E' => {
                exp = if (exp != 0) exp else 1;
                exp *= expt10(parseInt32(str[i + 1 ..]));
                break :loop;
            },
            else => {
                r = 10 * r + @as(f32, @floatFromInt(str[i] - '0'));
                exp *= 0.1;
            },
        }
    }

    return sign * r * (if (exp != 0) exp else 1);
}

fn expt10(e: i32) f32 {
    var y: f32 = 1;
    var x: f32 = if (e < 0) 0.1 else if (e > 0) 10 else 1;
    var n: i32 = if (e < 0) e else -e;

    while (n < -1) : (n = @divTrunc(n, 2)) {
        y *= if (@rem(n, 2) != 0) x else 1;
        x *= x;
    }

    return x * y;
}

fn parseInt64(str: []const u8) i64 {
    var r: u64 = 0;
    var sign: i64 = 1;

    for (str) |c| switch (c) {
        '+' => {},
        '-' => sign = -1,
        else => r = 10 * r + c - '0',
    };

    return @as(i64, @intCast(r)) * sign;
}

fn parseInt32(str: []const u8) i32 {
    var r: u32 = 0;
    var sign: i32 = 1;

    for (str) |c| switch (c) {
        '+' => {},
        '-' => sign = -1,
        else => r = 10 * r + c - '0',
    };

    return @as(i32, @intCast(r)) * sign;
}

inline fn split(buf: []const u8, s: u8) SplitIterator {
    return std.mem.splitScalar(u8, buf, s);
}

inline fn tokenize(buf: []const u8, s: u8) TokenIterator {
    return std.mem.tokenizeScalar(u8, buf, s);
}

inline fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "cross2d" {
    const pv0 = Vec2{ 0, 0 };
    const pv1 = Vec2{ 1, 0 };
    const pv2 = Vec2{ 1, 1 };

    const vec_in = pv1 - pv0;
    const vec_out = pv2 - pv1;

    const r = cross2d(vec_in, vec_out);
    try std.testing.expect(r > 0);
    try std.testing.expectEqual(1, r);
}

test "winding sum" {
    const pv0 = Vec2{ 0, 0 };
    const pv1 = Vec2{ 1, 0 };
    const pv2 = Vec2{ 1, 1 };
    const pv3 = Vec2{ 0, 1 };

    const edges = [_][2]Vec2{
        .{ pv0, pv1 },
        .{ pv1, pv2 },
        .{ pv2, pv3 },
        .{ pv3, pv0 },
    };

    var sum: f32 = 0;
    for (edges) |e| {
        const edge = (e[0][0] * e[1][1]) - (e[1][0] * e[0][1]);
        sum += edge;
    }

    try std.testing.expect(sum > 0);
    try std.testing.expectEqual(2, sum);
}

test "convex" {
    const pv0 = Vec2{ 0, 0 };
    const pv1 = Vec2{ 1, 0 };
    const pv2 = Vec2{ 1, 1 };

    const r = convex(pv0, pv1, pv2);
    try std.testing.expectEqual(true, r);
}

test "handedness normalization" {
    const v0 = Vec3{ 1, 1, -1 };
    const v1 = Vec3{ -1, 1, -1 };
    const v2 = Vec3{ -1, 1, 1 };
    const v3 = Vec3{ 1, 1, 1 };

    const face_normal_ = cross(v1 - v0, v2 - v0);
    const fn_mag_sq = dot(face_normal_, face_normal_);
    if (fn_mag_sq < GEOM_EPS * GEOM_EPS) return error.TriangulationFailed;
    const face_normal = normalize(face_normal_);

    const nx = @abs(face_normal[0]);
    const ny = @abs(face_normal[1]);
    const nz = @abs(face_normal[2]);

    const Mask = struct {
        u: usize,
        v: usize,
        s: f32,
    };

    // Third element is sign of projection
    const mask: Mask =
        if (nx >= ny and nx >= nz)
            .{ .u = 1, .v = 2, .s = if (face_normal[0] > 0) 1 else -1 }
        else if (ny >= nx and ny >= nz)
            .{ .u = 0, .v = 2, .s = if (face_normal[1] > 0) 1 else -1 }
        else
            .{ .u = 0, .v = 1, .s = if (face_normal[2] > 0) 1 else -1 };

    assert(mask.u == 0);
    assert(mask.v == 2);
    assert(mask.s == 1);

    const pv0 = Vec2{ v0[0], v0[2] };
    const pv1 = Vec2{ v1[0], v1[2] };
    const pv2 = Vec2{ v2[0], v2[2] };
    const pv3 = Vec2{ v3[0], v3[2] };

    var n0 = ProjectedVertex{ .pos = pv0, .idx = .{} };
    var n1 = ProjectedVertex{ .pos = pv1, .idx = .{} };
    var n2 = ProjectedVertex{ .pos = pv2, .idx = .{} };
    var n3 = ProjectedVertex{ .pos = pv3, .idx = .{} };

    var vertex_list = LinkedList{};
    vertex_list.append(&n0.node);
    vertex_list.append(&n1.node);
    vertex_list.append(&n2.node);
    vertex_list.append(&n3.node);

    var u_basis = Vec3{ 0, 0, 0 };
    var v_basis = Vec3{ 0, 0, 0 };
    u_basis[mask.u] = 1;
    v_basis[mask.v] = 1;

    const basis_cross = cross(u_basis, v_basis);
    const bdot = dot(basis_cross, face_normal);
    const plane_handedness_factor: f32 = if (bdot > 0) 1 else -1;

    var winding_sum: f32 = 0.0;
    var current_node = vertex_list.first;

    while (current_node) |node| {
        const pv_cur: *ProjectedVertex = @alignCast(@fieldParentPtr("node", node));
        const pv_next_node = node.next orelse vertex_list.first.?;
        const pv_next: *ProjectedVertex = @alignCast(@fieldParentPtr("node", pv_next_node));

        winding_sum += (pv_cur.pos[0] * pv_next.pos[1]) - (pv_next.pos[0] * pv_cur.pos[1]);
        current_node = node.next;
    }

    const effective_winding_sign = winding_sum * plane_handedness_factor;

    const revert = if (effective_winding_sign < -GEOM_EPS)
        true
    else if (effective_winding_sign > GEOM_EPS)
        false
    else {
        return error.NearZeroWindingSumDegenerate;
    };

    try std.testing.expectEqual(Vec3{ 0, 1, 0 }, face_normal);
    try std.testing.expectEqual(Mask{ .u = 0, .v = 2, .s = 1 }, mask);
    try std.testing.expectEqual(Vec2{ 1, -1 }, pv0);
    try std.testing.expectEqual(Vec2{ -1, -1 }, pv1);
    try std.testing.expectEqual(Vec2{ -1, 1 }, pv2);
    try std.testing.expectEqual(Vec2{ 1, 1 }, pv3);
    try std.testing.expectEqual(Vec3{ 1, 0, 0 }, u_basis);
    try std.testing.expectEqual(Vec3{ 0, 0, 1 }, v_basis);
    try std.testing.expectEqual(Vec3{ 0, -1, 0 }, basis_cross);
    try std.testing.expectEqual(-1, bdot);
    try std.testing.expectEqual(-8, winding_sum);
    try std.testing.expectEqual(-1, plane_handedness_factor);
    try std.testing.expectEqual(8, effective_winding_sign);
    try std.testing.expectEqual(false, revert);
}
