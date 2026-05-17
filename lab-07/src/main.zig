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
    board.Hardware.enableSpi1(SYSCLK, .{ .bus_rate_hz = 4_000_000 });

    const serial = board.Hardware.serial;
    serial.puts("Lab 07: TMP102 + MB85RS64V FRAM logger\r\n");

    const sensor = class_board.Tmp102.init(board.Hardware.i2c1_bus) catch blk: {
        serial.puts("TMP102 init FAILED - check wiring\r\n");
        break :blk class_board.Tmp102{ .bus = board.Hardware.i2c1_bus };
    };
    const fram = class_board.Mb85rs64v.init(board.Hardware.spi1_bus) catch blk: {
        serial.puts("FRAM init FAILED - ID mismatch, check wiring\r\n");
        break :blk class_board.Mb85rs64v{ .bus = board.Hardware.spi1_bus };
    };
    serial.puts("Commands: START, STOP, TEMP, CLEAR\r\n> ");

    application = .{ .timer_module = &timer_module, .sensor = sensor, .fram = fram };
    blinky.init(&timer_module, board.Hardware.led);

    while (true) {
        var had_work = false;
        if (board.Hardware.runUarts()) had_work = true;
        if (timer_module.run()) had_work = true;
        if (!had_work) asm volatile ("wfi");
    }
}
