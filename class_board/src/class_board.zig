//! Drivers for peripherals on the class shield board.
//!
//! The shield sits on the NUCLEO-G071RB Arduino-style header and adds
//! peripherals beyond what's on the bare Nucleo. Drivers here depend
//! on the BSP for peripheral types (`board.i2c.I2c`, etc.) but the
//! BSP itself doesn't reach the other way.
pub const Tmp102 = @import("tmp102.zig").Tmp102;
pub const Mb85rs64v = @import("mb85rs64v.zig").Mb85rs64v;
