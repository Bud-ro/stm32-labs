// ARM Cortex-M SysTick register type (core peripheral, not from SVD)
// See: https://developer.arm.com/documentation/dui0662/b/Cortex-M0--Peripherals/System-timer--SysTick
const mmio = @import("../../../mmio.zig");

pub const SysTick = extern struct {
    /// SysTick Control and Status Register
    /// offset: 0x00
    CSR: mmio.Mmio(packed struct(u32) {
        ENABLE: u1 = 0x0,
        TICKINT: u1 = 0x0,
        CLKSOURCE: u1 = 0x0,
        reserved: u13 = 0,
        COUNTFLAG: u1 = 0x0,
        padding: u15 = 0,
    }),
    /// SysTick Reload Value Register
    /// offset: 0x04
    RVR: mmio.Mmio(packed struct(u32) {
        RELOAD: u24 = 0x0,
        padding: u8 = 0,
    }),
    /// SysTick Current Value Register
    /// offset: 0x08
    CVR: mmio.Mmio(packed struct(u32) {
        CURRENT: u24 = 0x0,
        padding: u8 = 0,
    }),
    /// SysTick Calibration Value Register
    /// offset: 0x0C
    CALIB: mmio.Mmio(packed struct(u32) {
        TENMS: u24 = 0x0,
        reserved: u6 = 0,
        SKEW: u1 = 0x0,
        NOREF: u1 = 0x0,
    }),
};
