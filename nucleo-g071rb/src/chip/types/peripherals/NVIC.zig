// ARM Cortex-M NVIC register type (core peripheral, not from SVD)
// See: https://developer.arm.com/documentation/dui0662/b/Cortex-M0--Peripherals/Nested-Vectored-Interrupt-Controller
const mmio = @import("../../../mmio.zig");

pub const NVIC = extern struct {
    /// Interrupt Set-Enable Register (write-1-to-enable)
    /// offset: 0x000
    ISER: mmio.Mmio(packed struct(u32) { bits: u32 = 0 }),
    _reserved0: [31]u32,
    /// Interrupt Clear-Enable Register (write-1-to-disable)
    /// offset: 0x080
    ICER: mmio.Mmio(packed struct(u32) { bits: u32 = 0 }),
    _reserved1: [31]u32,
    /// Interrupt Set-Pending Register (write-1-to-pend)
    /// offset: 0x100
    ISPR: mmio.Mmio(packed struct(u32) { bits: u32 = 0 }),
    _reserved2: [31]u32,
    /// Interrupt Clear-Pending Register (write-1-to-clear)
    /// offset: 0x180
    ICPR: mmio.Mmio(packed struct(u32) { bits: u32 = 0 }),
};
