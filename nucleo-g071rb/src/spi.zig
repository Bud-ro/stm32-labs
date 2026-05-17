/// SPI master driver for STM32G0 (polled, 8-bit, full-duplex).
///
/// Software-managed NSS: the application is responsible for asserting
/// CS (typically a plain GPIO) around each transaction. That matches
/// the typical Arduino-shield wiring where the slave's CS isn't on a
/// peripheral-NSS-capable pin.
///
/// The DR register is intentionally accessed as a byte through a
/// pointer cast - STM32G0 SPI uses the access width of the store to
/// pack/unpack the FIFO, so an 8-bit store sends exactly one byte.
const chip = @import("chip/STM32G071.zig");

pub const Mode = struct {
    /// CPOL: clock idle polarity (0 = idle low).
    cpol: u1 = 0,
    /// CPHA: clock phase (0 = sample on first edge).
    cpha: u1 = 0,
};

pub const Config = struct {
    /// SPI kernel clock in Hz (PCLK on this BSP).
    kernel_clock_hz: u32,
    /// Max bus rate in Hz. Driver picks the slowest available prescaler
    /// that still meets or exceeds the rate, capped at PCLK/2.
    bus_rate_hz: u32 = 4_000_000,
    mode: Mode = .{},
};

pub const Spi = struct {
    periph: *volatile chip.types.peripherals.SPI1,

    pub fn init(self: Spi, comptime config: Config) void {
        self.periph.CR1.modify(.{ .SPE = 0 });
        // 8-bit data frame, RXNE asserts on each byte.
        self.periph.CR2.write(.{ .DS = 0b0111, .FRXTH = 1 });
        self.periph.CR1.write(.{
            .MSTR = 1,
            .BR = comptime brDivider(config.kernel_clock_hz, config.bus_rate_hz),
            .CPOL = config.mode.cpol,
            .CPHA = config.mode.cpha,
            .SSM = 1,
            .SSI = 1,
        });
        self.periph.CR1.modify(.{ .SPE = 1 });
    }

    /// Clock one byte out (and one in). The full-duplex round-trip is
    /// the natural primitive - TX-only and RX-only are just patterns
    /// over it.
    pub fn transferByte(self: Spi, tx: u8) u8 {
        const dr8: *volatile u8 = @ptrCast(&self.periph.DR);
        while (self.periph.SR.read().TXE == 0) {}
        dr8.* = tx;
        while (self.periph.SR.read().RXNE == 0) {}
        return dr8.*;
    }

    /// Send `data`, discard whatever the slave drives back.
    pub fn transmit(self: Spi, data: []const u8) void {
        for (data) |byte| _ = self.transferByte(byte);
        while (self.periph.SR.read().BSY == 1) {}
    }

    /// Clock dummy bytes out, store the slave's response into `buf`.
    pub fn receive(self: Spi, buf: []u8) void {
        for (buf) |*byte| byte.* = self.transferByte(0xFF);
        while (self.periph.SR.read().BSY == 1) {}
    }
};

/// Pick the smallest BR field that keeps the bus at or below the
/// requested rate. BR encodes f_PCLK / 2^(BR+1).
fn brDivider(comptime kernel_hz: u32, comptime bus_hz: u32) u3 {
    var br: u3 = 0;
    while (br < 7) : (br += 1) {
        const div: u32 = @as(u32, 2) << br;
        if (kernel_hz / div <= bus_hz) return br;
    }
    return 7;
}
