/// Lab 05: User-defined system clock (32 MHz) + register-level blink
///
/// Brings the chip up to 32 MHz via a user-defined RCC sequence
/// (HSI16 -> PLL/4 -> SYSCLK), prints a banner every second over the
/// ST-Link VCP, and toggles the on-board LED (PA5) at the same cadence
/// through direct BSRR writes. UART pacing comes from the SysTick-driven
/// `TimerModule`, which is the equivalent of HAL_Delay without blocking
/// the super-loop.
const board = @import("board");
const Application = @import("application").Application;
const erd_core = @import("erd_core");

comptime {
    _ = board.startup;
}

var timer_module: erd_core.timer.TimerModule = .{};
var hardware: board.Hardware = .{};
var application: Application = .{};

fn sysTickTick() void {
    timer_module.incrementCurrentTime(1);
}

pub fn main() noreturn {
    hardware.init(.{ .systick_tick = &sysTickTick, .clock = .pll_32mhz });
    application.init(&timer_module);
    while (true) {
        if (!timer_module.run()) asm volatile ("wfi");
    }
}
