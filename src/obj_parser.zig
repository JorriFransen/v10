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

const EPS = 1e-6;

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

    log.debug("\n\n", .{});

    for (vertex_array.items, 0..) |v, i| log.debug("vertex_array.items[{}]: {}", .{ i, v });
    for (uv_array.items, 0..) |v, i| log.debug("uv_array.items[{}]: {}", .{ i, v });
    for (normal_array.items, 0..) |v, i| log.debug("normal_array.items[{}]: {}", .{ i, v });
    for (index_array.items, 0..) |v, i| log.debug("index_array.items[{}]: {}", .{ i, v.vertex });
    for (face_array.items, 0..) |v, i| log.debug("face_array.items[{}]: {}", .{ i, v });
    for (obj_array.items, 0..) |v, i| log.debug("obj_array.items[{}]: {}", .{ i, v });

    log.debug("\n\n", .{});

    log.debug("need_triangulation: {}\n", .{need_triangulation});

    // if (need_triangulation) {
    //     assert(false);
    // }

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
