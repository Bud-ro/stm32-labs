const chip = @import("chip/STM32G071.zig");
const clock = @import("clock.zig");
const gpio = @import("gpio.zig");
const uart = @import("uart.zig");
const i2c = @import("i2c.zig");
const startup = @import("startup.zig");
const RingBuffer = @import("ring_buffer.zig").RingBuffer;

const usart2 = chip.peripherals.USART2;
const i2c1 = chip.peripherals.I2C1;

var rx_storage: [64]u8 = undefined;
var tx_storage: [256]u8 = undefined;
var rx_ring: RingBuffer = .{ .buf = &rx_storage };
var tx_ring: RingBuffer = .{ .buf = &tx_storage };
var uart_rx_callback: ?*const fn (u8) void = null;

pub fn usart2RxHandler() callconv(chip.cc) void {
    const isr = usart2.ISR.read();
    if (isr.ORE == 1 or isr.FE == 1 or isr.NF == 1)
        usart2.ICR.write(.{ .ORECF = isr.ORE, .FECF = isr.FE, .NCF = isr.NF });
    if (isr.RXNE == 1) {
        const byte: u8 = @truncate(usart2.RDR.read().RDR);
        _ = rx_ring.push(byte);
    }
}

pub const Hardware = struct {
    pub const led = gpio.Pin(.A, 5);

    pub const serial: uart.Usart = .{ .periph = usart2, .tx_ring = &tx_ring };
    /// I2C1 master on the Arduino-style header (PB8 = SCL/D15,
    /// PB9 = SDA/D14). Call `enableI2c1` before use.
    pub const i2c1_bus: i2c.I2c = .{ .periph = i2c1 };

    const usart2_tx = gpio.Pin(.A, 2);
    const usart2_rx = gpio.Pin(.A, 3);
    const i2c1_scl = gpio.Pin(.B, 8);
    const i2c1_sda = gpio.Pin(.B, 9);

    pub const Config = struct {
        systick_tick: *const fn () void,
        uart_rx: ?*const fn (u8) void = null,
        /// SYSCLK source. Defaults to `.hsi16` (16 MHz reset state); set
        /// to a faster preset like `.pll_32mhz` when the application needs
        /// it. See `clock.zig`.
        clock: clock.Config = .hsi16,
    };

    /// Configure I2C1 on PB8/PB9 in master mode. Caller picks the bus
    /// speed via `config.mode` and supplies the I2C kernel clock (the
    /// default RCC reset selects PCLK, which matches HCLK on this BSP).
    pub fn enableI2c1(_: Hardware, comptime config: i2c.Config) void {
        chip.peripherals.RCC.IOPENR.modify(.{ .IOPBEN = 1 });
        chip.peripherals.RCC.APBENR1.modify(.{ .I2C1EN = 1 });
        i2c1_scl.configure(.{ .mode = .alternate, .af = 6, .output_type = .open_drain, .pull = .up });
        i2c1_sda.configure(.{ .mode = .alternate, .af = 6, .output_type = .open_drain, .pull = .up });
        i2c1_bus.init(config);
    }

    pub fn runUarts(_: Hardware) bool {
        var had_work = serial.drainTx();
        if (rx_ring.pop()) |byte| {
            if (uart_rx_callback) |cb| cb(byte);
            had_work = true;
        }
        return had_work or serial.txPending();
    }

    pub fn init(_: Hardware, config: Config) void {
        config.clock.apply();

        chip.peripherals.RCC.IOPENR.modify(.{ .IOPAEN = 1 });
        chip.peripherals.RCC.APBENR1.modify(.{ .USART2EN = 1 });

        led.configure(.{ .mode = .output });
        usart2_tx.configure(.{ .mode = .alternate, .af = 1 });
        usart2_rx.configure(.{ .mode = .alternate, .af = 1 });

        serial.init(.{ .baud_divider = config.clock.baudDivider(115_200) });

        uart_rx_callback = config.uart_rx;
        if (config.uart_rx != null) {
            usart2.CR1.modify(.{ .RXNEIE = 1 });
            chip.peripherals.NVIC.ISER.write_raw(1 << chip.irqIndex("USART2"));
        }

        startup.setSysTickCallback(config.systick_tick);

        const systick = chip.peripherals.SysTick;
        systick.RVR.write_raw(config.clock.systickReload1ms());
        systick.CVR.write_raw(0);
        systick.CSR.write(.{ .CLKSOURCE = 1, .TICKINT = 1, .ENABLE = 1 });
    }
};
