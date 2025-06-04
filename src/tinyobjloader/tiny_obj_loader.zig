pub usingnamespace @cImport({
    @cInclude("tiny_obj_loader.h");
});

export fn tinyobj_malloc(size: usize) ?*anyopaque {
    _ = size;
    unreachable;
}

export fn tinyobj_calloc(num: usize, size: usize) ?*anyopaque {
    _ = num;
    _ = size;
    unreachable;
}

export fn tinyobj_free(ptr: ?*anyopaque) void {
    _ = ptr;
    unreachable;
}

export fn tinyobj_realloc(ptr: ?*anyopaque, new_size: usize) ?*anyopaque {
    _ = ptr;
    _ = new_size;
    unreachable;
}
