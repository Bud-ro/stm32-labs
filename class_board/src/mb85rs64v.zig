//! MB85RS64V SPI FRAM driver.
//!
//! The MB85RS64V is a Fujitsu 64 Kbit ferroelectric RAM (8192 × 8) on
//! SPI mode 0. FRAM is byte-addressable, write-without-erase, and has
//! no page boundary - a single WRITE command can stream all 8192 cells.
//!
//! Each WRITE must be preceded by a WREN (write-enable) command; the
//! peripheral auto-clears the write-enable latch when CS rises after
//! a WRITE, so we issue WREN+WRITE as two separate CS-asserted bursts.
//!
//! On this shield the chip-select pin is fixed (PB6), so the driver
//! owns it directly rather than taking a CS handle from the caller.
const board = @import("board");
const spi = board.spi;
const gpio = board.gpio;

const cs = gpio.Pin(.B, 0);

const CMD_WREN: u8 = 0x06;
const CMD_WRITE: u8 = 0x02;
const CMD_READ: u8 = 0x03;
const CMD_RDID: u8 = 0x9F;

/// Per Fujitsu datasheet: manufacturer ID 0x04 (Fujitsu),
/// continuation 0x7F, product 0x03 0x02 for MB85RS64V.
const EXPECTED_ID: [4]u8 = .{ 0x04, 0x7F, 0x03, 0x02 };

pub const Error = error{NotPresent};

pub const Mb85rs64v = struct {
    pub const SIZE_BYTES: u16 = 8192;

    bus: spi.Spi,

    /// Bring the CS pin up, then probe the device via RDID. Returns
    /// `Error.NotPresent` if the ID doesn't match Fujitsu's MB85RS64V.
    pub fn init(bus: spi.Spi) Error!Mb85rs64v {
        cs.configure(.{ .mode = .output });
        cs.set();

        const self: Mb85rs64v = .{ .bus = bus };
        const id = self.readId();
        for (id, EXPECTED_ID) |actual, expected| {
            if (actual != expected) return Error.NotPresent;
        }
        return self;
    }

    /// Clock out RDID and return the 4-byte device identifier. Useful
    /// for diagnostics when `init` returns `NotPresent`.
    pub fn readId(self: Mb85rs64v) [4]u8 {
        var id: [4]u8 = undefined;
        cs.clear();
        self.bus.transmit(&.{CMD_RDID});
        self.bus.receive(&id);
        cs.set();
        return id;
    }

    pub fn read(self: Mb85rs64v, addr: u16, buf: []u8) void {
        cs.clear();
        self.bus.transmit(&.{ CMD_READ, @truncate(addr >> 8), @truncate(addr) });
        self.bus.receive(buf);
        cs.set();
    }

    pub fn write(self: Mb85rs64v, addr: u16, data: []const u8) void {
        self.writeEnable();
        cs.clear();
        self.bus.transmit(&.{ CMD_WRITE, @truncate(addr >> 8), @truncate(addr) });
        self.bus.transmit(data);
        cs.set();
    }

    /// Zero all 8192 cells. Uses a single WRITE op starting at 0 - FRAM
    /// has no page boundary so the sequence streams the whole device in
    /// one burst.
    pub fn clear(self: Mb85rs64v) void {
        self.writeEnable();
        cs.clear();
        self.bus.transmit(&.{ CMD_WRITE, 0, 0 });
        for (0..Mb85rs64v.SIZE_BYTES) |_| _ = self.bus.transferByte(0);
        cs.set();
    }

    fn writeEnable(self: Mb85rs64v) void {
        cs.clear();
        self.bus.transmit(&.{CMD_WREN});
        cs.set();
    }
};
