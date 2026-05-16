const board = @import("board");
const Application = @import("application").Application;
const erd_core = @import("erd_core");

// Force the startup module to be analyzed so its exported symbols (_start,
// vector_table, __atomic_load_4) end up in the final binary.
comptime {
    _ = board.startup;
}

var timer_module: erd_core.timer.TimerModule = .{};
var application: Application = .{};

fn sysTickTick() void {
    timer_module.incrementCurrentTime(1);
}

pub fn main() noreturn {
    board.Hardware.init(.{ .systick_tick = &sysTickTick });
    application.init(&timer_module);
    while (true) {
        if (!timer_module.run()) {
            asm volatile ("wfi");
        }
    }
}
