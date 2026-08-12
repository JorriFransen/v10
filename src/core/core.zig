pub const arch = @import("arch/arch.zig").arch;
pub const clip = @import("clip.zig");
pub const intrinsics = @import("intrinsics.zig");
pub const linux = @import("linux/linux.zig");
pub const math = @import("math.zig");
pub const mem = @import("mem/mem.zig");
pub const meta = @import("meta.zig");
pub const win32 = @import("win32/win32.zig");
pub const xml = @import("xml.zig");

pub const DynLib = @import("dynlib.zig");
pub const TimeParts = @import("timeparts.zig").TimeParts;

test {
    const t = @import("std").testing;

    t.refAllDecls(clip);
    t.refAllDecls(mem);
}
