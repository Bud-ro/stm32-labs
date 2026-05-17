const board = @import("board");
const common = @import("common");
const class_board = @import("class_board");
const erd_core = @import("erd_core");
const timer = erd_core.timer;
const CommandBuffer = common.CommandBuffer;
const Tmp102 = class_board.Tmp102;
const Fram = class_board.Mb85rs64v;
const parser = @import("parser.zig");

const serial = board.Hardware.serial;

const CMD_BUF_SIZE = 20;
/// Worst-case TMP102 one-shot conversion time (datasheet: typ 26 ms,
/// max 30 ms). Round up to 35 ms for margin against the 1 ms tick.
const ONE_SHOT_MS: u32 = 35;
const SAMPLE_PERIOD_MS: u32 = 1000;

/// First four bytes of FRAM hold the bookkeeping words (first_addr,
/// last_addr) for the current session. Sample data starts at this
/// offset.
const DATA_START_ADDR: u16 = 0x0004;
const ENTRY_BYTES: u16 = 2;

var cmd_storage: [CMD_BUF_SIZE]u8 = .{0} ** CMD_BUF_SIZE;

pub const Application = struct {
    timer_module: *timer.TimerModule,
    sensor: Tmp102,
    fram: Fram,
    blink_timer: timer.Timer = .{},
    sample_timer: timer.Timer = .{},
    conversion_timer: timer.Timer = .{},
    cmd: CommandBuffer = .{ .buf = &cmd_storage },
    /// In-FRAM address words for the current session. Kept mirrored in
    /// RAM so the per-sample fast path only does a single FRAM write
    /// per reading (the address word is rewritten on each sample so
    /// that a power cycle mid-session still leaves a valid `last_addr`
    /// pointing at the most recent entry).
    first_addr: u16 = 0,
    last_addr: u16 = 0,

    /// Start the LED blink heartbeat. Banner print and peripheral init
    /// happen in main() before this is called.
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
                .temp => self.handleTemp(),
                .clear => self.handleClear(),
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

        const prev = self.readBookkeeping();
        if (prev.isUninitialized()) {
            self.first_addr = DATA_START_ADDR;
            self.last_addr = DATA_START_ADDR - ENTRY_BYTES;
        } else {
            // Begin a fresh session immediately after the previous one.
            self.first_addr = prev.last_addr + ENTRY_BYTES;
            self.last_addr = self.first_addr - ENTRY_BYTES;
            if (self.first_addr + ENTRY_BYTES > Fram.SIZE_BYTES) {
                serial.puts("FRAM full - issue CLEAR before starting a new session\r\n");
                return;
            }
        }
        self.writeBookkeeping();

        serial.puts("START - sampling at 1 Hz (logging to FRAM)\r\n");
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

    fn handleTemp(self: *Application) void {
        const state = self.readBookkeeping();
        if (state.isUninitialized()) {
            serial.puts("No data logged - FRAM is uninitialized. Run START first.\r\n");
            return;
        }
        if (state.last_addr < state.first_addr) {
            serial.puts("Current session has no entries yet.\r\n");
            return;
        }
        const count: u16 = (state.last_addr - state.first_addr) / ENTRY_BYTES + 1;

        serial.puts("Session: first=");
        printHex16(state.first_addr);
        serial.puts(" last=");
        printHex16(state.last_addr);
        serial.puts(" count=");
        printUint(count);
        serial.puts("\r\n");

        var addr = state.first_addr;
        var index: u16 = 0;
        while (addr <= state.last_addr) : (addr += ENTRY_BYTES) {
            var entry: [2]u8 = undefined;
            self.fram.read(addr, &entry);
            const raw: u16 = (@as(u16, entry[0]) << 8) | entry[1];
            const signed: i16 = @bitCast(raw);
            const fixed_12: i16 = signed >> 4;

            serial.putc('[');
            printUint(index);
            serial.puts("] @");
            printHex16(addr);
            serial.puts(": ");
            printTemperature(fixed_12);
            index += 1;
        }
    }

    fn handleClear(self: *Application) void {
        if (self.timer_module.isActive(&self.sample_timer)) {
            self.timer_module.stop(&self.sample_timer);
            self.timer_module.stop(&self.conversion_timer);
            serial.puts("(stopped sampling)\r\n");
        }
        serial.puts("Clearing FRAM... ");
        self.fram.clear();
        self.first_addr = 0;
        self.last_addr = 0;
        serial.puts("done\r\n");
    }

    fn onSampleTimer(ctx: ?*anyopaque, _: *timer.TimerModule, _: *timer.Timer) void {
        const self: *Application = @ptrCast(@alignCast(ctx));
        triggerOneShot(self);
    }

    fn onBlinkTimer(_: ?*anyopaque, _: *timer.TimerModule, _: *timer.Timer) void {
        board.Hardware.led.toggle();
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
        const raw_register = self.sensor.readRawRegister() catch {
            serial.puts("TMP102 read failed\r\n");
            return;
        };

        const next_addr = self.last_addr + ENTRY_BYTES;
        if (next_addr + ENTRY_BYTES > Fram.SIZE_BYTES) {
            serial.puts("FRAM full - stopping\r\n");
            self.timer_module.stop(&self.sample_timer);
            return;
        }
        const entry: [2]u8 = .{ @truncate(raw_register >> 8), @truncate(raw_register) };
        self.fram.write(next_addr, &entry);
        self.last_addr = next_addr;
        self.writeLastAddr();

        const fixed_12: i16 = @as(i16, @bitCast(raw_register)) >> 4;
        printTemperature(fixed_12);
    }

    const Bookkeeping = struct {
        first_addr: u16,
        last_addr: u16,

        fn isUninitialized(self: Bookkeeping) bool {
            // Fresh device or post-CLEAR: first_addr is zero. Anything
            // below the data region or beyond the FRAM is treated as
            // bogus and also reset.
            return self.first_addr < DATA_START_ADDR or self.first_addr >= Fram.SIZE_BYTES;
        }
    };

    fn readBookkeeping(self: *Application) Bookkeeping {
        var buf: [4]u8 = undefined;
        self.fram.read(0, &buf);
        return .{
            .first_addr = (@as(u16, buf[0]) << 8) | buf[1],
            .last_addr = (@as(u16, buf[2]) << 8) | buf[3],
        };
    }

    fn writeBookkeeping(self: *Application) void {
        const buf: [4]u8 = .{
            @truncate(self.first_addr >> 8), @truncate(self.first_addr),
            @truncate(self.last_addr >> 8),  @truncate(self.last_addr),
        };
        self.fram.write(0, &buf);
    }

    fn writeLastAddr(self: *Application) void {
        const buf: [2]u8 = .{ @truncate(self.last_addr >> 8), @truncate(self.last_addr) };
        self.fram.write(2, &buf);
    }
};

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
    var digits: [5]u8 = undefined;
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

fn printHex16(n: u16) void {
    serial.puts("0x");
    const nibbles: [4]u4 = .{
        @truncate(n >> 12),
        @truncate(n >> 8),
        @truncate(n >> 4),
        @truncate(n),
    };
    for (nibbles) |nib| {
        const v: u8 = nib;
        serial.putc(if (v < 10) '0' + v else 'A' + v - 10);
    }
}
