const app = @import("root");
const chip = @import("chip/STM32G071.zig");
const hardware = @import("hardware.zig");

// TODO: volatile isn't the correct way to handle this
export fn __atomic_load_4(src: *const u32, _: i32) u32 {
    return @as(*const volatile u32, @ptrCast(src)).*;
}

extern var _sidata: anyopaque;
extern var _sdata: anyopaque;
extern var _edata: anyopaque;
extern var _sbss: anyopaque;
extern var _ebss: anyopaque;
extern var _estack: anyopaque;

var systick_callback: ?*const fn () void = null;

pub fn setSysTickCallback(cb: *const fn () void) void {
    systick_callback = cb;
}

fn sysTickHandler() callconv(chip.cc) void {
    if (systick_callback) |cb| cb();
}

export fn _start() noreturn {
    const data_start: [*]u8 = @ptrCast(&_sdata);
    const data_end: [*]u8 = @ptrCast(&_edata);
    const data_load: [*]const u8 = @ptrCast(&_sidata);
    const data_len = @intFromPtr(data_end) - @intFromPtr(data_start);
    @memcpy(data_start[0..data_len], data_load[0..data_len]);

    const bss_start: [*]u8 = @ptrCast(&_sbss);
    const bss_end: [*]u8 = @ptrCast(&_ebss);
    const bss_len = @intFromPtr(bss_end) - @intFromPtr(bss_start);
    @memset(bss_start[0..bss_len], 0);

    const main_fn: *const fn () noreturn = &app.main;
    main_fn();
}

fn defaultHandler() callconv(chip.cc) void {
    while (true) {}
}

pub export const vector_table: chip.VectorTable linksection(".isr_vector") = .{
    .initial_stack_pointer = @ptrCast(&_estack),
    .Reset = @ptrCast(&_start),
    .SysTick = &sysTickHandler,
    .USART2 = &hardware.usart2RxHandler,
};
