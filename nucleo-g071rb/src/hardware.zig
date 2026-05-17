//! NUCLEO-G071RB board hardware namespace.
//!
//! `Hardware.init(clock)` programs the RCC + USART2 + optional SysTick
//! for the requested SYSCLK. Subsequent `enableX(clock, ...)` calls
//! take the same `clock` so the BSP can derive peripheral kernel
//! settings (I2C TIMINGR, etc.) at comptime.
//!
//! Clock-independent handles (`Hardware.led`, `Hardware.serial`,
//! `Hardware.i2c1_bus`) are accessible directly without threading
//! `clock`.
//!
//! Example:
//!
//!   const board = @import("board");
//!   const SYSCLK: board.clock.Config = .pll_32mhz;
//!
//!   fn sysTick() callconv(.c) void { /* ... */ }
//!
//!   pub export const vector_table linksection(".isr_vector") =
//!       board.startup.vectorTable(.{ .SysTick = &sysTick });
//!
//!   pub fn main() noreturn {
//!       board.Hardware.init(SYSCLK);
//!       board.Hardware.enableI2c1(SYSCLK, .{ .mode = .standard_100k });
//!       board.Hardware.led.toggle();
//!   }
//!
//! `init` reads the lab's `vector_table` at comptime and:
//!   - programs SysTick (1 ms tick) if `.SysTick` is overridden
//!   - unmasks USART2 RX (RXNEIE + NVIC) if `.USART2` is overridden
//! Labs that want UART RX write a one-line USART2 handler that calls
//! `Hardware.serial.serviceRx()`.

const root = @import("root");
const chip = @import("chip/STM32G071.zig");
const clock = @import("clock.zig");
const gpio = @import("gpio.zig");
const uart = @import("uart.zig");
const i2c = @import("i2c.zig");
const spi = @import("spi.zig");
const RingBuffer = @import("common").RingBuffer;

const usart2 = chip.peripherals.USART2;
const i2c1 = chip.peripherals.I2C1;
const spi1 = chip.peripherals.SPI1;

var tx_storage: [256]u8 = undefined;
var tx_ring: RingBuffer = .{ .buf = &tx_storage };

/// True at comptime when the lab's `vector_table` overrides `field`
/// with a non-default handler. Used by `init` to gate SysTick
/// programming and USART2 RX unmasking.
fn hasVectorOverride(comptime field: []const u8) bool {
    if (!@hasDecl(root, "vector_table")) return false;
    return @field(root.vector_table, field) != chip.unhandled;
}

