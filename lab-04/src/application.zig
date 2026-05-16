const board = @import("board");
const common = @import("common");
const erd_core = @import("erd_core");
const timer = erd_core.timer;
const CommandBuffer = common.CommandBuffer;
const parser = @import("parser.zig");

const serial = board.Hardware.serial;

const CMD_BUF_SIZE = 20;
var cmd_storage: [CMD_BUF_SIZE]u8 = .{0} ** CMD_BUF_SIZE;

pub const Application = struct {
    blink_timer: timer.Timer = .{},
    cmd: CommandBuffer = .{ .buf = &cmd_storage },

    pub fn init(self: *Application, timer_module: *timer.TimerModule) void {
        timer_module.startPeriodic(&self.blink_timer, 1000, null, &onBlinkTimer);
        serial.puts("Lab 04: UART Ring Buffer + Command Parser\r\n");
        serial.puts("Commands: STOP, START, CLEAR\r\n> ");
    }

    pub fn processChar(self: *Application, c: u8) void {
        switch (c) {
            '\r' => self.handleEnter(),
            0x08, 0x7F => self.handleBackspace(),
            else => {
                if (c >= 0x20 and c <= 0x7E) {
                    self.cmd.add(c);
                    serial.putc(c);
                }
            },
        }
    }

    fn handleEnter(self: *Application) void {
        self.cmd.add('\r');
        serial.puts("\r\n");

        dumpBuffer(self.cmd.buf);

        if (self.cmd.overflowed) {
            serial.puts("Error: ring buffer overflow\r\n");
        } else {
            var buf: [CMD_BUF_SIZE]u8 = undefined;
            const input = self.cmd.currentInput(&buf);
            const cmd_str = if (input.len > 0 and input[input.len - 1] == '\r')
                input[0 .. input.len - 1]
            else
                input;

            switch (parser.parse(cmd_str)) {
                .stop => serial.puts("STOP command received\r\n"),
                .start => serial.puts("START command received\r\n"),
                .clear => serial.puts("CLEAR command received\r\n"),
                .unknown => {
                    if (cmd_str.len > 0)
                        serial.puts("undefined command\r\n")
                    else
                        serial.puts("\r\n");
                },
            }
        }

        self.cmd.resetInput();
        serial.puts("> ");
    }

    fn handleBackspace(self: *Application) void {
        if (self.cmd.removeLast()) {
            serial.putc(0x08);
            serial.putc(' ');
            serial.putc(0x08);
        }
    }

    fn dumpBuffer(buf: []const u8) void {
        serial.puts("Ring buffer:\r\n");
        for (buf, 0..) |c, i| {
            serial.putc('[');
            serial.putc('0' + @as(u8, @intCast(i / 10)));
            serial.putc('0' + @as(u8, @intCast(i % 10)));
            serial.puts("] ");
            if (c >= 0x20 and c <= 0x7E) {
                serial.putc(c);
            } else if (c == '\r') {
                serial.puts("\\r");
            } else if (c == '\n') {
                serial.puts("\\n");
            } else {
                serial.putc('.');
            }
            serial.puts("\r\n");
        }
    }

    fn onBlinkTimer(_: ?*anyopaque, _: *timer.TimerModule, _: *timer.Timer) void {
        board.Hardware.led.toggle();
        serial.puts("Lab 04 running\r\n");
    }
};
