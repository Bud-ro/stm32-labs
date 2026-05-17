const board = @import("board");
const common = @import("common");
const erd_core = @import("erd_core");
const timer = erd_core.timer;
const CommandBuffer = common.CommandBuffer;
const parser = @import("parser.zig");

const serial = board.Hardware.serial;

const CMD_BUF_SIZE = 20;
/// Rising-edge encoder pulses per *output shaft* revolution. The
/// DG01D-E has a single-channel Hall sensor reading a 6-pole magnet
/// on the motor shaft (3 N + 3 S alternating), which gives 3 rising
/// edges per motor revolution. Coupled to the 1:48 gearbox that
/// becomes 3 * 48 = 144 edges per output-shaft revolution.
/// See: https://cdn.sparkfun.com/assets/8/3/b/e/4/DS-16413-DG01D-E_Motor_with_Encoder.pdf
const ENCODER_PULSES_PER_REV: u32 = 144;
const RPM_PERIOD_MS: u32 = 1000;

var cmd_storage: [CMD_BUF_SIZE]u8 = .{0} ** CMD_BUF_SIZE;

/// Updated from the encoder ISR, drained by the 1 Hz RPM tick. `volatile`
/// here is just to flag the cross-context access for the reader - the
/// real ordering guarantee on Cortex-M0+ is that the ISR runs to
/// completion before the main loop resumes, so word-aligned u32 RMW in
/// the main loop is safe.
var encoder_pulses: u32 = 0;

pub const Application = struct {
    timer_module: *timer.TimerModule,
    rpm_timer: timer.Timer = .{},
    blink_timer: timer.Timer = .{},
    cmd: CommandBuffer = .{ .buf = &cmd_storage },

    pub fn start(self: *Application) void {
        self.timer_module.startPeriodic(&self.rpm_timer, RPM_PERIOD_MS, self, &onRpmTick);
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
                .duty => |percent| handleDuty(percent),
                .halt => handleHalt(),
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

    fn handleDuty(percent: u8) void {
        board.Hardware.motor_pwm.setDuty(percent);
        serial.puts("DUTY ");
        printUint(percent);
        serial.puts("% set\r\n");
    }

    fn handleHalt() void {
        board.Hardware.motor_pwm.setDuty(0);
        serial.puts("HALT - motor stopped\r\n");
    }

    fn onBlinkTimer(_: ?*anyopaque, _: *timer.TimerModule, _: *timer.Timer) void {
        board.Hardware.led.toggle();
    }

    fn onRpmTick(_: ?*anyopaque, _: *timer.TimerModule, _: *timer.Timer) void {
        // Snapshot-and-reset the encoder counter. On M0+ this is safe
        // against the EXTI ISR because the ISR runs to completion
        // outside the main loop - we won't interleave with a half-
        // updated value.
        const pulses = encoder_pulses;
        encoder_pulses = 0;

        const rpm = (pulses * 60) / ENCODER_PULSES_PER_REV;
        serial.puts("RPM: ");
        printUint(rpm);
        serial.puts(" (");
        printUint(pulses);
        serial.puts(" pulses/s)\r\n");
    }
};

/// Wired into the BSP's EXTI0_1 vector. The shield's ENCODER signal is
/// on PA0 -> EXTI line 0, rising-edge triggered.
pub fn onEncoderEdge() void {
    board.exti.clearPending(0);
    encoder_pulses +%= 1;
}

fn printUint(n: u32) void {
    if (n == 0) {
        serial.putc('0');
        return;
    }
    var digits: [10]u8 = undefined;
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
