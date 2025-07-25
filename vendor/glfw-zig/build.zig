// Based on: https://github.com/thedeadtellnotales/glfw/blob/master/build.zig

const std = @import("std");

const assert = std.debug.assert;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const maybe_glfw_dep = b.option(std.Build.LazyPath, "glfw_source", "Set the path to the glfw source");

    const shared = b.option(bool, "shared", "Build as shared library") orelse false;
    const use_x11 = b.option(bool, "x11", "Build with X11. (Linux only)") orelse true;
    const use_wl = b.option(bool, "wayland", "Build with Wayland. (Linux only)") orelse true;

    const use_opengl = b.option(bool, "opengl", "Build with opengl. (MacOs deprecated)") orelse false;
    const use_gles = b.option(bool, "gles", "Build with GLES. (MacOs deprecated)") orelse false;
    const use_metal = b.option(bool, "metal", "Build with metal. (MacOs only)") orelse true;

    const glfw_source = GlfwSource.init(b, maybe_glfw_dep);

    const lib = b.addLibrary(.{
        .name = "glfw",
        .version = .{ .major = 3, .minor = 4, .patch = 0 },
        .linkage = if (shared) .dynamic else .static,
        .root_module = b.createModule(.{
            .root_source_file = null,
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    lib.addIncludePath(glfw_source.path("include"));

    if (shared) lib.root_module.addCMacro("_GLFW_BUILD_DLL", "1");

    lib.installHeadersDirectory(glfw_source.path("include/GLFW"), "GLFW", .{});

    const include_src_flag = "-Isrc";

    switch (target.result.os.tag) {
        else => {
            std.log.err("Unsupported target: {}", .{target.result.os.tag});
            @panic("Unsupported target");
        },
        .windows => {
            lib.linkSystemLibrary("gdi32");
            lib.linkSystemLibrary("user32");
            lib.linkSystemLibrary("shell32");

            if (use_opengl) {
                lib.linkSystemLibrary("opengl32");
            }
            if (use_gles) {
                lib.linkSystemLibrary("GLESv3");
            }

            const flags = [_][]const u8{ include_src_flag, "-D_GLFW_WIN32" };
            lib.addCSourceFiles(.{
                .root = glfw_source.path(""),
                .files = &base_sources ++ &windows_sources,
                .flags = &flags,
            });
        },
        .linux => {
            var flags = try std.BoundedArray([]const u8, 16).init(0);
            var sources = try std.BoundedArray([]const u8, 64).init(0);

            try sources.appendSlice(&base_sources);
            try sources.appendSlice(&linux_sources);

            if (use_x11) {
                try flags.append("-D_GLFW_X11");
                try sources.appendSlice(&linux_x11_sources);
            }

            if (use_wl) {
                try flags.append("-D_GLFW_WAYLAND");
                try sources.appendSlice(&linux_wl_sources);

                const wayland_gen = try WaylandGenerator.generate(b, glfw_source);
                lib.step.dependOn(wayland_gen.step);
                lib.addIncludePath(wayland_gen.include_dir);
            }

            try flags.append(include_src_flag);

            lib.addCSourceFiles(.{
                .root = glfw_source.path(""),
                .files = sources.slice(),
                .flags = flags.slice(),
            });
        },
    }

    b.installArtifact(lib);

    const glfw_mod = b.addModule("glfw", .{
        .root_source_file = b.path("src/glfw.zig"),
        .target = target,
        .optimize = optimize,
    });
    glfw_mod.linkLibrary(lib);

    _ = use_metal;
}

const base_sources = [_][]const u8{
    "src/context.c",
    "src/egl_context.c",
    "src/init.c",
    "src/input.c",
    "src/monitor.c",
    "src/null_init.c",
    "src/null_joystick.c",
    "src/null_monitor.c",
    "src/null_window.c",
    "src/osmesa_context.c",
    "src/platform.c",
    "src/vulkan.c",
    "src/window.c",
};

const linux_sources = [_][]const u8{
    "src/linux_joystick.c",
    "src/posix_module.c",
    "src/posix_poll.c",
    "src/posix_thread.c",
    "src/posix_time.c",
    "src/xkb_unicode.c",
};

const linux_wl_sources = [_][]const u8{
    "src/wl_init.c",
    "src/wl_monitor.c",
    "src/wl_window.c",
};

const linux_x11_sources = [_][]const u8{
    "src/glx_context.c",
    "src/x11_init.c",
    "src/x11_monitor.c",
    "src/x11_window.c",
};

const windows_sources = [_][]const u8{
    "src/wgl_context.c",
    "src/win32_init.c",
    "src/win32_joystick.c",
    "src/win32_module.c",
    "src/win32_monitor.c",
    "src/win32_thread.c",
    "src/win32_time.c",
    "src/win32_window.c",
};

const macos_sources = [_][]const u8{
    // C sources
    "src/cocoa_time.c",
    "src/posix_module.c",
    "src/posix_thread.c",

    // ObjC sources
    "src/cocoa_init.m",
    "src/cocoa_joystick.m",
    "src/cocoa_monitor.m",
    "src/cocoa_window.m",
    "src/nsgl_context.m",
};

const wayland_xml_dir = "deps/wayland";
const wayland_xml_sources = [_][]const u8{
    "fractional-scale-v1.xml",
    "idle-inhibit-unstable-v1.xml",
    "pointer-constraints-unstable-v1.xml",
    "relative-pointer-unstable-v1.xml",
    "viewporter.xml",
    "wayland.xml",
    "xdg-activation-v1.xml",
    "xdg-decoration-unstable-v1.xml",
    "xdg-shell.xml",
};

const GlfwSource = struct {
    owner: *std.Build,
    source: union(enum) {
        default: *std.Build.Dependency,
        lazypath: std.Build.LazyPath,
    },

    pub fn init(b: *std.Build, maybe_lazypath: ?std.Build.LazyPath) GlfwSource {
        if (maybe_lazypath) |lp| {
            return .{ .owner = b, .source = .{ .lazypath = lp } };
        } else {
            return .{ .owner = b, .source = .{ .default = b.dependency("glfw", .{}) } };
        }
    }

    pub fn path(this: *const GlfwSource, sub_path: []const u8) std.Build.LazyPath {
        switch (this.source) {
            .default => |d| return d.path(sub_path),
            .lazypath => |lp| return lp.path(this.owner, sub_path),
        }
    }
};

const WaylandGenerator = struct {
    const Result = struct {
        step: *std.Build.Step,
        include_dir: std.Build.LazyPath,
    };

    owner: *std.Build,
    scanner: []const u8,
    write_file: *std.Build.Step.WriteFile,

    pub fn generate(b: *std.Build, glfw_source: GlfwSource) !Result {
        var ctx = @This(){
            .owner = b,
            .scanner = try pkgConfig(b, "wayland-scanner", &.{"--variable=wayland_scanner"}),
            .write_file = b.addNamedWriteFiles("wayland-protocols"),
        };
        ctx.write_file.step.name = "WriteFiles wayland-protocols";

        const xml_lazy_dir = glfw_source.path(wayland_xml_dir);
        for (wayland_xml_sources) |xml_name| {
            assert(std.mem.endsWith(u8, xml_name, ".xml"));

            const name = xml_name[0 .. xml_name.len - 4];
            const xml_lazy_name = xml_lazy_dir.path(b, xml_name);
            ctx.runScanner("client-header", xml_lazy_name, b.fmt("{s}-client-protocol.h", .{name}));
            ctx.runScanner("private-code", xml_lazy_name, b.fmt("{s}-client-protocol-code.h", .{name}));
        }

        return .{
            .step = &ctx.write_file.step,
            .include_dir = ctx.write_file.getDirectory(),
        };
    }

    fn runScanner(ctx: *@This(), cmd: []const u8, xml_path: std.Build.LazyPath, header_file_name: []const u8) void {
        const b = ctx.owner;
        var run = b.addSystemCommand(&.{ ctx.scanner, cmd });
        run.addFileArg(xml_path);
        const out_file = run.addOutputFileArg(header_file_name);
        _ = ctx.write_file.addCopyFile(out_file, header_file_name);
    }
};

fn pkgConfig(b: *std.Build, pkg: []const u8, flags: []const []const u8) ![]const u8 {
    var args = std.ArrayList([]const u8).init(b.allocator);
    try args.append("pkg-config");
    try args.appendSlice(flags);
    try args.append(pkg);

    var child = std.process.Child.init(args.items, b.allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    var stdout_buf = std.ArrayList(u8).init(b.allocator);
    defer stdout_buf.deinit();
    _ = try child.stdout.?.deprecatedReader().readAllArrayList(&stdout_buf, 1024 * 1024);

    var stderr_buf = std.ArrayList(u8).init(b.allocator);
    defer stderr_buf.deinit();
    _ = try child.stderr.?.deprecatedReader().readAllArrayList(&stderr_buf, 1024 * 1024);

    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code == 0) {
                const result = try b.allocator.alloc(u8, stdout_buf.items.len);
                @memcpy(result, stdout_buf.items);
                return stripRight(result);
            } else {
                std.log.err("pkgconf failed with error: {}", .{code});
                return error.PkgConfigFailed;
            }
        },
        .Signal => |signal| {
            std.log.err("pkgconf failed with signal: {}", .{signal});
            return error.PkgConfigSignaled;
        },
        .Stopped, .Unknown => {
            std.log.err("pkgconf failed", .{});
            return error.PkgConfigFailed;
        },
    }
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
