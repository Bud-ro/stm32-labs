const chip = @import("chip/STM32G071.zig");
const RingBuffer = @import("common").RingBuffer;

pub const Usart = struct {
    periph: *volatile chip.types.peripherals.USART1,
    tx_ring: ?*RingBuffer = null,

    pub const Config = struct {
        baud_divider: u16,
    };

    pub fn init(self: Usart, config: Config) void {
        self.periph.BRR.write_raw(config.baud_divider);
        self.periph.CR1.modify(.{ .UE = 1, .TE = 1, .RE = 1 });
    }

    pub fn putc(self: Usart, c: u8) void {
        if (self.tx_ring) |ring| {
            _ = ring.push(c);
        } else {
            while (self.periph.ISR.read().TXE == 0) {}
            self.periph.TDR.write_raw(c);
        }
    }

    pub fn puts(self: Usart, s: []const u8) void {
        for (s) |c| self.putc(c);
    }

    pub fn drainTx(self: Usart) bool {
        const ring = self.tx_ring orelse return false;
        var sent = false;
        while (self.periph.ISR.read().TXE == 1) {
            const byte = ring.pop() orelse break;
            self.periph.TDR.write_raw(byte);
            sent = true;
        }
        return sent;
    }

    pub fn txPending(self: Usart) bool {
        const ring = self.tx_ring orelse return false;
        return ring.nonEmpty();
    }
};
