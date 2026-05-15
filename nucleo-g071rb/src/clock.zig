/// System clock configuration.
///
/// `Config` selects which SYSCLK source the board should run on and
/// exposes the derived timing constants every peripheral driver needs
/// (UART BRR divisor, SysTick reload for a 1 ms tick). Add a new variant
/// here when a future lab needs a new clock target; peripheral drivers
/// pick the right constants up automatically.
const chip = @import("chip/STM32G071.zig");

pub const Config = enum {
    /// HSI16 direct, SYSCLK = 16 MHz. Chip reset state — no RCC writes
    /// required.
    hsi16,
    /// HSI16 fed through the PLL, SYSCLK = HCLK = PCLK = 32 MHz.
    pll_32mhz,

    pub fn hclkHz(self: Config) u32 {
        return switch (self) {
            .hsi16 => 16_000_000,
            .pll_32mhz => 32_000_000,
        };
    }

    /// Rounded USART BRR divisor for the requested baud rate. The
    /// returned switch arms are comptime-evaluated, so this lowers to
    /// a constant-table lookup on the enum.
    pub fn baudDivider(self: Config, comptime baud: u32) u16 {
        return switch (self) {
            .hsi16 => roundedDivide(16_000_000, baud),
            .pll_32mhz => roundedDivide(32_000_000, baud),
        };
    }

    /// SysTick reload value for a 1 ms tick using the processor clock.
    pub fn systickReload1ms(self: Config) u32 {
        return switch (self) {
            .hsi16 => 16_000 - 1,
            .pll_32mhz => 32_000 - 1,
        };
    }

    /// Apply this clock configuration to the RCC + FLASH peripherals.
    /// Must be called before any peripheral driver that depends on the
    /// resulting bus clocks (UART baud, SysTick, etc.).
    pub fn apply(self: Config) void {
        switch (self) {
            .hsi16 => {},
            .pll_32mhz => enablePll32MHz(),
        }
    }
};

fn roundedDivide(comptime n: u32, comptime d: u32) u16 {
    return @intCast((n + d / 2) / d);
}

/// Bring SYSCLK = HCLK = PCLK up to 32 MHz from HSI16 via the PLL.
///
/// Sequence per STM32G071 RM0444 §5:
///   1. FLASH: 1 wait state + prefetch (required above 24 MHz).
///   2. HSI16 on, wait for HSIRDY.
///   3. Configure PLL: HSI16 / 1 * 8 / 4 = 32 MHz on PLLRCLK.
///   4. PLL on, wait for PLLRDY.
///   5. Switch SYSCLK to PLLRCLK, wait for SWS = PLL.
fn enablePll32MHz() void {
    const flash = chip.peripherals.FLASH;
    const rcc = chip.peripherals.RCC;

    flash.ACR.modify(.{ .LATENCY = 1, .PRFTEN = 1 });
    while (flash.ACR.read().LATENCY != 1) {}

    rcc.CR.modify(.{ .HSION = 1 });
    while (rcc.CR.read().HSIRDY == 0) {}

    // PLL must be off while PLLSYSCFGR is written (reset state: off).
    rcc.PLLSYSCFGR.modify(.{
        .PLLSRC = 0b10, // HSI16
        .PLLM = 0, // /1   (VCO input = 16 MHz)
        .PLLN = 8, //  x8  (VCO       = 128 MHz)
        .PLLR = 0b011, // /4   (PLLRCLK   = 32 MHz)
        .PLLREN = 1,
    });

    rcc.CR.modify(.{ .PLLON = 1 });
    while (rcc.CR.read().PLLRDY == 0) {}

    // HPRE/PPRE stay at /1 (reset default) so HCLK = PCLK = SYSCLK.
    rcc.CFGR.modify(.{ .SW = 0b010 });
    while (rcc.CFGR.read().SWS != 0b010) {}
}
