/// Lab 03: UART print + LED blink
///
/// Prints a message via USART2 (ST-Link VCP) every 1 second and toggles the
/// onboard LED (PA5) with each print. Uses erd_core's TimerModule for scheduling
/// instead of HAL_Delay — the super-loop sleeps via WFI between timer expirations.
const board = @import("board");
const Application = @import("application").Application;
const erd_core = @import("erd_core");

// Force the startup module to be analyzed so its exported symbols (_start,
// vector_table, __atomic_load_4) end up in the final binary.
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
    hardware.init(.{ .systick_tick = &sysTickTick });
    application.init(&timer_module);
    while (true) {
        if (!timer_module.run()) {
            asm volatile ("wfi");
        }
    }
}
