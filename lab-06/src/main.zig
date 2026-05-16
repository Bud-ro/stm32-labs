/// Lab 06: I2C1 + TMP102 temperature sensor
///
/// Builds on Lab 04 (UART command parser, ring buffer) and Lab 05
/// (32 MHz PLL system clock). The application configures I2C1 on
/// PB8/PB9 (Arduino D15/D14) and reads a TMP102 sensor sitting on a
/// shield board. `START` over UART begins 1 Hz one-shot reads; `STOP`
/// halts them. Conversions are triggered by writing OS=1 to the
/// TMP102 config register; a 30 ms one-shot software timer schedules
/// the readback so the super-loop stays responsive in between.
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
    hardware.init(.{
        .systick_tick = &sysTickTick,
        .uart_rx = &onUartRx,
        .clock = .pll_32mhz,
    });
    hardware.enableI2c1(.{
        .kernel_clock_hz = board.clock.Config.pll_32mhz.hclkHz(),
        .mode = .standard_100k,
    });
    application.init(&timer_module);
    while (true) {
        var had_work = false;
        if (hardware.runUarts()) had_work = true;
        if (timer_module.run()) had_work = true;
        if (!had_work) asm volatile ("wfi");
    }
}
