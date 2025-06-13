const std = @import("std");
const log = std.log.scoped(.obj_parser);
const gfx = @import("gfx.zig");
const mem = @import("memory.zig");
const math = @import("math.zig");

const Allocator = std.mem.Allocator;
const Arena = mem.Arena;
const TempArena = mem.TempArena;
const SplitIterator = std.mem.SplitIterator(u8, .scalar);
const TokenIterator = std.mem.TokenIterator(u8, .scalar);

const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);

const assert = std.debug.assert;

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
};

pub const Object = struct {
    name: []const u8 = "",
    faces: []const Face = &.{},
};

pub const Face = struct {
    indices: []Index = &.{},
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

    var vertex_array = try std.ArrayListUnmanaged(Vec3).initCapacity(allocator, num_verts);
    var normal_array = try std.ArrayListUnmanaged(Vec3).initCapacity(allocator, num_normals);
    var uv_array = try std.ArrayListUnmanaged(@Vector(2, f32)).initCapacity(allocator, num_uvs);
    var obj_array = try std.ArrayListUnmanaged(Object).initCapacity(allocator, num_objects);

    var colors_array: std.ArrayListUnmanaged(Vec3) = undefined;
    var parse_vector_fn = &parseVector;
    if (options.flags.vertex_colors) {
        colors_array = try std.ArrayListUnmanaged(Vec3).initCapacity(allocator, num_verts);
        parse_vector_fn = parseVectorAndColor;
    }

    var ta = mem.get_scratch(@ptrCast(@alignCast(allocator.ptr)));
    defer ta.release();

    const face_alloc = if (need_triangulation) ta.allocator() else allocator;
    var face_array = try std.ArrayListUnmanaged(Face).initCapacity(face_alloc, num_faces);
    var index_array = try std.ArrayListUnmanaged(Index).initCapacity(face_alloc, num_indices);

    var current_object: ?*Object = null;
    var obj_face_offset: usize = 0;

    line_it = tokenize(buffer, '\n'); // TODO: Make this work with CRLF
    line_num = 1;
    while (line_it.next()) |line| : (line_num += 1) {
        errdefer log.err("{s}:{}: Invalid line: '{s}'", .{ options.name, line_num, line });

        var field_it = tokenize(line, ' ');
        const field = field_it.next() orelse return error.Syntax;

        if (eq(field, "v")) {
            parse_vector_fn(&field_it, &vertex_array, &colors_array);
        } else if (eq(field, "vn")) {
            normal_array.appendAssumeCapacity(parseVec3(&field_it));
        } else if (eq(field, "vt")) {
            uv_array.appendAssumeCapacity(parseVec2(&field_it));
        } else if (eq(field, "f")) {
            const face = try parseFace(field_it.rest(), @intCast(vertex_array.items.len), num_uvs, @intCast(normal_array.items.len), &index_array);
            face_array.appendAssumeCapacity(face);
        } else if (eq(field, "o")) {
            if (current_object) |obj| {
                obj.faces = face_array.items[obj_face_offset..face_array.items.len];
            }
            obj_face_offset = face_array.items.len;

            const obj = obj_array.addOneAssumeCapacity();
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
        obj.faces = face_array.items[obj_face_offset..face_array.items.len];
    }

    assert(vertex_array.items.len == num_verts);
    if (options.flags.vertex_colors) assert(colors_array.items.len == num_verts);
    assert(uv_array.items.len == num_uvs);
    assert(normal_array.items.len == num_normals);
    assert(index_array.items.len == num_indices);
    assert(face_array.items.len == num_faces);
    assert(obj_array.items.len == num_objects);

    if (need_triangulation) {
        log.debug("TRIANGULATE!", .{});

        log.debug("face_array.items.len: {}", .{face_array.items.len});
        log.debug("index_array.items.len: {}", .{index_array.items.len});

        var final_face_count: usize = 0;
        for (face_array.items) |face| {
            assert(face.indices.len >= 3);
            final_face_count += face.indices.len - 2;
        }

        log.debug("final_face_count: {}", .{final_face_count});

        var t_faces = try std.ArrayListUnmanaged(Face).initCapacity(allocator, final_face_count);
        var t_indices = try std.ArrayListUnmanaged(Index).initCapacity(allocator, final_face_count * 3);

        for (face_array.items, 0..) |face, fi| {
            var indices = std.ArrayListUnmanaged(Index).fromOwnedSlice(face.indices);

            log.debug("\n", .{});
            for (indices.items, 0..) |idx, i| log.debug("indices[{}]: {}, vertices[{}]: {}", .{ i, idx.vertex, idx.vertex, vertex_array.items[idx.vertex] });

            var face_ta = TempArena.init(ta.arena);
            defer face_ta.release();

            var proj_verts = try std.ArrayListUnmanaged(Vec2).initCapacity(face_ta.allocator(), indices.items.len);

            const pa3 = vertex_array.items[indices.items[0].vertex];
            const pb3 = vertex_array.items[indices.items[1].vertex];
            const pc3 = vertex_array.items[indices.items[2].vertex];

            const pba3 = pb3 - pa3;
            const pca3 = pc3 - pa3;
            const ppn_cross = cross(Vec3, pba3, pca3);
            log.debug("pba3: {}", .{pba3});
            log.debug("pca3: {}", .{pca3});
            log.debug("pcross: {}", .{ppn_cross});
            if (dot(Vec3, ppn_cross, ppn_cross) < 1e-9) {
                log.err("Colinear!?", .{});
                unreachable;
            }

            const pplane_normal = normalize(Vec3, ppn_cross);
            log.debug("pplane_normal: {}", .{pplane_normal});

            const U = normalize(Vec3, pba3);
            const W = normalize(Vec3, cross(Vec3, pplane_normal, U));
            log.debug("U: {}", .{U});
            log.debug("W: {}", .{W});

            var signed_area: f32 = 0.0;
            for (indices.items, 0..) |idx, i| {
                const c = vertex_array.items[idx.vertex];
                const n = vertex_array.items[indices.items[(i + 1) % indices.items.len].vertex];

                const cpa = c - pa3;
                const npa = n - pa3;
                const pc = Vec2{ dot(Vec3, cpa, U), dot(Vec3, cpa, W) };
                const pn = Vec2{ dot(Vec3, npa, U), dot(Vec3, npa, W) };

                proj_verts.appendAssumeCapacity(pc);

                signed_area += cross(Vec2, pc, pn);
            }
            signed_area /= 2;
            log.debug("signed_area: {}", .{signed_area});
            assert(@abs(signed_area) > std.math.floatEps(f32));
            const ccw = signed_area > 0;
            log.debug("ccw: {}", .{ccw});

            const vi_dir: isize = if (ccw) 1 else -1;
            var vi: usize = if (ccw) 0 else indices.items.len - 1;

            while (indices.items.len > 3) {
                const idx0 = indices.items[if (vi == 0) indices.items.len - 1 else vi - 1];
                const idx1 = indices.items[vi];
                const idx2 = indices.items[if (vi == indices.items.len - 1) 0 else vi + 1];
                const a3 = vertex_array.items[idx0.vertex];
                const b3 = vertex_array.items[idx1.vertex];
                const c3 = vertex_array.items[idx2.vertex];

                log.debug("\n", .{});
                log.debug("Face idx: {}", .{fi});
                log.debug("Remaining indices: {}", .{indices.items.len});
                log.debug("Testing {}, {}, {}", .{ idx0, idx1, idx2 });
                log.debug("Testing {}, {}, {}", .{ a3, b3, c3 });

                const a = proj_verts.items[if (vi == 0) indices.items.len - 1 else vi - 1];
                const b = proj_verts.items[vi];
                const c = proj_verts.items[(vi + 1) % indices.items.len];

                log.debug("a: {}", .{a});
                log.debug("b: {}", .{b});
                log.debug("c: {}", .{c});

                const ba = a - b;
                const bc = c - b;

                log.debug("ba: {}", .{ba});
                log.debug("bc: {}", .{bc});

                const convex = cross(Vec2, ba, bc);
                log.debug("convex: {}", .{convex});

                var convex_ear = false;
                if (ccw) {
                    if (convex > std.math.floatEps(f32)) convex_ear = true;
                } else {
                    if (convex < -std.math.floatEps(f32)) convex_ear = true;
                }

                if (!convex_ear) {
                    // Colinear or reflex angle
                    log.debug("skipping colinear or reflex: {}", .{vi});
                    var nvi = @as(isize, @intCast(vi)) + vi_dir;
                    if (nvi < 0) nvi = @intCast(indices.items.len);
                    if (nvi >= indices.items.len) nvi = 0;
                    vi = @intCast(nvi);
                    continue;
                }

                log.debug("Angles passed", .{});

                // Check if any other vertices are in the triangle formed by abc
                var tvi = vi + 2;
                var collision = false;
                for (0..indices.items.len - 3) |_| {
                    if (tvi >= indices.items.len) tvi = 0;

                    const p3 = vertex_array.items[indices.items[tvi].vertex];
                    log.debug("Checking for collission with {}", .{p3});

                    const p = proj_verts.items[tvi];
                    log.debug("p: {}", .{p});

                    if (inTriangle(p, a, b, c)) {
                        collision = true;
                        break;
                    }

                    tvi += 1;
                }

                if (!collision) {
                    const start_idx = t_indices.items.len;
                    t_indices.appendSliceAssumeCapacity(&.{ idx0, idx1, idx2 });
                    const new_face = Face{ .indices = t_indices.items[start_idx .. start_idx + 3] };
                    t_faces.appendAssumeCapacity(new_face);
                    _ = indices.orderedRemove(vi);
                    _ = proj_verts.orderedRemove(vi);
                    log.debug("add ear: {}", .{vi});

                    if (vi > indices.items.len) {
                        vi = 0;
                    }
                } else {
                    log.debug("skipping collision: vi: {}", .{vi});
                    var nvi = @as(isize, @intCast(vi)) + vi_dir;
                    if (nvi < 0) nvi = @intCast(indices.items.len);
                    if (nvi >= indices.items.len) nvi = 0;
                    vi = @intCast(nvi);
                }
            }

            // Last triangle
            assert(indices.items.len == 3);
            const start_idx = t_indices.items.len;
            t_indices.appendSliceAssumeCapacity(indices.items);
            const new_face = Face{ .indices = t_indices.items[start_idx .. start_idx + 3] };
            t_faces.appendAssumeCapacity(new_face);
        }

        face_array = t_faces;
        index_array = t_indices;
        ta.release();
    }

    return .{
        .vertices = vertex_array.items,
        .colors = colors_array.items,
        .normals = normal_array.items,
        .texcoords = uv_array.items,
        .indices = index_array.items,
        .faces = face_array.items,
        .objects = obj_array.items,
    };
}

inline fn inTriangle(p: Vec2, ta: Vec2, tb: Vec2, tc: Vec2) bool {
    const v0 = tc - ta;
    const v1 = tb - ta;
    const v2 = p - ta;

    const dot00 = dot(Vec2, v0, v0);
    const dot01 = dot(Vec2, v0, v1);
    const dot02 = dot(Vec2, v0, v2);
    const dot11 = dot(Vec2, v1, v1);
    const dot12 = dot(Vec2, v1, v2);

    const denom = dot00 * dot11 - dot01 * dot01;
    const u = (dot11 * dot02 - dot01 * dot12) / denom;
    const v = (dot00 * dot12 - dot01 * dot02) / denom;

    const EPS = 1e-6;

    return u > EPS and v > EPS and (u + v) < (1 - EPS);
}

inline fn cross(comptime V: type, a: V, b: V) switch (@typeInfo(V).vector.len) {
    else => @compileError("Invalid vector length"),
    3 => V,
    2 => @typeInfo(V).vector.child,
} {
    switch (@typeInfo(V).vector.len) {
        else => @compileError("Invalid vector length"),
        3 => return @bitCast(math.Vec3.cross(@bitCast(a), @bitCast(b))),
        2 => return (a[0] * b[1]) - (a[1] * b[0]),
    }
}

inline fn dot(comptime V: type, a: V, b: V) @typeInfo(V).vector.child {
    switch (@typeInfo(V).vector.len) {
        else => @compileError("Invalid vector length"),
        2 => return @bitCast(math.Vec2.dot(@bitCast(a), @bitCast(b))),
        3 => return @bitCast(math.Vec3.dot(@bitCast(a), @bitCast(b))),
    }
}

inline fn normalize(comptime V: type, v: V) V {
    switch (@typeInfo(V).vector.len) {
        else => @compileError("Invalid vector length"),
        2 => return @bitCast(math.Vec2.normalized(@bitCast(v))),
        3 => return @bitCast(math.Vec3.normalized(@bitCast(v))),
    }
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
