const board = @import("board");
const erd_core = @import("erd_core");
const timer = erd_core.timer;

pub const Application = struct {
    blink_timer: timer.Timer = .{},

    pub fn init(self: *Application, timer_module: *timer.TimerModule) void {
        timer_module.startPeriodic(&self.blink_timer, 1000, null, &onBlinkTimer);
    }

    fn onBlinkTimer(_: ?*anyopaque, _: *timer.TimerModule, _: *timer.Timer) void {
        board.Hardware.led.toggle();
        board.Hardware.serial.puts("Lab 05: SYSCLK = HCLK = PCLK = 32 MHz\r\n");
    }
};
