const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.obj_parser);
const gfx = @import("gfx.zig");
const math = @import("math.zig");
const mem = @import("memory.zig");

const Allocator = std.mem.Allocator;
const LinkedList = std.DoublyLinkedList;
const SplitIterator = std.mem.SplitIterator(u8, .scalar);
const TokenIterator = std.mem.TokenIterator(u8, .scalar);
const Arena = mem.Arena;
const TempArena = mem.TempArena;
const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);

const assert = std.debug.assert;
inline fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
inline fn parseFloat(str: []const u8) !f32 {
    return std.fmt.parseFloat(f32, str);
}
inline fn parseInt(comptime T: type, str: []const u8) !T {
    if (str.len == 0) return 0;
    return std.fmt.parseInt(T, str, 10);
}

const GEOM_EPS = 1e-6;

pub const ObjParseError = error{
    InvalidCharacter,
    InvalidIndex,
    OutOfMemory,
    Overflow,
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

pub fn parse(allocator: Allocator, options: ParseOptions) ObjParseError!Model {
    const buffer = options.buffer;

    var num_objects: usize = 0;
    var num_verts: u32 = 0;
    var num_normals: u32 = 0;
    var num_texcoords: u32 = 0;
    var num_indices: usize = 0;
    var num_faces: usize = 0;
    var need_triangulation = false;

    var line_it = std.mem.tokenizeScalar(u8, buffer, '\n');
    var line_num: usize = 1;

    while (line_it.next()) |line_maybe_clrf| : (line_num += 1) {
        errdefer err("{s}:{}: Invalid line: '{s}'", .{ options.name, line_num, line_maybe_clrf });

        const line = stripRight(line_maybe_clrf);

        var field_it = std.mem.tokenizeScalar(u8, line, ' ');
        const field = field_it.next() orelse continue;

        if (eq(field, "v")) {
            num_verts += 1;
        } else if (eq(field, "vn")) {
            num_normals += 1;
        } else if (eq(field, "vt")) {
            num_texcoords += 1;
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
            log.warn("{s}:{}: Skipping invalid line: '{s}'", .{ options.name, line_num, line });
            // ok, skip
        }
    }

    var parse_vector_fn = &parseVector;

    var ta = mem.get_scratch(@ptrCast(@alignCast(allocator.ptr)));
    defer ta.release();
    const face_alloc = if (need_triangulation) ta.allocator() else allocator;

    var result = Model{
        .vertices = try allocator.alloc(Vec3, num_verts),
        .normals = try allocator.alloc(Vec3, num_normals),
        .texcoords = try allocator.alloc(Vec2, num_texcoords),
        .objects = try allocator.alloc(Object, num_objects),
        .colors = blk: {
            if (options.flags.vertex_colors) {
                parse_vector_fn = parseVectorAndColor;
                break :blk try allocator.alloc(Vec3, num_verts);
            } else break :blk &.{};
        },
        .faces = try face_alloc.alloc(Face, num_faces),
        .indices = try face_alloc.alloc(Index, num_indices),
    };

    var vertices = std.ArrayListUnmanaged(Vec3).initBuffer(@constCast(result.vertices));
    var normals = std.ArrayListUnmanaged(Vec3).initBuffer(@constCast(result.normals));
    var texcoords = std.ArrayListUnmanaged(Vec2).initBuffer(@constCast(result.texcoords));
    var objects = std.ArrayListUnmanaged(Object).initBuffer(@constCast(result.objects));
    var colors = std.ArrayListUnmanaged(Vec3).initBuffer(@constCast(result.colors));
    var faces = std.ArrayListUnmanaged(Face).initBuffer(@constCast(result.faces));
    var indices = std.ArrayListUnmanaged(Index).initBuffer(@constCast(result.indices));

    var current_object: ?*Object = null;
    var obj_face_offset: usize = 0;

    line_it = std.mem.tokenizeScalar(u8, buffer, '\n');
    line_num = 1;
    while (line_it.next()) |line_maybe_clrf| : (line_num += 1) {
        errdefer err("{s}:{}: Invalid line: '{s}'", .{ options.name, line_num, line_maybe_clrf });

        const line = stripRight(line_maybe_clrf);

        var field_it = std.mem.tokenizeScalar(u8, line, ' ');
        const field = field_it.next() orelse continue;

        if (eq(field, "v")) {
            try parse_vector_fn(&field_it, &vertices, &colors);
        } else if (eq(field, "vn")) {
            normals.appendAssumeCapacity(try parseVec3(&field_it));
        } else if (eq(field, "vt")) {
            texcoords.appendAssumeCapacity(try parseVec2(&field_it));
        } else if (eq(field, "f")) {
            const face = try parseFace(field_it.rest(), @intCast(vertices.items.len), num_texcoords, @intCast(normals.items.len), &indices);
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
            // ok, skip
            log.warn("{s}:{}: Skipping invalid line: '{s}'", .{ options.name, line_num, line });
        }
    }
    if (current_object) |obj| {
        obj.faces = faces.items[obj_face_offset..faces.items.len];
    }

    assert(vertices.items.len == num_verts);
    if (options.flags.vertex_colors) assert(colors.items.len <= num_verts);
    assert(texcoords.items.len == num_texcoords);
    assert(normals.items.len == num_normals);
    assert(indices.items.len == num_indices);
    assert(faces.items.len == num_faces);
    assert(objects.items.len == num_objects);

    if (need_triangulation) {
        try triangulate(&result, allocator, ta);
    }

    if (faces.items.len == 0) {
        log.warn("{s}: Empty file? (no faces encountered)", .{options.name});
    }

    return result;
}

fn findFaceIndexCount(str: []const u8) usize {
    var index_it = std.mem.tokenizeScalar(u8, str, ' ');
    var r: usize = 0;
    while (index_it.next()) |f| {
        if (f[0] == '#') break;
        r += 1;
    }
    return r;
}

fn parseFace(str: []const u8, num_verts: u32, num_texcoords: u32, num_normals: u32, indices: *std.ArrayListUnmanaged(Index)) !Face {
    var r = Face{};
    var index_it = std.mem.tokenizeScalar(u8, str, ' ');

    const start_idx = indices.items.len;

    while (index_it.next()) |fields| {
        if (fields[0] == '#') {
            break;
        }

        var field_it = std.mem.splitScalar(u8, fields, '/');
        const vertex = try parseInt(i64, field_it.next() orelse "") - 1;
        const texcoord = try parseInt(i64, field_it.next() orelse "") - 1;
        const normal = try parseInt(i64, field_it.next() orelse "") - 1;

        if (vertex >= num_verts) {
            err("Invalid vertex index: {}", .{vertex + 1});
            return error.InvalidIndex;
        }
        if (texcoord >= num_texcoords) {
            err("Invalid texcoord index: {}", .{texcoord + 1});
            return error.InvalidIndex;
        }
        if (normal >= num_normals) {
            err("Invalid normal index: {}", .{normal + 1});
            return error.InvalidIndex;
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

fn parseVector(field_it: *TokenIterator, vertices: *std.ArrayListUnmanaged(Vec3), colors: *std.ArrayListUnmanaged(Vec3)) !void {
    _ = colors;
    vertices.appendAssumeCapacity(try parseVec3(field_it));
}

fn parseVectorAndColor(field_it: *TokenIterator, vertices: *std.ArrayListUnmanaged(Vec3), colors: *std.ArrayListUnmanaged(Vec3)) !void {
    vertices.appendAssumeCapacity(try parseVec3(field_it));

    if (field_it.peek()) |n| {
        if (!std.mem.startsWith(u8, n, "#")) {
            colors.appendAssumeCapacity(if (field_it.rest().len == 0) .{ 1, 1, 1 } else try parseVec3(field_it));
        }
    }
}

inline fn parseVec3(field_it: *TokenIterator) !Vec3 {
    return .{
        try parseFloat(field_it.next() orelse ""),
        try parseFloat(field_it.next() orelse ""),
        try parseFloat(field_it.next() orelse ""),
    };
}

inline fn parseVec2(field_it: *TokenIterator) !Vec2 {
    return .{
        try parseFloat(field_it.next() orelse ""),
        try parseFloat(field_it.next() orelse ""),
    };
}

inline fn stripRight(str: []const u8) []const u8 {
    var end = str.len;

    var i = str.len;
    while (i > 0) {
        i -= 1;

        if (!std.ascii.isWhitespace(str[i])) {
            break;
        }

        end -= 1;
    }

    return str[0..end];
}

const ProjectedVertex = struct {
    pos: Vec2,
    idx: Index,
    node: LinkedList.Node = .{},
};

fn triangulate(model: *Model, allocator: Allocator, temp: TempArena) !void {
    var triangle_face_count: usize = 0;
    for (model.faces) |face| {
        assert(face.indices.len >= 3);
        triangle_face_count += face.indices.len - 2;
    }

    var fta = TempArena.init(temp.arena);

    var new_faces = try std.ArrayListUnmanaged(Face).initCapacity(allocator, triangle_face_count);
    var new_indices = try std.ArrayListUnmanaged(Index).initCapacity(allocator, triangle_face_count * 3);

    for (model.faces, 0..) |face, fi| {
        assert(face.indices.len >= 3);

        // Calculate face normal
        var normal_sum = Vec3{ 0, 0, 0 };
        for (0..face.indices.len) |i| {
            const p_cur_idx = face.indices[i].vertex;
            const p_next_idx = face.indices[(i + 1) % face.indices.len].vertex;

            const p_cur = model.vertices[p_cur_idx];
            const p_next = model.vertices[p_next_idx];

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
        };

        // Selection mask for 3d->2d based on face normal
        const mask: Mask =
            if (nx >= ny and nx >= nz)
                .{ .u = 1, .v = 2 }
            else if (ny >= nx and ny >= nz)
                .{ .u = 0, .v = 2 }
            else
                .{ .u = 0, .v = 1 };

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

        // Project 3d vertices to 2d using mask
        for (face.indices, projected_vertices_mem) |idx, *pv| {
            const v = model.vertices[idx.vertex];
            const p: Vec2 = .{ v[mask.u], v[mask.v] };

            pv.* = .{ .pos = p, .idx = idx };

            // TODO: Don't append duplicates
            // TODO: Remove collinear intermidate vertices
            vertex_list.append(&pv.node);
        }

        // The 2d projection might cause the winding order to change, revert the order of the projection in this case
        const winding_sum = shoelaceSum(vertex_list);
        const ccw = if (winding_sum > GEOM_EPS)
            true
        else if (winding_sum < -GEOM_EPS)
            false
        else {
            log.warn("Face {} has a near-zero effective winding sum. Skipping triangulation (likely degenerate).", .{fi});
            continue;
        };

        var num_vertices = face.indices.len;
        var it = if (ccw) vertex_list.first else vertex_list.last;

        clip_loop: while (num_vertices > 3) {
            const node = it.?;
            // const prev: *ProjectedVertex = @alignCast(@fieldParentPtr("node", if (ccw) node.prev orelse vertex_list.last.? else node.next orelse vertex_list.first.?));
            // const cur: *ProjectedVertex = @alignCast(@fieldParentPtr("node", node));
            // const next: *ProjectedVertex = @alignCast(@fieldParentPtr("node", if (ccw) node.next orelse vertex_list.first.? else node.prev orelse vertex_list.last.?));

            var prev: *ProjectedVertex = @alignCast(@fieldParentPtr("node", node.prev orelse vertex_list.last.?));
            const cur: *ProjectedVertex = @alignCast(@fieldParentPtr("node", node));
            var next: *ProjectedVertex = @alignCast(@fieldParentPtr("node", node.next orelse vertex_list.first.?));
            if (!ccw) {
                const tmp = prev;
                prev = next;
                next = tmp;
            }

            if (!convex(prev.pos, cur.pos, next.pos)) {
                it = if (ccw) node.next orelse vertex_list.first else node.prev orelse vertex_list.last;
                continue;
            }

            var c_it = if (ccw) next.node.next orelse vertex_list.first else next.node.prev orelse vertex_list.last;
            while (c_it) |c_node| {
                if (c_node == &prev.node) break;

                const c: *ProjectedVertex = @alignCast(@fieldParentPtr("node", c_node));

                if (inTriangle(c.pos, prev.pos, cur.pos, next.pos)) {
                    it = if (ccw) node.next orelse vertex_list.first else node.prev orelse vertex_list.last;
                    continue :clip_loop;
                }

                c_it = if (ccw) c_node.next orelse vertex_list.first else c_node.prev orelse vertex_list.last;
            }

            // Found ear
            const new_triangle: [3]Index = if (plane_handedness_factor > 0)
                .{ prev.idx, cur.idx, next.idx }
            else
                .{ prev.idx, next.idx, cur.idx };

            const start_idx = new_indices.items.len;
            new_indices.appendSliceAssumeCapacity(&new_triangle);
            new_faces.appendAssumeCapacity(.{ .indices = new_indices.items[start_idx .. start_idx + 3] });

            it = if (ccw) &next.node else &prev.node;
            vertex_list.remove(&cur.node);

            num_vertices -= 1;
        }

        assert(num_vertices == 3);
        var n0: *LinkedList.Node = undefined;
        var n1: *LinkedList.Node = undefined;
        var n2: *LinkedList.Node = undefined;

        if (ccw) {
            n0 = vertex_list.first.?;
            n1 = n0.next.?;
            n2 = n1.next.?;
            assert(n1.next == n2);
        } else {
            n0 = vertex_list.last.?;
            n1 = n0.prev.?;
            n2 = n1.prev.?;
            assert(n1.prev == n2);
        }
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

    model.indices = try new_indices.toOwnedSlice(allocator);
    model.faces = try new_faces.toOwnedSlice(allocator);
}

/// Calculates the winding sum (or signed area) times two
inline fn shoelaceSum(vertices: LinkedList) f32 {
    var shoelace_sum: f32 = 0.0;
    var current_node = vertices.first;

    while (current_node) |node| {
        const pv_cur: *ProjectedVertex = @alignCast(@fieldParentPtr("node", node));
        const pv_next_node = node.next orelse vertices.first.?;
        const pv_next: *ProjectedVertex = @alignCast(@fieldParentPtr("node", pv_next_node));

        shoelace_sum += (pv_cur.pos[0] * pv_next.pos[1]) - (pv_next.pos[0] * pv_cur.pos[1]);
        current_node = node.next;
    }

    return shoelace_sum;
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

test "shoelace sum" {
    const pv0 = Vec2{ 0, 0 };
    const pv1 = Vec2{ 1, 0 };
    const pv2 = Vec2{ 1, 1 };
    const pv3 = Vec2{ 0, 1 };

    var n0 = ProjectedVertex{ .pos = pv0, .idx = .{} };
    var n1 = ProjectedVertex{ .pos = pv1, .idx = .{} };
    var n2 = ProjectedVertex{ .pos = pv2, .idx = .{} };
    var n3 = ProjectedVertex{ .pos = pv3, .idx = .{} };

    var list = LinkedList{};
    list.append(&n0.node);
    list.append(&n1.node);
    list.append(&n2.node);
    list.append(&n3.node);

    const sum = shoelaceSum(list);

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

    var normal_sum = Vec3{ 0, 0, 0 };
    const vertices_array = [_]Vec3{ v0, v1, v2, v3 };
    for (0..vertices_array.len) |i| {
        const p_cur = vertices_array[i];
        const p_next = vertices_array[(i + 1) % vertices_array.len];

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
    };

    const mask: Mask =
        if (nx >= ny and nx >= nz)
            .{ .u = 1, .v = 2 }
        else if (ny >= nx and ny >= nz)
            .{ .u = 0, .v = 2 }
        else
            .{ .u = 0, .v = 1 };

    assert(mask.u == 0);
    assert(mask.v == 2);

    var u_basis = Vec3{ 0, 0, 0 };
    var v_basis = Vec3{ 0, 0, 0 };
    u_basis[mask.u] = 1;
    v_basis[mask.v] = 1;

    const basis_cross = cross(u_basis, v_basis);
    const bdot = dot(basis_cross, face_normal);
    const plane_handedness_factor: f32 = if (bdot > 0) 1 else -1;

    const pv0 = Vec2{ v0[mask.u], v0[mask.v] };
    const pv1 = Vec2{ v1[mask.u], v1[mask.v] };
    const pv2 = Vec2{ v2[mask.u], v2[mask.v] };
    const pv3 = Vec2{ v3[mask.u], v3[mask.v] };

    var n0 = ProjectedVertex{ .pos = pv0, .idx = .{} };
    var n1 = ProjectedVertex{ .pos = pv1, .idx = .{} };
    var n2 = ProjectedVertex{ .pos = pv2, .idx = .{} };
    var n3 = ProjectedVertex{ .pos = pv3, .idx = .{} };

    var vertex_list = LinkedList{};
    vertex_list.append(&n0.node);
    vertex_list.append(&n1.node);
    vertex_list.append(&n2.node);
    vertex_list.append(&n3.node);

    const winding_sum = shoelaceSum(vertex_list);
    const effective_winding_sign = winding_sum * plane_handedness_factor;

    const revert = if (effective_winding_sign < -GEOM_EPS)
        true
    else if (effective_winding_sign > GEOM_EPS)
        false
    else {
        return error.NearZeroWindingSumDegenerate;
    };

    try std.testing.expectEqual(Vec3{ 0, 1, 0 }, face_normal);
    try std.testing.expectEqual(Mask{ .u = 0, .v = 2 }, mask);
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

/// Use this so tests don't 'fail'(?) when they expect an error, but an error message is also logged.
fn err(comptime fmt: []const u8, args: anytype) void {
    if (builtin.is_test) {
        log.warn(fmt, args);
    } else {
        log.err(fmt, args);
    }
}

test "empty buffer" {
    mem.initTemp();
    defer mem.deinitTemp();

    var ta = mem.get_temp();

    const result: Model = try parse(ta.allocator(), .{ .buffer = "", .name = "testbuffer" });

    try std.testing.expectEqual(0, result.vertices.len);
    try std.testing.expectEqual(0, result.colors.len);
    try std.testing.expectEqual(0, result.normals.len);
    try std.testing.expectEqual(0, result.texcoords.len);
    try std.testing.expectEqual(0, result.indices.len);
    try std.testing.expectEqual(0, result.faces.len);
    try std.testing.expectEqual(0, result.objects.len);
}

test "invalid float" {
    // TODO:[test_temp_alloc_init] Can we do this in the runner?
    mem.initTemp();
    defer mem.deinitTemp();

    var ta = mem.get_temp();

    const result = parse(ta.allocator(), .{ .buffer = "o test \nv 1.0 xxx 1.0", .name = "testbuffer" });

    try std.testing.expectError(error.InvalidCharacter, result);
}

test "parse (semantic comparison)" {
    // todo:[test_temp_alloc_init] Can we do this in the runner?
    mem.initTemp();
    defer mem.deinitTemp();

    const ExpectedModelData = struct {
        vertex_count: usize,
        normal_count: usize,
        texcoord_count: usize,
        face_count: usize,
        object_count: usize,
    };

    const test_path = "res/test_obj";

    const expected_data = struct {
        pub const cube_t = ExpectedModelData{ .vertex_count = 8, .normal_count = 6, .texcoord_count = 14, .face_count = 12, .object_count = 1 };
        pub const concave_pentagon_t = ExpectedModelData{ .vertex_count = 5, .normal_count = 1, .texcoord_count = 0, .face_count = 3, .object_count = 1 };
        pub const funky_plane_3d_t = ExpectedModelData{ .vertex_count = 20, .normal_count = 18, .texcoord_count = 10, .face_count = 36, .object_count = 1 };
        pub const concave_quad_t = ExpectedModelData{ .vertex_count = 4, .normal_count = 1, .texcoord_count = 0, .face_count = 2, .object_count = 1 };
        pub const projection_winding_flip_t = ExpectedModelData{ .vertex_count = 4, .normal_count = 1, .texcoord_count = 0, .face_count = 2, .object_count = 1 };
        pub const collinear_t = ExpectedModelData{ .vertex_count = 6, .normal_count = 1, .texcoord_count = 0, .face_count = 4, .object_count = 1 };
        pub const funky_plane_t = ExpectedModelData{ .vertex_count = 10, .normal_count = 1, .texcoord_count = 10, .face_count = 8, .object_count = 1 };
        pub const c_t = ExpectedModelData{ .vertex_count = 8, .normal_count = 1, .texcoord_count = 0, .face_count = 6, .object_count = 1 };
        pub const triangle_t = ExpectedModelData{ .vertex_count = 3, .normal_count = 1, .texcoord_count = 1, .face_count = 1, .object_count = 1 };
        pub const arrow_t = ExpectedModelData{ .vertex_count = 25, .normal_count = 12, .texcoord_count = 34, .face_count = 46, .object_count = 1 };
    };

    const tests = blk: {
        const info = @typeInfo(expected_data);
        assert(info == .@"struct");

        var result: [info.@"struct".decls.len]struct {
            file_path: []const u8,
            content: []const u8,
            expected: ExpectedModelData,
        } = undefined;

        inline for (info.@"struct".decls, &result) |decl, *r| {
            assert(!std.mem.endsWith(u8, decl.name, ".obj"));

            const file_name = std.fmt.comptimePrint("{s}.obj", .{decl.name});
            const file_path = std.fmt.comptimePrint("{s}{c}{s}", .{ test_path, std.fs.path.sep, file_name });
            r.* = .{
                .file_path = file_path,
                .content = @embedFile(file_path),
                .expected = @field(expected_data, decl.name),
            };
        }

        break :blk result;
    };

    var ta = mem.get_temp();
    defer ta.release();

    for (tests) |t| {
        log.debug("testing: {s}:", .{t.file_path});

        const model = try parse(ta.allocator(), .{ .name = t.file_path, .buffer = t.content });

        try std.testing.expectEqual(t.expected.vertex_count, model.vertices.len);
        try std.testing.expectEqual(t.expected.normal_count, model.normals.len);
        try std.testing.expectEqual(t.expected.texcoord_count, model.texcoords.len);
        try std.testing.expectEqual(t.expected.face_count, model.faces.len);
        try std.testing.expectEqual(t.expected.object_count, model.objects.len);
    }
}
