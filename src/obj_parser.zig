const std = @import("std");
const log = std.log.scoped(.obj_parser);
const gfx = @import("gfx.zig");
const mem = @import("memory.zig");

const Allocator = std.mem.Allocator;
const Arena = mem.Arena;
const SplitIterator = std.mem.SplitIterator(u8, .scalar);
const TokenIterator = std.mem.TokenIterator(u8, .scalar);

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
    vertices: []const @Vector(3, f32),
    colors: []const @Vector(3, f32),
    normals: []const @Vector(3, f32),
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
    var num_texcoords: u32 = 0;
    var num_indices: usize = 0;
    var num_faces: usize = 0;

    var line_it = tokenize(buffer, '\n'); // TODO: Make this work with CRLF
    var line_num: usize = 1;
    while (line_it.next()) |line| : (line_num += 1) {
        errdefer log.err("{s}:{}: Invalid line: '{s}'", .{ options.name, line_num, line });

        var field_it = split(line, ' ');
        const field = field_it.first();

        if (eq(field, "v")) {
            num_verts += 1;
        } else if (eq(field, "vn")) {
            num_normals += 1;
        } else if (eq(field, "vt")) {
            num_texcoords += 1;
        } else if (eq(field, "f")) {
            num_indices += 3;
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

    const vertices = try allocator.alloc(@Vector(3, f32), num_verts);
    const normals = try allocator.alloc(@Vector(3, f32), num_normals);
    const texcoords = try allocator.alloc(@Vector(2, f32), num_texcoords);
    const faces = try allocator.alloc(Face, num_faces);
    const objects = try allocator.alloc(Object, num_objects);
    const indices = try allocator.alloc(Index, num_faces * 3);

    var colors: []@Vector(3, f32) = &.{};
    var parse_vector_fn = &parseVector;
    if (options.flags.vertex_colors) {
        colors = try allocator.alloc(@Vector(3, f32), num_verts);
        parse_vector_fn = parseVectorAndColor;
    }

    num_verts = 0;
    num_normals = 0;
    num_texcoords = 0;
    num_indices = 0;
    num_faces = 0;
    num_objects = 0;

    var current_object: ?*Object = null;
    var obj_face_offset: usize = 0;

    line_it = tokenize(buffer, '\n'); // TODO: Make this work with CRLF
    line_num = 1;
    while (line_it.next()) |line| : (line_num += 1) {
        errdefer log.err("{s}:{}: Invalid line: '{s}'", .{ options.name, line_num, line });

        var field_it = tokenize(line, ' ');
        const field = field_it.next() orelse return error.Syntax;

        if (eq(field, "v")) {
            parse_vector_fn(&field_it, num_verts, vertices, colors);
            num_verts += 1;
        } else if (eq(field, "vn")) {
            normals[num_normals] = parseVec3(&field_it);
            num_normals += 1;
        } else if (eq(field, "vt")) {
            texcoords[num_texcoords] = parseVec2(&field_it);
            num_texcoords += 1;
        } else if (eq(field, "f")) {
            faces[num_faces] = try parseFace(field_it.rest(), num_verts, num_texcoords, num_normals, indices, &num_indices);
            num_faces += 1;
        } else if (eq(field, "o")) {
            if (current_object) |obj| {
                obj.faces = faces[obj_face_offset..num_faces];
            }
            obj_face_offset = num_faces;

            const obj = &objects[num_objects];
            obj.name = field_it.rest();

            current_object = obj;
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
    if (current_object) |obj| {
        obj.faces = faces[obj_face_offset..num_faces];
    }

    assert(vertices.len == num_verts);
    if (options.flags.vertex_colors) assert(colors.len == num_verts);
    assert(texcoords.len == num_texcoords);
    assert(normals.len == num_normals);
    assert(indices.len == num_indices);
    assert(faces.len == num_faces);
    assert(objects.len == num_objects);

    return .{
        .vertices = vertices,
        .colors = colors,
        .normals = normals,
        .texcoords = texcoords,
        .indices = indices,
        .faces = faces,
        .objects = objects,
    };
}

fn parseFace(str: []const u8, num_verts: u32, num_texcoords: u32, num_normals: u32, indices: []Index, num_indices: *usize) !Face {
    var r = Face{};
    var index_it = tokenize(str, ' ');
    for (0..3) |i| {
        const fields = index_it.next() orelse {
            log.err("Face needs at least 3 vertices", .{});
            return error.Syntax;
        };

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

        indices[num_indices.* + i].vertex = @intCast(if (vertex < 0) (vertex + (1 + num_verts)) else (vertex));
        indices[num_indices.* + i].texcoord = @intCast(if (texcoord < 0) (texcoord + (1 + num_texcoords)) else (texcoord));
        indices[num_indices.* + i].normal = @intCast(if (normal < 0) (normal + (1 + num_normals)) else (normal));
    }

    r.indices = indices[num_indices.* .. num_indices.* + 3];

    num_indices.* += 3;

    if (index_it.next() != null) {
        log.err("Non triangulate faces are not supported!", .{});
        return error.Syntax;
    }

    return r;
}

fn parseVector(field_it: *TokenIterator, num_verts: usize, vertices: []@Vector(3, f32), colors: []@Vector(3, f32)) void {
    _ = colors;
    vertices[num_verts] = parseVec3(field_it);
}

fn parseVectorAndColor(field_it: *TokenIterator, num_verts: usize, vertices: []@Vector(3, f32), colors: []@Vector(3, f32)) void {
    vertices[num_verts] = parseVec3(field_it);
    colors[num_verts] = if (field_it.rest().len == 0) .{ 1, 1, 1 } else parseVec3(field_it);
}

inline fn parseVec3(field_it: *TokenIterator) @Vector(3, f32) {
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
