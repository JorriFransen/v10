pub inline fn rdtsc() u64 {
    var hi: u32 = 0;
    var low: u32 = 0;

    asm (
        \\rdtsc
        : [low] "={eax}" (low),
          [hi] "={edx}" (hi),
    );

    return (@as(u64, hi) << 32) | @as(u64, low);
}

pub inline fn rdtscp() u64 {
    var hi: u32 = undefined;
    var low: u32 = undefined;
    const c: u32 = undefined;

    asm (
        \\rdtscp
        : [low] "={eax}" (low),
          [hi] "={edx}" (hi),
        : [c] "={ecx}" (c),
    );
    return (@as(u64, hi) << 32) | @as(u64, low);
}
