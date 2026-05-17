const board = @import("board");
const Application = @import("application").Application;
const erd_core = @import("erd_core");

const SYSCLK: board.clock.Config = .hsi16;

var timer_module: erd_core.timer.TimerModule = .{};
var application: Application = .{};

fn sysTick() callconv(.c) void {
    timer_module.incrementCurrentTime(1);
}

fn usart2Isr() callconv(.c) void {
    if (board.Hardware.serial.serviceRx()) |c| application.processChar(c);
}

pub export const vector_table linksection(".isr_vector") =
    board.startup.vectorTable(.{
        .SysTick = &sysTick,
        .USART2 = &usart2Isr,
    });

pub fn main() noreturn {
    board.Hardware.init(SYSCLK);
    application.init(&timer_module);
    while (true) {
        var had_work = false;
        if (board.Hardware.runUarts()) had_work = true;
        if (timer_module.run()) had_work = true;
        if (!had_work) asm volatile ("wfi");
    }
}
