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

pub inline fn syscall0(number: u64) i64 {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> i64),
        : [number] "{rax}" (number),
        : .{ .rcx = true, .r11 = true, .memory = true });
}

pub inline fn syscall1(number: u64, arg1: u64) i64 {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> i64),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
        : .{ .rcx = true, .r11 = true, .memory = true });
}

pub inline fn syscall2(number: u64, arg1: u64, arg2: u64) i64 {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> i64),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
        : .{ .rcx = true, .r11 = true, .memory = true });
}

pub inline fn syscall3(number: u64, arg1: u64, arg2: u64, arg3: u64) i64 {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> i64),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
        : .{ .rcx = true, .r11 = true, .memory = true });
}

pub inline fn syscall4(number: u64, arg1: u64, arg2: u64, arg3: u64, arg4: u64) i64 {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> i64),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
        : .{ .rcx = true, .r11 = true, .memory = true });
}

pub inline fn syscall5(number: u64, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64) i64 {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> i64),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
          [arg5] "{r8}" (arg5),
        : .{ .rcx = true, .r11 = true, .memory = true });
}

pub inline fn syscall6(number: u64, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64, arg6: u64) i64 {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> i64),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
          [arg5] "{r8}" (arg5),
          [arg6] "{r9}" (arg6),
        : .{ .rcx = true, .r11 = true, .memory = true });
}
