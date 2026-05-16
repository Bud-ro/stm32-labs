/// I2C master driver for STM32G0 (polled).
///
/// The peripheral handles the bit-level protocol; this driver builds
/// the CR2 transfer descriptor and shuttles bytes through TXDR/RXDR
/// in a busy-wait loop. `AUTOEND = 1` lets the hardware emit the
/// terminating STOP on its own once `NBYTES` have moved.
///
/// The TIMINGR value is comptime-derived from the I2C kernel clock so
/// that `Config{ .kernel_clock_hz = ..., .mode = .standard_100k }`
/// produces correct timing for whichever clock source the board picks.
const chip = @import("chip/STM32G071.zig");

pub const Error = error{
    Nack,
    BusError,
    ArbitrationLost,
};

pub const Mode = enum {
    /// 100 kHz, standard mode.
    standard_100k,
    /// 400 kHz, fast mode.
    fast_400k,
};

pub const Config = struct {
    /// I2C peripheral kernel clock in Hz. Must come from whichever
    /// source RCC.CCIPR.I2C1SEL selects (PCLK / SYSCLK / HSI16).
    kernel_clock_hz: u32,
    mode: Mode = .standard_100k,
};

pub const I2c = struct {
    periph: *volatile chip.types.peripherals.I2C1,

    pub fn init(self: I2c, comptime config: Config) void {
        self.periph.CR1.modify(.{ .PE = 0 });
        self.periph.TIMINGR.write_raw(computeTiming(config));
        self.periph.CR1.modify(.{ .PE = 1 });
    }

    /// Master transmit `data` to the 7-bit address `addr`.
    pub fn write(self: I2c, addr: u7, data: []const u8) Error!void {
        try self.beginTransfer(addr, .write, @intCast(data.len), .autoend);
        try self.pumpTx(data);
        try self.waitStop();
    }

    /// Master receive `buf.len` bytes from the 7-bit address `addr`.
    pub fn read(self: I2c, addr: u7, buf: []u8) Error!void {
        try self.beginTransfer(addr, .read, @intCast(buf.len), .autoend);
        try self.pumpRx(buf);
        try self.waitStop();
    }

    /// Combined write-then-read with a repeated START between phases.
    /// Conventional way to read N bytes from a sub-register: send the
    /// register pointer in the write phase, then clock out the data
    /// without releasing the bus.
    pub fn writeRead(self: I2c, addr: u7, write_data: []const u8, read_buf: []u8) Error!void {
        try self.beginTransfer(addr, .write, @intCast(write_data.len), .software_end);
        try self.pumpTx(write_data);
        try self.waitFlag("TC");
        self.armCr2(addr, .read, @intCast(read_buf.len), .autoend);
        try self.pumpRx(read_buf);
        try self.waitStop();
    }

    const Direction = enum { write, read };
    const EndMode = enum { autoend, software_end };

    fn beginTransfer(self: I2c, addr: u7, dir: Direction, nbytes: u8, end_mode: EndMode) Error!void {
        while (self.periph.ISR.read().BUSY == 1) {}
        self.periph.ICR.write(.{ .NACKCF = 1, .STOPCF = 1, .BERRCF = 1, .ARLOCF = 1 });
        self.armCr2(addr, dir, nbytes, end_mode);
    }

    fn armCr2(self: I2c, addr: u7, dir: Direction, nbytes: u8, end_mode: EndMode) void {
        self.periph.CR2.write(.{
            .SADD = @as(u10, addr) << 1,
            .RD_WRN = if (dir == .read) 1 else 0,
            .NBYTES = nbytes,
            .AUTOEND = if (end_mode == .autoend) 1 else 0,
            .START = 1,
        });
    }

    fn pumpTx(self: I2c, data: []const u8) Error!void {
        for (data) |byte| {
            try self.waitFlag("TXIS");
            self.periph.TXDR.write_raw(byte);
        }
    }

    fn pumpRx(self: I2c, buf: []u8) Error!void {
        for (buf) |*byte| {
            try self.waitFlag("RXNE");
            byte.* = @truncate(self.periph.RXDR.read().RXDATA);
        }
    }

    /// Poll ISR until `success_flag` is set, surfacing protocol errors
    /// (NACK / bus error / arbitration loss) as `Error.*`.
    fn waitFlag(self: I2c, comptime success_flag: []const u8) Error!void {
        while (true) {
            const isr = self.periph.ISR.read();
            if (isr.NACKF == 1) {
                self.periph.ICR.write(.{ .NACKCF = 1, .STOPCF = 1 });
                return Error.Nack;
            }
            if (isr.BERR == 1) return Error.BusError;
            if (isr.ARLO == 1) return Error.ArbitrationLost;
            if (@field(isr, success_flag) == 1) return;
        }
    }

    fn waitStop(self: I2c) Error!void {
        try self.waitFlag("STOPF");
        self.periph.ICR.write(.{ .STOPCF = 1 });
    }
};

/// Build a TIMINGR value from the kernel clock + bus mode.
///
/// Timing analysis follows RM0444 §27.4.10:
///   t_PRESC = (PRESC + 1) / f_I2CCLK
///   t_SCLL  = (SCLL + 1)  * t_PRESC
///   t_SCLH  = (SCLH + 1)  * t_PRESC
///
/// The chosen PRESC keeps t_PRESC near 125 ns, which gives plenty of
/// granularity for both standard and fast modes from any of the
/// supported kernel clocks (16 / 32 / 64 MHz).
fn computeTiming(comptime config: Config) u32 {
    const target_presc_hz: u32 = 8_000_000;
    const presc_div: u32 = (config.kernel_clock_hz + target_presc_hz - 1) / target_presc_hz;
    const presc: u32 = presc_div - 1;
    if (presc > 0xF) @compileError("kernel clock too fast for I2C timing solver");

    const t_presc_ns: u32 = (presc_div * 1_000_000_000) / config.kernel_clock_hz;

    const target_low_ns: u32 = switch (config.mode) {
        .standard_100k => 4700,
        .fast_400k => 1300,
    };
    const target_high_ns: u32 = switch (config.mode) {
        .standard_100k => 4000,
        .fast_400k => 600,
    };
    const target_sdadel_ns: u32 = 250;
    const target_scldel_ns: u32 = switch (config.mode) {
        .standard_100k => 1250,
        .fast_400k => 500,
    };

    const scll: u32 = (target_low_ns + t_presc_ns - 1) / t_presc_ns - 1;
    const sclh: u32 = (target_high_ns + t_presc_ns - 1) / t_presc_ns - 1;
    const sdadel: u32 = (target_sdadel_ns + t_presc_ns - 1) / t_presc_ns;
    const scldel: u32 = (target_scldel_ns + t_presc_ns - 1) / t_presc_ns - 1;

    if (scll > 0xFF or sclh > 0xFF or sdadel > 0xF or scldel > 0xF)
        @compileError("I2C timing values out of range");

    return (presc << 28) | (scldel << 20) | (sdadel << 16) | (sclh << 8) | scll;
}
