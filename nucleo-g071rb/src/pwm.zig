//! TIM14-channel-1 PWM driver.
//!
//! TIM14 is the simplest general-purpose timer on the STM32G0 - one
//! channel, no break / dead-time / encoder mode - and it's the only
//! timer that maps onto PA4 (the shield's MOTOR_PWM net) via AF4.
//!
//! The driver runs the counter in edge-aligned PWM mode 1 (high while
//! `CNT < CCR1`). The PWM frequency is `kernel_clock_hz /
//! ((PSC + 1) * (ARR + 1))`. We pick PSC so that ARR + 1 == resolution,
//! which lets the caller program duty as a 0..resolution integer that
//! reads as a percentage when `resolution == 100`.
const chip = @import("chip/STM32G071.zig");

pub const Config = struct {
    /// Timer kernel clock in Hz (TIM14 = PCLK on this BSP).
    kernel_clock_hz: u32,
    /// Switching frequency on the PWM pin.
    pwm_freq_hz: u32 = 10_000,
    /// CCR1 input range: 0 = full off, resolution = full on. Default 100
    /// makes "DUTY50" mean exactly 50%.
    resolution: u16 = 100,
};

pub const Tim14Pwm = struct {
    periph: *volatile chip.types.peripherals.TIM14,

    pub fn init(self: Tim14Pwm, comptime config: Config) void {
        self.periph.CR1.modify(.{ .CEN = 0 });
        self.periph.PSC.write_raw(comptime computePsc(config));
        self.periph.ARR.write_raw(config.resolution - 1);
        self.periph.CCMR1_Output.write(.{ .OC1M = 0b110, .OC1PE = 1 });
        self.periph.CCER.write(.{ .CC1E = 1 });
        self.periph.CCR1.write_raw(0);
        self.periph.EGR.write(.{ .UG = 1 });
        self.periph.CR1.modify(.{ .ARPE = 1, .CEN = 1 });
    }

    /// Set duty as a value in `0..resolution`. Out-of-range values are
    /// clamped to full on.
    pub fn setDuty(self: Tim14Pwm, duty: u16) void {
        self.periph.CCR1.write_raw(duty);
    }
};

fn computePsc(comptime config: Config) u16 {
    const tick_freq: u32 = config.pwm_freq_hz * config.resolution;
    if (config.kernel_clock_hz < tick_freq)
        @compileError("kernel clock too slow for requested PWM freq * resolution");
    const psc = config.kernel_clock_hz / tick_freq - 1;
    if (psc > 0xFFFF) @compileError("PWM frequency too low for 16-bit prescaler");
    return @intCast(psc);
}
