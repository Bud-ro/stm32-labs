//! Reset handler + vector-table helper for the STM32G071RB.
//!
//! The BSP doesn't own a vector table - each lab declares its own
//! and points it at whatever handlers it wants. `vectorTable(.{ ... })`
//! is a comptime helper that fills in the standard slots (initial SP,
//! reset entry) and lets the lab override any IRQ slot in one line:
//!
//!     pub export const vector_table linksection(".isr_vector") =
//!         board.startup.vectorTable(.{
//!             .SysTick = &mySysTickHandler,
//!             .USART2 = &board.Hardware.usart2RxHandler,
//!         });
//!
//! Slots the lab doesn't name fall through to the chip's
//! `defaultHandler` (an infinite-loop trap from
//! `chip/STM32G071.zig`). This applies to NMI, HardFault, SVCall,
//! PendSV, and every peripheral IRQ.
const app = @import("root");
const chip = @import("chip/STM32G071.zig");

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

/// Builds an `.isr_vector` table, filling in `initial_stack_pointer`
/// and `Reset` from the BSP's startup symbols. Pass a `chip.VectorTable`
/// literal naming only the IRQ slots you want to handle; every other
/// slot keeps the chip default (`unhandled`, an infinite-loop trap).
/// Typed parameter means LSP autocompletes the available fields.
pub fn vectorTable(table: chip.VectorTable) chip.VectorTable {
    var t = table;
    t.initial_stack_pointer = @ptrCast(&_estack);
    t.Reset = @ptrCast(&_start);
    return t;
}
