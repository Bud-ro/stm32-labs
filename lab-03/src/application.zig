const board = @import("board");
const erd_core = @import("erd_core");
const timer = erd_core.timer;

pub const Application = struct {
    print_timer: timer.Timer = .{},

    pub fn init(self: *Application, timer_module: *timer.TimerModule) void {
        timer_module.startPeriodic(&self.print_timer, 1000, null, &onPrintTimer);
    }

    fn onPrintTimer(_: ?*anyopaque, _: *timer.TimerModule, _: *timer.Timer) void {
        board.Hardware.led.toggle();
        board.Hardware.serial.puts("Not putting my name here in the Zig version :D\r\n");
    }
};
