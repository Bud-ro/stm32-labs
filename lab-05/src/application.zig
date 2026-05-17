const board = @import("board");
const erd_core = @import("erd_core");
const timer = erd_core.timer;

pub const Application = struct {
    banner_timer: timer.Timer = .{},

    pub fn init(self: *Application, timer_module: *timer.TimerModule) void {
        timer_module.startPeriodic(&self.banner_timer, 1000, null, &onBannerTimer);
    }

    fn onBannerTimer(_: ?*anyopaque, _: *timer.TimerModule, _: *timer.Timer) void {
        board.Hardware.serial.puts("Lab 05: SYSCLK = HCLK = PCLK = 32 MHz\r\n");
    }
};
