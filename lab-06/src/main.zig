const board = @import("board");
const common = @import("common");
const class_board = @import("class_board");
const Application = @import("application").Application;
const erd_core = @import("erd_core");

const SYSCLK: board.clock.Config = .pll_32mhz;

var timer_module: erd_core.timer.TimerModule = .{};
var application: Application = undefined;
var blinky: common.Blinky = .{};

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
    board.Hardware.enableI2c1(SYSCLK, .{ .mode = .standard_100k });

    const serial = board.Hardware.serial;
    serial.puts("Lab 06: TMP102 over I2C1\r\n");
    const sensor = class_board.Tmp102.init(board.Hardware.i2c1_bus) catch blk: {
        serial.puts("TMP102 init FAILED - check wiring\r\n");
        break :blk class_board.Tmp102{ .bus = board.Hardware.i2c1_bus };
    };
    serial.puts("Commands: START, STOP\r\n> ");

    application = .{ .timer_module = &timer_module, .sensor = sensor };
    blinky.init(&timer_module, board.Hardware.led);

    while (true) {
        var had_work = false;
        if (board.Hardware.runUarts()) had_work = true;
        if (timer_module.run()) had_work = true;
        if (!had_work) asm volatile ("wfi");
    }
}
