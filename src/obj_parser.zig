const std = @import("std");
const log = std.log.scoped(.obj_parser);
const gfx = @import("gfx.zig");
const mem = @import("memory.zig");

const Allocator = std.mem.Allocator;
const Arena = mem.Arena;
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

        for (face_array.items) |face| {
            if (face.indices.len == 3) {
                const start_idx = t_indices.items.len;
                t_indices.appendUnalignedSliceAssumeCapacity(face.indices);
                const new_face = Face{ .indices = t_indices.items[start_idx .. start_idx + 3] };
                t_faces.appendAssumeCapacity(new_face);
            } else {
                var vi: usize = 0;
                var indices = std.ArrayListUnmanaged(Index).fromOwnedSlice(face.indices);

                while (indices.items.len > 3) {
                    const idx0 = indices.items[if (vi == 0) indices.items.len - 1 else vi - 1];
                    const idx1 = indices.items[vi];
                    const idx2 = indices.items[if (vi == indices.items.len - 1) 0 else vi + 1];
                    const a = vertex_array.items[idx0.vertex];
                    const b = vertex_array.items[idx1.vertex];
                    const c = vertex_array.items[idx2.vertex];

                    log.debug("\n", .{});
                    log.debug("Remaining indices: {}", .{indices.items.len});
                    log.debug("Testing {}, {}, {}", .{ idx0, idx1, idx2 });
                    log.debug("Testing {}, {}, {}", .{ a, b, c });

                    const angle = angleBetween(a, b, c);
                    log.debug("angle: {}", .{std.math.radiansToDegrees(angle)});
                    if (std.math.approxEqAbs(f32, angle, 0, std.math.floatEps(f32)) or angle >= 180) {
                        // Colinear or reflex angle
                        vi += 1;
                        log.debug("skipping colinear or reflex: {}", .{vi});
                        continue;
                    }

                    log.debug("Angles passed", .{});

                    // Check if any other vertices are in the triangle formed by abc
                    // Assume all points are in the same plane for this
                    var tvi = vi + 2;
                    var collision = false;
                    for (0..indices.items.len - 3) |_| {
                        if (tvi >= indices.items.len) tvi = 0;

                        const p = vertex_array.items[indices.items[tvi].vertex];
                        log.debug("Checking for collission with {}", .{p});

                        if (inTriangle(p, a, b, c)) {
                            log.debug("found point in triangle!", .{});
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
                        vi = 0;
                    } else {
                        vi += 1;
                    }
                }

                // Last triangle
                const start_idx = t_indices.items.len;
                t_indices.appendSliceAssumeCapacity(indices.items);
                const new_face = Face{ .indices = t_indices.items[start_idx .. start_idx + 3] };
                t_faces.appendAssumeCapacity(new_face);
            }
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

inline fn angleBetween(a: Vec3, b: Vec3, c: Vec3) f32 {
    const ba = a - b;
    const bc = c - b;
    const ba_length = @sqrt(@reduce(.Add, ba * ba));
    const bc_length = @sqrt(@reduce(.Add, bc * bc));
    const ba_d_bc = dot(ba, bc);

    log.debug("angleBetween - ba_m: {}", .{ba_length});
    log.debug("angleBetween - bc_m: {}", .{bc_length});
    log.debug("angleBetween - dot: {}", .{ba_d_bc});

    return std.math.acos(std.math.clamp(ba_d_bc / (ba_length * bc_length), -1, 1));
}

inline fn inTriangle(p: Vec3, ta: Vec3, tb: Vec3, tc: Vec3) bool {
    const v0 = tc - ta;
    const v1 = tb - ta;
    const v2 = p - ta;

    const dot00 = dot(v0, v0);
    const dot01 = dot(v0, v1);
    const dot02 = dot(v0, v2);
    const dot11 = dot(v1, v1);
    const dot12 = dot(v1, v2);

    const denom = dot00 * dot11 - dot01 * dot01;
    const u = (dot11 * dot02 - dot01 * dot12) / denom;
    const v = (dot00 * dot12 - dot01 * dot02) / denom;

    return u >= 0 and v >= 0 and u + v <= 1;
}

inline fn dot(a: Vec3, b: Vec3) f32 {
    return @reduce(.Add, a * b);
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

test "colinear" {
    const eps = @sqrt(std.math.floatEps(f32));
    {
        const a = Vec3{ 0, 0, 0 };
        const b = Vec3{ 0, 1, 0 };
        const c = Vec3{ 0, 2, 0 };

        try std.testing.expectApproxEqRel(std.math.pi, angleBetween(a, b, c), eps);
        try std.testing.expectApproxEqRel(0, angleBetween(b, a, c), eps);
    }

    {
        const a = Vec3{ 1, 0, 0 };
        const b = Vec3{ 0, 0, 0 };
        const c = Vec3{ 0, 1, 0 };

        try std.testing.expectApproxEqRel(std.math.pi / 2.0, angleBetween(a, b, c), eps);
    }
}
