const std = @import("std");
const clip = @import("clip");
const mem = @import("mem");

const OptionParser = clip.OptionParser("aseprite-export", &.{
    clip.arrayOption([]const u8, "input", 'i', "aseprite file"),
    clip.option(@as([]const u8, ""), "script", 's', "aseprite lua script file"),
    clip.option(@as([]const u8, ""), "done", 'd', "done file"),
});

pub fn main(init: std.process.Init) !u8 {
    try mem.init();
    var tmp = mem.getTemp();

    var options = try OptionParser.parse(init.minimal.args, init.gpa, tmp.allocator());
    defer OptionParser.freeOptions(&options, init.gpa);

    for (options.input.items) |input_file| {
        const args: []const []const u8 = &.{
            "aseprite",
            "-b",
            input_file,
            "--script",
            options.script,
        };

        if (std.process.run(init.gpa, init.io, .{ .argv = args })) |run_res| {
            const ok: bool = switch (run_res.term) {
                .exited => |exit_code| exit_code == 0,
                else => false,
            };

            if (!ok) {
                std.log.warn("asprite execution failed ({s})", .{options.script});
                std.log.warn("stdout: {s}", .{run_res.stdout});
                std.log.warn("stderr: {s}", .{run_res.stderr});
            }

            init.gpa.free(run_res.stdout);
            init.gpa.free(run_res.stderr);
        } else |e| switch (e) {
            else => {
                std.log.err("asprite invocation failed, args:", .{});
                for (args, 0..) |arg, i| std.log.err("        arg[{}]: {s}", .{ i, arg });
            },
        }
    }

    if (options.done.len > 0) {
        const done_file = try std.Io.Dir.createFileAbsolute(init.io, options.done, .{ .truncate = true });
        defer done_file.close(init.io);

        const timestamp = std.Io.Timestamp.now(init.io, .real);

        try done_file.writePositionalAll(init.io, std.mem.asBytes(&timestamp), 0);
    }

    return 0;
}
