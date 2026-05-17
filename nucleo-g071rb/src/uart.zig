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

    /// One-shot RX service for a USART2 IRQ handler: clears overrun /
    /// frame / noise flags and returns the next byte if RXNE is set.
    /// Returns `null` when the IRQ fired for some other reason (or once
    /// the RDR has been drained on this entry).
    pub fn serviceRx(self: Usart) ?u8 {
        const isr = self.periph.ISR.read();
        if (isr.ORE == 1 or isr.FE == 1 or isr.NF == 1)
            self.periph.ICR.write(.{ .ORECF = isr.ORE, .FECF = isr.FE, .NCF = isr.NF });
        if (isr.RXNE == 0) return null;
        return @truncate(self.periph.RDR.read().RDR);
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
