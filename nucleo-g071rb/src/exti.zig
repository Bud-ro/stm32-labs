//! External interrupt helpers for STM32G0.
//!
//! On the G0 the EXTI peripheral subsumes what used to live in SYSCFG
//! on F-series chips, so the routing register (`EXTICR`) is owned by
//! EXTI directly - no SYSCFG clock enable required.
//!
//! Each line is fed from one of the GPIO ports A-D/F via the EXTICR
//! byte for that line; trigger polarity goes in `RTSR1` / `FTSR1`, and
//! the line is unmasked in `IMR1`. NVIC then routes the line to one of
//! three banked interrupts:
//!   - EXTI0_1 (lines 0..1)
//!   - EXTI2_3 (lines 2..3)
//!   - EXTI4_15 (lines 4..15)
const std = @import("std");
const chip = @import("chip/STM32G071.zig");
const gpio = @import("gpio.zig");

pub const Trigger = enum { rising, falling, both };

/// Configure an EXTI line for a GPIO pin and enable the NVIC vector.
/// The caller is still responsible for installing the ISR handler that
/// clears the pending bit (`clearPending`) and does the work.
pub fn enable(comptime port: gpio.Port, comptime line: u4, comptime trigger: Trigger) void {
    const exti = chip.peripherals.EXTI;
    const port_code: u8 = @intFromEnum(port);

    // Route this EXTI line to the requested GPIO port. Each EXTICR
    // register holds the port code for four consecutive lines packed
    // into four 8-bit fields named after the *bit positions* they
    // occupy (EXTI0_7, EXTI8_15, EXTI16_23, EXTI24_31).
    const byte_names = [_][]const u8{ "EXTI0_7", "EXTI8_15", "EXTI16_23", "EXTI24_31" };
    const cr_field = byte_names[line % 4];
    switch (line / 4) {
        0 => exti.EXTICR1.modify_one(cr_field, port_code),
        1 => exti.EXTICR2.modify_one(cr_field, port_code),
        2 => exti.EXTICR3.modify_one(cr_field, port_code),
        3 => exti.EXTICR4.modify_one(cr_field, port_code),
        else => unreachable,
    }

    const tr_field = comptime std.fmt.comptimePrint("TR{d}", .{line});
    if (trigger == .rising or trigger == .both) exti.RTSR1.modify_one(tr_field, 1);
    if (trigger == .falling or trigger == .both) exti.FTSR1.modify_one(tr_field, 1);

    const im_field = comptime std.fmt.comptimePrint("IM{d}", .{line});
    exti.IMR1.modify_one(im_field, 1);

    const irq_index = comptime chip.irqIndex(if (line < 2) "EXTI0_1" else if (line < 4) "EXTI2_3" else "EXTI4_15");
    chip.peripherals.NVIC.ISER.write_raw(1 << irq_index);
}

/// Clear the rising and falling pending bits for `line`. Call from the
/// ISR before returning, otherwise the interrupt will re-trigger
/// immediately.
pub fn clearPending(comptime line: u4) void {
    const exti = chip.peripherals.EXTI;
    const rpif = comptime std.fmt.comptimePrint("RPIF{d}", .{line});
    const fpif = comptime std.fmt.comptimePrint("FPIF{d}", .{line});
    exti.RPR1.modify_one(rpif, 1);
    exti.FPR1.modify_one(fpif, 1);
}
