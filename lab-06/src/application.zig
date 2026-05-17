const board = @import("board");
const common = @import("common");
const class_board = @import("class_board");
const erd_core = @import("erd_core");
const timer = erd_core.timer;
const CommandBuffer = common.CommandBuffer;
const Tmp102 = class_board.Tmp102;
const parser = @import("parser.zig");

const serial = board.Hardware.serial;

const CMD_BUF_SIZE = 20;
/// Worst-case TMP102 one-shot conversion time (datasheet: typ 26 ms,
/// max 30 ms). Round up to 35 ms for margin against the 1 ms tick.
const ONE_SHOT_MS: u32 = 35;
const SAMPLE_PERIOD_MS: u32 = 1000;

var cmd_storage: [CMD_BUF_SIZE]u8 = .{0} ** CMD_BUF_SIZE;

pub const Application = struct {
    timer_module: *timer.TimerModule,
    sensor: Tmp102,
    blink_timer: timer.Timer = .{},
    sample_timer: timer.Timer = .{},
    conversion_timer: timer.Timer = .{},
    cmd: CommandBuffer = .{ .buf = &cmd_storage },

    /// Start the LED blink heartbeat. Banner print and TMP102 init are
    /// done in main() before this is called - Application here just
    /// wires the periodic timer the super-loop will service.
    pub fn start(self: *Application) void {
        self.timer_module.startPeriodic(&self.blink_timer, 1000, null, &onBlinkTimer);
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
        serial.puts("\r\n");

        if (self.cmd.overflowed) {
            serial.puts("Error: ring buffer overflow\r\n");
        } else {
            var buf: [CMD_BUF_SIZE]u8 = undefined;
            const cmd_str = self.cmd.currentInput(&buf);

            switch (parser.parse(cmd_str)) {
                .start => self.handleStart(),
                .stop => self.handleStop(),
                .unknown => {
                    if (cmd_str.len > 0) serial.puts("undefined command\r\n");
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

    fn handleStart(self: *Application) void {
        if (self.timer_module.isActive(&self.sample_timer)) {
            serial.puts("already sampling\r\n");
            return;
        }
        serial.puts("START - sampling at 1 Hz\r\n");
        triggerOneShot(self);
        self.timer_module.startPeriodic(&self.sample_timer, SAMPLE_PERIOD_MS, self, &onSampleTimer);
    }

    fn handleStop(self: *Application) void {
        if (!self.timer_module.isActive(&self.sample_timer)) {
            serial.puts("not sampling\r\n");
            return;
        }
        self.timer_module.stop(&self.sample_timer);
        self.timer_module.stop(&self.conversion_timer);
        serial.puts("STOP - sampling halted\r\n");
    }

    fn onSampleTimer(ctx: ?*anyopaque, _: *timer.TimerModule, _: *timer.Timer) void {
        const self: *Application = @ptrCast(@alignCast(ctx));
        triggerOneShot(self);
    }

    fn triggerOneShot(self: *Application) void {
        self.sensor.triggerOneShot() catch {
            serial.puts("TMP102 trigger failed\r\n");
            return;
        };
        self.timer_module.startOneShot(&self.conversion_timer, ONE_SHOT_MS, self, &onConversionDone);
    }

    fn onConversionDone(ctx: ?*anyopaque, _: *timer.TimerModule, _: *timer.Timer) void {
        const self: *Application = @ptrCast(@alignCast(ctx));
        const raw = self.sensor.readTemperatureRaw() catch {
            serial.puts("TMP102 read failed\r\n");
            return;
        };
        printTemperature(raw);
    }

    fn onBlinkTimer(_: ?*anyopaque, _: *timer.TimerModule, _: *timer.Timer) void {
        board.Hardware.led.toggle();
    }
};

/// Format a signed 12-bit TMP102 reading (1 LSB = 1/16 °C) as
/// "Temperature: ±DD.DDDD C\r\n". Manual fixed-point avoids dragging
/// in std.fmt.
fn printTemperature(raw_12: i16) void {
    serial.puts("Temperature: ");
    var v = raw_12;
    if (v < 0) {
        serial.putc('-');
        v = -v;
    }
    const abs: u16 = @intCast(v);
    const int_part: u16 = abs >> 4;
    const frac_10000ths: u16 = (abs & 0xF) * 625;

    printUint(int_part);
    serial.putc('.');
    serial.putc('0' + @as(u8, @intCast(frac_10000ths / 1000)));
    serial.putc('0' + @as(u8, @intCast((frac_10000ths / 100) % 10)));
    serial.putc('0' + @as(u8, @intCast((frac_10000ths / 10) % 10)));
    serial.putc('0' + @as(u8, @intCast(frac_10000ths % 10)));
    serial.puts(" C\r\n");
}

fn printUint(n: u16) void {
    if (n == 0) {
        serial.putc('0');
        return;
    }
    var digits: [3]u8 = undefined;
    var v = n;
    var i: usize = 0;
    while (v > 0) : (i += 1) {
        digits[i] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
    }
    while (i > 0) {
        i -= 1;
        serial.putc(digits[i]);
    }
}
