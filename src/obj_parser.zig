const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.obj_parser);
const mem = @import("memory");
const math = @import("math.zig");

const Allocator = std.mem.Allocator;
const TokenIterator = std.mem.TokenIterator(u8, .scalar);
const TempArena = mem.TempArena;
const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);

const geo_eps = math.GeometricEpsilon;

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

const ProjectedVertex = struct {
    pos: Vec2,
    idx: Index,
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

pub const ObjParseError = error{
    InvalidIndex,
    TriangulationFailed,
} ||
    std.mem.Allocator.Error ||
    std.fmt.ParseIntError ||
    ParseVectorError;

pub const ParseVectorError = error{InvalidColor} || std.fmt.ParseFloatError;

const ModelBuilder = struct {
    vertices: []Vec3,
    colors: []Vec3,
    normals: []Vec3,
    texcoords: []@Vector(2, f32),
    indices: []Index = &.{},
    faces: []Face = &.{},
    objects: []Object = &.{},
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

            if (num_objects < 1) {
                num_objects += 1;
            }
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

    var ta = mem.get_scratch(@ptrCast(@alignCast(allocator.ptr)));
    defer ta.release();
    const face_alloc = if (need_triangulation) ta.allocator() else allocator;

    var result = ModelBuilder{
        .vertices = try allocator.alloc(Vec3, num_verts),
        .normals = try allocator.alloc(Vec3, num_normals),
        .texcoords = try allocator.alloc(Vec2, num_texcoords),
        .objects = try allocator.alloc(Object, num_objects),
        .colors = blk: {
            if (options.flags.vertex_colors) {
                break :blk try allocator.alloc(Vec3, num_verts);
            } else break :blk &.{};
        },
        .faces = try face_alloc.alloc(Face, num_faces),
        .indices = try face_alloc.alloc(Index, num_indices),
    };

    var vertices = std.ArrayListUnmanaged(Vec3).initBuffer(result.vertices);
    var normals = std.ArrayListUnmanaged(Vec3).initBuffer(result.normals);
    var texcoords = std.ArrayListUnmanaged(Vec2).initBuffer(result.texcoords);
    var objects = std.ArrayListUnmanaged(Object).initBuffer(result.objects);
    var colors_ = std.ArrayListUnmanaged(Vec3).initBuffer(@constCast(result.colors));
    const colors: ?*@TypeOf(colors_) = if (options.flags.vertex_colors) &colors_ else null;
    var faces = std.ArrayListUnmanaged(Face).initBuffer(result.faces);
    var indices = std.ArrayListUnmanaged(Index).initBuffer(result.indices);

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
            try parseVectorAndOptionalColor(&field_it, &vertices, colors);
        } else if (eq(field, "vn")) {
            normals.appendAssumeCapacity(try parseVec3(&field_it));
        } else if (eq(field, "vt")) {
            texcoords.appendAssumeCapacity(try parseVec2(&field_it));
        } else if (eq(field, "f")) {
            const face = try parseFace(field_it.rest(), @intCast(vertices.items.len), num_texcoords, @intCast(normals.items.len), &indices);
            faces.appendAssumeCapacity(face);

            if (current_object == null) {
                const implicit_obj = objects.addOneAssumeCapacity();
                implicit_obj.* = .{};
                current_object = implicit_obj;
            }
        } else if (eq(field, "o")) {
            if (current_object) |obj| {
                obj.faces = faces.items[obj_face_offset..];
            }
            obj_face_offset = faces.items.len;

            const obj = objects.addOneAssumeCapacity();
            obj.name = try allocCopy(u8, allocator, field_it.rest());
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
        obj.faces = faces.items[obj_face_offset..];
    }

    assert(vertices.items.len == num_verts);
    if (options.flags.vertex_colors) assert(colors.?.items.len == num_verts);
    assert(texcoords.items.len == num_texcoords);
    assert(normals.items.len == num_normals);
    assert(indices.items.len == num_indices);
    assert(faces.items.len == num_faces);
    assert(objects.items.len == num_objects);

    if (need_triangulation) {
        try earclip(&result, allocator, ta);
    }

    if (faces.items.len == 0) {
        log.warn("{s}: Empty file? (no faces encountered)", .{options.name});
    }

    return .{
        .vertices = result.vertices,
        .colors = result.colors,
        .normals = result.normals,
        .texcoords = result.texcoords,
        .indices = result.indices,
        .faces = result.faces,
        .objects = result.objects,
    };
}

