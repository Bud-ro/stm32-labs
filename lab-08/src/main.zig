const board = @import("board");
const app_mod = @import("application");
const Application = app_mod.Application;
const erd_core = @import("erd_core");

const SYSCLK: board.clock.Config = .pll_32mhz;

var timer_module: erd_core.timer.TimerModule = .{};
var application: Application = .{ .timer_module = &timer_module };

fn sysTick() callconv(.c) void {
    timer_module.incrementCurrentTime(1);
}

fn usart2Isr() callconv(.c) void {
    if (board.Hardware.serial.serviceRx()) |c| application.processChar(c);
}

fn encoderEdge() callconv(.c) void {
    app_mod.onEncoderEdge();
}

pub export const vector_table linksection(".isr_vector") =
    board.startup.vectorTable(.{
        .SysTick = &sysTick,
        .USART2 = &usart2Isr,
        .EXTI0_1 = &encoderEdge,
    });

pub fn main() noreturn {
    board.Hardware.init(SYSCLK);
    board.Hardware.enableMotorPwm(SYSCLK, .{});

    // Encoder on PA0 -> EXTI0, rising edge. PA0 defaults to *analog*
    // mode on STM32G0 (GPIOA_MODER reset = 0xEBFF_FFFF), so flip it to
    // input first; otherwise the Schmitt trigger sees nothing and EXTI
    // never fires.
    board.gpio.Pin(.A, 0).configure(.{ .mode = .input });
    board.exti.enable(.A, 0, .rising);

    const serial = board.Hardware.serial;
    serial.puts("Lab 08: motor PWM + encoder RPM\r\n");
    serial.puts("Commands: DUTY<n> (0..100), HALT\r\n> ");

    application.start();

    while (true) {
        var had_work = false;
        if (board.Hardware.runUarts()) had_work = true;
        if (timer_module.run()) had_work = true;
        if (!had_work) asm volatile ("wfi");
    }
}
