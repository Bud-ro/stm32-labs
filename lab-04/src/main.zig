/// Lab 04: UART Ring Buffer + Command Parser
///
/// Extends Lab 03 with interactive UART I/O: received characters are stored
/// in a 20-byte ring buffer with echo, backspace support, and a command
/// parser that recognizes STOP, START, and CLEAR.
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

fn onUartRx(c: u8) void {
    application.processChar(c);
}

pub fn main() noreturn {
    hardware.init(.{ .systick_tick = &sysTickTick, .uart_rx = &onUartRx });
    application.init(&timer_module);
    while (true) {
        var had_work = false;
        if (hardware.runUarts()) had_work = true;
        if (timer_module.run()) had_work = true;
        if (!had_work) asm volatile ("wfi");
    }
}