inline fn allocCopy(comptime T: type, allocator: Allocator, data: []const T) ![]const T {
    const result = try allocator.alloc(T, data.len);
    @memcpy(result, data);
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

inline fn parseVectorAndOptionalColor(field_it: *TokenIterator, vertices: *std.ArrayListUnmanaged(Vec3), colors_opt: ?*std.ArrayListUnmanaged(Vec3)) ParseVectorError!void {
    vertices.appendAssumeCapacity(try parseVec3(field_it));

    if (colors_opt) |colors| {
        const white = Vec3{ 1, 1, 1 };
        const color = blk: {
            const rest = stripRight(field_it.rest());
            if (rest.len > 0 and !std.mem.startsWith(u8, rest, "#")) {
                if (rest.len < 5) return error.InvalidColor;
                break :blk parseVec3(field_it) catch return error.InvalidColor;
            } else break :blk white;
        };

        colors.appendAssumeCapacity(color);
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

/// Triangulates concave faces in the model using ear clipping algorithm.
/// Handles 3D faces by projecting them onto their dominant plane.
/// Does not support polygons with holes or self-intersections.
///
/// Process:
/// 1. Project 3D face onto 2D plane using face normal
/// 2. Remove duplicate/collinear vertices
/// 3. Find and clip "ears" (convex triangles) until only one triangle remains
///
/// Arguments:
///  - model: Input model to triangulate
///  - allocator: For final triangulated mesh storage
///  - temp: Temporary arena for working data
fn earclip(model: *ModelBuilder, allocator: Allocator, temp: TempArena) !void {
    var triangle_face_count: usize = 0;
    for (model.faces, 0..) |face, i| {
        if (face.indices.len < 3) {
            log.warn("Skipping degenerate face (index): {}", .{i});
            continue;
        }
        triangle_face_count += face.indices.len - 2;
    }

    var fta = TempArena.init(temp.arena);

    const faces_ = try allocator.alloc(Face, triangle_face_count);
    const indices_ = try allocator.alloc(Index, triangle_face_count * 3);
    var new_faces = std.ArrayListUnmanaged(Face).initBuffer(faces_);
    var new_indices = std.ArrayListUnmanaged(Index).initBuffer(indices_);

    for (model.objects) |*obj| {
        const new_first_face = new_faces.items.len;

        for (obj.faces, 0..) |face, fi| {
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
            if (fn_mag_sq < geo_eps * geo_eps) return error.TriangulationFailed;
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
            const projected_vertices = try fta.allocator().alloc(ProjectedVertex, face.indices.len);
            var rem_idx = try std.ArrayListUnmanaged(u32).initCapacity(fta.allocator(), face.indices.len);

            // Project 3d vertices to 2d using mask
            // Project the first 3d vertex to 2d
            const first_idx = face.indices[0];
            const first_v = model.vertices[first_idx.vertex];
            const first_pv = &projected_vertices[0];
            first_pv.* = .{
                .pos = .{ first_v[mask.u], first_v[mask.v] },
                .idx = first_idx,
            };
            rem_idx.appendAssumeCapacity(0);

            // Remaining vertices, check for duplicates
            for (face.indices[1..]) |idx| {
                const pv = &projected_vertices[rem_idx.items.len];
                const v = model.vertices[idx.vertex];
                const p: Vec2 = .{ v[mask.u], v[mask.v] };

                // const last: *ProjectedVertex = @alignCast(@fieldParentPtr("node", vertex_list.last.?));
                const last = &projected_vertices[rem_idx.items[rem_idx.items.len - 1]];

                // Compare square distance to avoid duplicates
                const diff = p - last.pos;
                if (dot(diff, diff) >= geo_eps * geo_eps) {

                    // If collinear, 'replace' the last point with the current one
                    const add: bool = add_blk: {
                        if (rem_idx.items.len > 1) {
                            const second_to_last = &projected_vertices[rem_idx.items[rem_idx.items.len - 2]];
                            if (collinear(second_to_last.pos, last.pos, p)) {
                                last.pos = p;
                                last.idx = idx;
                                triangle_face_count -= 1;
                                break :add_blk false;
                            }
                        }
                        break :add_blk true;
                    };

                    if (add) {
                        pv.* = .{ .pos = p, .idx = idx };
                        rem_idx.appendAssumeCapacity(@intCast(rem_idx.items.len));
                    }
                }
            }

            if (rem_idx.items.len < 3) {
                log.warn("Skipping degenerate face after projection (index): {}", .{fi});
                continue;
            }
            { // check (last-1), last, first for collinearity
                const l = &projected_vertices[rem_idx.items[rem_idx.items.len - 1]];
                const ll = &projected_vertices[rem_idx.items[rem_idx.items.len - 2]];
                const f = &projected_vertices[rem_idx.items[0]];
                if (collinear(ll.pos, l.pos, f.pos)) {
                    _ = rem_idx.orderedRemove(rem_idx.items.len - 1);
                    triangle_face_count -= 1;
                }
            }
            if (rem_idx.items.len < 3) {
                log.warn("Skipping degenerate face after projection (index): {}", .{fi});
                continue;
            }
            { // check last, first, second for collinearity
                const l = &projected_vertices[rem_idx.items[rem_idx.items.len - 1]];
                const f = &projected_vertices[rem_idx.items[0]];
                const s = &projected_vertices[rem_idx.items[1]];
                if (collinear(l.pos, f.pos, s.pos)) {
                    _ = rem_idx.orderedRemove(0);
                    triangle_face_count -= 1;
                }
            }

            // Remove last if duplicate of first
            const first = &projected_vertices[rem_idx.items[0]];
            const last = &projected_vertices[rem_idx.items[rem_idx.items.len - 1]];
            const diff = first.pos - last.pos;
            if (dot(diff, diff) < geo_eps * geo_eps) {
                _ = rem_idx.orderedRemove(rem_idx.items.len - 1);
                triangle_face_count -= 1;
            }
            if (rem_idx.items.len < 3) {
                log.warn("Skipping degenerate face after projection (index): {}", .{fi});
                continue;
            }

            // The 2d projection might cause the winding order to change, revert the order of the projection in this case
            // projected_vertices = projected_vertices[rem_idx.items[0] .. rem_idx.items[0] + rem_idx.items.len];
            const winding_sum = shoelaceSum(projected_vertices[rem_idx.items[0] .. rem_idx.items[0] + rem_idx.items.len]);

            const ccw = if (winding_sum > geo_eps)
                true
            else if (winding_sum < -geo_eps)
                false
            else {
                log.warn("Face {} has a near-zero effective winding sum. Skipping triangulation (likely degenerate).", .{fi});
                continue;
            };

            var i: usize = if (ccw) 0 else rem_idx.items.len - 1;

            clip_loop: while (rem_idx.items.len > 3) {
                var prev_idx = if (i == 0) rem_idx.items.len - 1 else i - 1;
                var next_idx = if (i == rem_idx.items.len - 1) 0 else i + 1;
                if (!ccw) {
                    const tmp = prev_idx;
                    prev_idx = next_idx;
                    next_idx = tmp;
                }
                const prev = &projected_vertices[rem_idx.items[prev_idx]];
                const cur = &projected_vertices[rem_idx.items[i]];
                const next = &projected_vertices[rem_idx.items[next_idx]];

                // Edges for convex and same-side triangle test
                const ab = cur.pos - prev.pos;
                const bc = next.pos - cur.pos;
                const ca = prev.pos - next.pos;

                // Convex check
                const double_signed_area = cross2d(ab, bc);
                if (double_signed_area <= -geo_eps) {
                    i = if (ccw) next_idx else prev_idx;
                    continue;
                }

                // Triangle check
                var ci: usize = 0;
                var points_to_check = rem_idx.items.len - 3;
                while (points_to_check > 0) : (ci += 1) {
                    if (ci == prev_idx or ci == i or ci == next_idx) continue;
                    points_to_check -= 1;

                    const c = projected_vertices[rem_idx.items[ci]];
                    const ap = c.pos - prev.pos;
                    const bp = c.pos - cur.pos;
                    const cp = c.pos - next.pos;

                    if (cross2d(ab, ap) > geo_eps and
                        cross2d(bc, bp) > geo_eps and
                        cross2d(ca, cp) > geo_eps)
                    {
                        // Collision!
                        i = if (ccw) next_idx else prev_idx;
                        continue :clip_loop;
                    }
                }

                // Found ear
                const new_triangle: [3]Index = if (plane_handedness_factor > 0)
                    .{ prev.idx, cur.idx, next.idx }
                else
                    .{ prev.idx, next.idx, cur.idx };

                const start_idx = new_indices.items.len;
                new_indices.appendSliceAssumeCapacity(&new_triangle);
                new_faces.appendAssumeCapacity(.{ .indices = new_indices.items[start_idx .. start_idx + 3] });

                _ = rem_idx.orderedRemove(i);
                if (i >= rem_idx.items.len) {
                    i = if (ccw) 0 else rem_idx.items.len - 1;
                }
            }

            assert(rem_idx.items.len == 3);
            var lv0: *ProjectedVertex = undefined;
            var lv1: *ProjectedVertex = undefined;
            var lv2: *ProjectedVertex = undefined;

            if (ccw) {
                lv0 = &projected_vertices[rem_idx.items[0]];
                lv1 = &projected_vertices[rem_idx.items[1]];
                lv2 = &projected_vertices[rem_idx.items[2]];
            } else {
                lv0 = &projected_vertices[rem_idx.items[2]];
                lv1 = &projected_vertices[rem_idx.items[1]];
                lv2 = &projected_vertices[rem_idx.items[0]];
            }
            const last_triangle: [3]Index = if (plane_handedness_factor > 0)
                .{ lv0.idx, lv1.idx, lv2.idx }
            else
                .{ lv0.idx, lv2.idx, lv1.idx };

            const start_idx = new_indices.items.len;
            new_indices.appendSliceAssumeCapacity(&last_triangle);
            new_faces.appendAssumeCapacity(.{ .indices = new_indices.items[start_idx .. start_idx + 3] });
        }

        obj.faces = new_faces.items[new_first_face..];
    }

    assert(triangle_face_count == new_faces.items.len);
    assert(triangle_face_count * 3 == new_indices.items.len);

    model.indices = new_indices.items;
    model.faces = new_faces.items;
}

/// Calculates signed area of polygon using shoelace formula.
/// Positive result means counter-clockwise winding.
/// Result is twice the actual area.
inline fn shoelaceSum(vertices: []const ProjectedVertex) f32 {
    assert(vertices.len >= 3);

    var shoelace_sum: f32 = 0.0;

    for (vertices, 0..) |cur, i| {
        const next = vertices[if (i >= vertices.len - 1) 0 else i + 1];

        shoelace_sum += cross2d(cur.pos, next.pos);
    }

    return shoelace_sum;
}

/// Test if point is inside triangle using signed areas.
/// Uses geometric epsilon for robust comparisons.
/// Returns true if point is strictly inside the triangle.
inline fn inTriangle(p: Vec2, ta: Vec2, tb: Vec2, tc: Vec2) bool {
    const ab = tb - ta;
    const bc = tc - tb;
    const ca = ta - tc;
    const ap = p - ta;
    const bp = p - tb;
    const cp = p - tc;

    const c1 = cross2d(ab, ap);
    const c2 = cross2d(bc, bp);
    const c3 = cross2d(ca, cp);

    return c1 > geo_eps and c2 > geo_eps and c3 > geo_eps;
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

/// Tests if three 2D points are collinear within geometric epsilon.
/// Uses signed area of the triangle formed by the points.
/// Returns true if points are effectively collinear.
inline fn collinear(a: Vec2, b: Vec2, c: Vec2) bool {
    const vec_in = b - a;
    const vec_out = c - b;
    const double_signed_area = cross2d(vec_in, vec_out);
    return @abs(double_signed_area) < geo_eps;
}

inline fn dot(a: anytype, b: anytype) @typeInfo(@TypeOf(a)).vector.child {
    assert(@TypeOf(a) == @TypeOf(b));
    return @reduce(.Add, a * b);
}

inline fn normalize(v: anytype) @TypeOf(v) {
    const one_over_len = 1.0 / @sqrt(dot(v, v));
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

    const vertices = [_]ProjectedVertex{
        .{ .pos = pv0, .idx = .{} },
        .{ .pos = pv1, .idx = .{} },
        .{ .pos = pv2, .idx = .{} },
        .{ .pos = pv3, .idx = .{} },
    };

    const sum = shoelaceSum(&vertices);

    try std.testing.expect(sum > 0);
    try std.testing.expectEqual(2, sum);
}

test "convex" {
    const pv0 = Vec2{ 0, 0 };
    const pv1 = Vec2{ 1, 0 };
    const pv2 = Vec2{ 1, 1 };

    const double_signed_area = cross2d(pv1 - pv0, pv2 - pv1);
    const convex = !(double_signed_area <= -geo_eps);
    try std.testing.expectEqual(true, convex);
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
    if (fn_mag_sq < geo_eps * geo_eps) return error.TriangulationFailed;
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

    const vertices = [_]ProjectedVertex{
        .{ .pos = pv0, .idx = .{} },
        .{ .pos = pv1, .idx = .{} },
        .{ .pos = pv2, .idx = .{} },
        .{ .pos = pv3, .idx = .{} },
    };

    const winding_sum = shoelaceSum(&vertices);
    const effective_winding_sign = winding_sum * plane_handedness_factor;

    const revert = if (effective_winding_sign < -geo_eps)
        true
    else if (effective_winding_sign > geo_eps)
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
    var ta = mem.get_temp();

    const result = parse(ta.allocator(), .{ .buffer = "o test \nv 1.0 xxx 1.0", .name = "testbuffer" });

    try std.testing.expectError(error.InvalidCharacter, result);
}

// If no 'o' lines are present, the parser should assign all vertecis (etc) to a default object
test "implicit object" {
    var ta = mem.get_temp();

    const result = try parse(ta.allocator(), .{
        .name = "defaultobject",
        .buffer =
        \\v -0.500000 0.000000 0.000000
        \\v 0.500000 0.000000 0.000000
        \\v 0.000000 0.500000 0.000000
        \\vn -0.0000 -0.0000 1.0000
        \\vt 0.000000 0.000000
        \\f 1/1/1 2/1/1 3/1/1
        ,
    });

    try std.testing.expectEqual(1, result.objects.len);
    const obj = result.objects[0];
    try std.testing.expectEqual(result.faces.len, obj.faces.len);
    try std.testing.expectEqualSlices(u8, "", obj.name);
    try std.testing.expectEqualSlices(Face, result.faces, obj.faces);
}

test "first object name" {
    var ta = mem.get_temp();

    const result = try parse(ta.allocator(), .{
        .name = "defaultobject",
        .buffer =
        \\o Triangle
        \\v -0.500000 0.000000 0.000000
        \\v 0.500000 0.000000 0.000000
        \\v 0.000000 0.500000 0.000000
        \\vn -0.0000 -0.0000 1.0000
        \\vt 0.000000 0.000000
        \\f 1/1/1 2/1/1 3/1/1
        ,
    });

    try std.testing.expectEqual(1, result.objects.len);
    const obj = result.objects[0];
    try std.testing.expectEqual(result.faces.len, obj.faces.len);
    try std.testing.expectEqualSlices(u8, "Triangle", obj.name);
    try std.testing.expectEqualSlices(Face, result.faces, obj.faces);
}

// Some faces (and vertices etc.) might occur before the first object
test "implicit and explicit object" {
    var ta = mem.get_temp();

    const result = try parse(ta.allocator(), .{
        .name = "defaultobject",
        .buffer =
        \\v -0.500000 0.000000 0.000000
        \\v 0.500000 0.000000 0.000000
        \\v 0.000000 0.500000 0.000000
        \\vn -0.0000 -0.0000 1.0000
        \\vt 0.000000 0.000000
        \\f 1/1/1 2/1/1 3/1/1
        \\o Triangle
        \\v 0.500000 0.000000 0.000000
        \\v 1.500000 0.000000 0.000000
        \\v 1.000000 0.500000 0.000000
        \\vn -0.0000 -0.0000 1.0000
        \\vt 0.000000 0.000000
        \\f 4/2/2 5/2/2 6/2/2
        ,
    });

    try std.testing.expectEqual(2, result.objects.len);
    try std.testing.expectEqual(6, result.vertices.len);
    try std.testing.expectEqual(2, result.normals.len);
    try std.testing.expectEqual(2, result.texcoords.len);

    const implicit_obj = result.objects[0];
    try std.testing.expectEqual(1, implicit_obj.faces.len);
    try std.testing.expectEqualSlices(u8, "", implicit_obj.name);
    try std.testing.expectEqualSlices(Face, result.faces[0..1], implicit_obj.faces);
    try std.testing.expectEqualSlices(Index, result.indices[0..3], implicit_obj.faces[0].indices);
    try std.testing.expectEqual(Index{ .vertex = 0, .normal = 0, .texcoord = 0 }, result.indices[0]);
    try std.testing.expectEqual(Index{ .vertex = 1, .normal = 0, .texcoord = 0 }, result.indices[1]);
    try std.testing.expectEqual(Index{ .vertex = 2, .normal = 0, .texcoord = 0 }, result.indices[2]);

    const explicit_obj = result.objects[1];
    try std.testing.expectEqual(1, explicit_obj.faces.len);
    try std.testing.expectEqualSlices(u8, "Triangle", explicit_obj.name);
    try std.testing.expectEqualSlices(Face, result.faces[1..], explicit_obj.faces);
    try std.testing.expectEqualSlices(Index, result.indices[3..], explicit_obj.faces[0].indices);
    try std.testing.expectEqual(Index{ .vertex = 3, .normal = 1, .texcoord = 1 }, result.indices[3]);
    try std.testing.expectEqual(Index{ .vertex = 4, .normal = 1, .texcoord = 1 }, result.indices[4]);
    try std.testing.expectEqual(Index{ .vertex = 5, .normal = 1, .texcoord = 1 }, result.indices[5]);
}

test "parse (semantic comparison)" {
    const ExpectedModelData = struct {
        vertex_count: usize,
        normal_count: usize,
        texcoord_count: usize,
        face_count: usize,
        object_count: usize,
    };
    const Test = struct {
        full_path: []const u8,
        content: []const u8,
        expected: ExpectedModelData,
    };

    var ta = mem.get_temp();
    defer ta.release();

    // TODO: Pass this path via options from build.zig
    const test_path = std.fmt.comptimePrint("{s}{c}{s}", .{ "res", std.fs.path.sep, "semantic_test_obj" });

    const addTest = struct {
        pub fn f(comptime name: @Type(.enum_literal), expected: ExpectedModelData) Test {
            const file_name = std.fmt.comptimePrint("{s}.obj", .{@tagName(name)});
            const full_path = std.fmt.comptimePrint("{s}{c}{s}", .{ test_path, std.fs.path.sep, file_name });

            return .{
                .full_path = full_path,
                .content = @embedFile(full_path),
                .expected = expected,
            };
        }
    }.f;

    const tests = [_]Test{
        addTest(.cube_t, .{ .vertex_count = 8, .normal_count = 6, .texcoord_count = 14, .face_count = 12, .object_count = 1 }),
        addTest(.cube, .{ .vertex_count = 8, .normal_count = 6, .texcoord_count = 14, .face_count = 12, .object_count = 1 }),
        addTest(.concave_pentagon_t, .{ .vertex_count = 5, .normal_count = 1, .texcoord_count = 0, .face_count = 3, .object_count = 1 }),
        addTest(.concave_pentagon, .{ .vertex_count = 5, .normal_count = 1, .texcoord_count = 0, .face_count = 3, .object_count = 1 }),
        addTest(.problematic_face_t, .{ .vertex_count = 4, .normal_count = 1, .texcoord_count = 4, .face_count = 2, .object_count = 1 }),
        addTest(.problematic_face, .{ .vertex_count = 4, .normal_count = 1, .texcoord_count = 4, .face_count = 2, .object_count = 1 }),
        addTest(.funky_plane_3d_t, .{ .vertex_count = 20, .normal_count = 18, .texcoord_count = 10, .face_count = 36, .object_count = 1 }),
        addTest(.funky_plane_3d, .{ .vertex_count = 20, .normal_count = 18, .texcoord_count = 10, .face_count = 35, .object_count = 1 }),
        addTest(.concave_quad_t, .{ .vertex_count = 4, .normal_count = 1, .texcoord_count = 0, .face_count = 2, .object_count = 1 }),
        addTest(.concave_quad, .{ .vertex_count = 4, .normal_count = 1, .texcoord_count = 0, .face_count = 2, .object_count = 1 }),
        addTest(.projection_winding_flip_t, .{ .vertex_count = 4, .normal_count = 1, .texcoord_count = 0, .face_count = 2, .object_count = 1 }),
        addTest(.projection_winding_flip, .{ .vertex_count = 4, .normal_count = 1, .texcoord_count = 0, .face_count = 2, .object_count = 1 }),
        addTest(.collinear_t, .{ .vertex_count = 6, .normal_count = 1, .texcoord_count = 0, .face_count = 4, .object_count = 1 }),
        addTest(.collinear, .{ .vertex_count = 6, .normal_count = 1, .texcoord_count = 0, .face_count = 2, .object_count = 1 }),
        addTest(.funky_plane_t, .{ .vertex_count = 10, .normal_count = 1, .texcoord_count = 10, .face_count = 8, .object_count = 1 }),
        addTest(.funky_plane, .{ .vertex_count = 10, .normal_count = 1, .texcoord_count = 10, .face_count = 8, .object_count = 1 }),
        addTest(.c_t, .{ .vertex_count = 8, .normal_count = 1, .texcoord_count = 0, .face_count = 6, .object_count = 1 }),
        addTest(.c, .{ .vertex_count = 8, .normal_count = 1, .texcoord_count = 0, .face_count = 4, .object_count = 1 }),
        addTest(.triangle_t, .{ .vertex_count = 3, .normal_count = 1, .texcoord_count = 1, .face_count = 1, .object_count = 1 }),
        addTest(.triangle, .{ .vertex_count = 3, .normal_count = 1, .texcoord_count = 1, .face_count = 1, .object_count = 1 }),
        addTest(.arrow_t, .{ .vertex_count = 25, .normal_count = 12, .texcoord_count = 34, .face_count = 46, .object_count = 1 }),
        addTest(.arrow, .{ .vertex_count = 25, .normal_count = 12, .texcoord_count = 34, .face_count = 46, .object_count = 1 }),
    };

    for (tests) |t| {
        log.debug("testing: {s}:", .{t.full_path});

        const model = try parse(ta.allocator(), .{ .name = t.full_path, .buffer = t.content });

        try std.testing.expectEqual(t.expected.vertex_count, model.vertices.len);
        try std.testing.expectEqual(t.expected.normal_count, model.normals.len);
        try std.testing.expectEqual(t.expected.texcoord_count, model.texcoords.len);
        try std.testing.expectEqual(t.expected.face_count, model.faces.len);
        try std.testing.expectEqual(t.expected.object_count, model.objects.len);
    }

    // Ensure no OBJ files have been overlooked by testing.
    var gpad = std.heap.DebugAllocator(.{}).init;
    const gpa = gpad.allocator();

    var test_dir = try std.fs.cwd().openDir(test_path, .{ .iterate = true });
    defer test_dir.close();
    var walker = try test_dir.walk(gpa);
    defer walker.deinit();

    var untested_files = false;
    while (try walker.next()) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".obj")) continue;

        const entry_path = try std.fs.path.join(gpa, &.{ test_path, entry.basename });

        var found = false;
        for (tests) |t| {
            if (std.mem.eql(u8, t.full_path, entry_path)) {
                found = true;
                break;
            }
        }

        if (!found) {
            log.err("Untested file: '{s}'", .{entry_path});
            untested_files = true;
        }
    }

    if (untested_files) {
        return error.UntestedOBJFile;
    }
}
