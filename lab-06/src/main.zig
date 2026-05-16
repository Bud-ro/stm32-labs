const board = @import("board");
const class_board = @import("class_board");
const Application = @import("application").Application;
const erd_core = @import("erd_core");

// Force the startup module to be analyzed so its exported symbols (_start,
// vector_table, __atomic_load_4) end up in the final binary.
comptime {
    _ = board.startup;
}

const SYSCLK = board.clock.Config.pll_32mhz;

var timer_module: erd_core.timer.TimerModule = .{};
var application: Application = undefined;

fn sysTickTick() void {
    timer_module.incrementCurrentTime(1);
}

fn onUartRx(c: u8) void {
    application.processChar(c);
}

pub fn main() noreturn {
    board.Hardware.init(.{
        .systick_tick = &sysTickTick,
        .uart_rx = &onUartRx,
        .clock = SYSCLK,
    });
    board.Hardware.enableI2c1(.{
        .kernel_clock_hz = SYSCLK.hclkHz(),
        .mode = .standard_100k,
    });

    const serial = board.Hardware.serial;
    serial.puts("Lab 06: TMP102 over I2C1\r\n");
    const sensor = class_board.Tmp102.init(board.Hardware.i2c1_bus) catch blk: {
        serial.puts("TMP102 init FAILED - check wiring\r\n");
        break :blk class_board.Tmp102{ .bus = board.Hardware.i2c1_bus };
    };
    serial.puts("Commands: START, STOP\r\n> ");

    application = .{ .timer_module = &timer_module, .sensor = sensor };
    application.start();

    while (true) {
        var had_work = false;
        if (board.Hardware.runUarts()) had_work = true;
        if (timer_module.run()) had_work = true;
        if (!had_work) asm volatile ("wfi");
    }
}