pub const Hardware = struct {
    /// Onboard user LED (LD4) on PA5. Configured as output by `init`.
    pub const led = gpio.Pin(.A, 5);

    /// USART2 (ST-Link VCP) at 115_200-8N1, TX backed by a ring buffer
    /// that the super-loop drains via `runUarts()`.
    pub const serial: uart.Usart = .{ .periph = usart2, .tx_ring = &tx_ring };

    /// I2C1 master on the Arduino-style header (PB8 = SCL/D15,
    /// PB9 = SDA/D14). Call `enableI2c1` before use.
    pub const i2c1_bus: i2c.I2c = .{ .periph = i2c1 };

    /// SPI1 master on the class-shield wiring (SCK=PB3, MISO=PA6,
    /// MOSI=PA7). CS is left to the slave driver. Call `enableSpi1`
    /// before use.
    pub const spi1_bus: spi.Spi = .{ .periph = spi1 };

    const usart2_tx = gpio.Pin(.A, 2);
    const usart2_rx = gpio.Pin(.A, 3);
    const i2c1_scl = gpio.Pin(.B, 8);
    const i2c1_sda = gpio.Pin(.B, 9);
    const spi1_sck = gpio.Pin(.B, 3);
    const spi1_miso = gpio.Pin(.A, 6);
    const spi1_mosi = gpio.Pin(.A, 7);

    /// Lab-facing I2C1 settings. Kernel clock is derived from the
    /// `clock` passed to `enableI2c1`; callers only pick the bus mode.
    pub const I2c1Config = struct {
        mode: i2c.Mode = .standard_100k,
    };

    /// Lab-facing SPI1 settings. Kernel clock comes from the `clock`
    /// passed to `enableSpi1`.
    pub const Spi1Config = struct {
        bus_rate_hz: u32 = 4_000_000,
        mode: spi.Mode = .{},
    };

    /// Apply `clock`, configure the LED + USART2 (TX always, RX if the
    /// lab overrides `.USART2`), and program SysTick for a 1 ms tick
    /// if the lab overrides `.SysTick`.
    pub fn init(comptime board_clock: clock.Config) void {
        board_clock.apply();

        chip.peripherals.RCC.IOPENR.modify(.{ .IOPAEN = 1 });
        chip.peripherals.RCC.APBENR1.modify(.{ .USART2EN = 1 });

        led.configure(.{ .mode = .output });
        usart2_tx.configure(.{ .mode = .alternate, .af = 1 });
        usart2_rx.configure(.{ .mode = .alternate, .af = 1 });

        serial.init(.{ .baud_divider = board_clock.baudDivider(115_200) });

        if (comptime hasVectorOverride("USART2")) {
            usart2.CR1.modify(.{ .RXNEIE = 1 });
            chip.peripherals.NVIC.ISER.write_raw(1 << chip.irqIndex("USART2"));
        }

        if (comptime hasVectorOverride("SysTick")) {
            const systick = chip.peripherals.SysTick;
            systick.RVR.write_raw(board_clock.systickReload1ms());
            systick.CVR.write_raw(0);
            systick.CSR.write(.{ .CLKSOURCE = 1, .TICKINT = 1, .ENABLE = 1 });
        }
    }

    /// Configure I2C1 on PB8/PB9 in master mode. `board_clock` must
    /// match the one passed to `init`; it drives the TIMINGR solver.
    pub fn enableI2c1(comptime board_clock: clock.Config, comptime cfg: I2c1Config) void {
        chip.peripherals.RCC.IOPENR.modify(.{ .IOPBEN = 1 });
        chip.peripherals.RCC.APBENR1.modify(.{ .I2C1EN = 1 });
        i2c1_scl.configure(.{ .mode = .alternate, .af = 6, .output_type = .open_drain, .pull = .up });
        i2c1_sda.configure(.{ .mode = .alternate, .af = 6, .output_type = .open_drain, .pull = .up });
        i2c1_bus.init(.{
            .kernel_clock_hz = board_clock.hclkHz(),
            .mode = cfg.mode,
        });
    }

    /// Configure SPI1 in master mode. SCK lives on PB3 to keep PA5
    /// free for the on-board LED; MISO/MOSI use the Arduino-standard
    /// PA6/PA7. CS is owned by the slave driver. `board_clock` must
    /// match the one passed to `init`; it drives the BR prescaler
    /// solver.
    pub fn enableSpi1(comptime board_clock: clock.Config, comptime cfg: Spi1Config) void {
        chip.peripherals.RCC.IOPENR.modify(.{ .IOPBEN = 1 });
        chip.peripherals.RCC.APBENR2.modify(.{ .SPI1EN = 1 });
        spi1_sck.configure(.{ .mode = .alternate, .af = 0 });
        spi1_miso.configure(.{ .mode = .alternate, .af = 0 });
        spi1_mosi.configure(.{ .mode = .alternate, .af = 0 });
        spi1_bus.init(.{
            .kernel_clock_hz = board_clock.hclkHz(),
            .bus_rate_hz = cfg.bus_rate_hz,
            .mode = cfg.mode,
        });
    }

    /// Drain pending TX bytes from `serial`'s ring buffer. Returns
    /// true if anything got sent or anything still pending. Call from
    /// the super-loop; the WFI gate reads it.
    pub fn runUarts() bool {
        const sent = serial.drainTx();
        return sent or serial.txPending();
    }
};
