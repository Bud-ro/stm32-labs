const chip = @import("chip/STM32G071.zig");

pub const Usart = struct {
    periph: *volatile chip.types.peripherals.USART1,

    pub const Config = struct {
        baud_divider: u16,
    };

    pub fn init(self: Usart, config: Config) void {
        self.periph.BRR.write_raw(config.baud_divider);
        self.periph.CR1.modify(.{ .UE = 1, .TE = 1, .RE = 1 });
    }

    pub fn putc(self: Usart, c: u8) void {
        while (self.periph.ISR.read().TXE == 0) {}
        self.periph.TDR.write_raw(c);
    }

    pub fn puts(self: Usart, s: []const u8) void {
        for (s) |c| self.putc(c);
    }
};
