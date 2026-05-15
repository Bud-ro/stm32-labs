const chip = @import("chip/STM32G071.zig");
const gpio = @import("gpio.zig");
const uart = @import("uart.zig");
const startup = @import("startup.zig");

pub const Hardware = struct {
    pub const led = gpio.Pin(.A, 5);

    pub const serial: uart.Usart = .{ .periph = chip.peripherals.USART2 };

    const usart2_tx = gpio.Pin(.A, 2);
    const usart2_rx = gpio.Pin(.A, 3);

    // 16_000_000 / 115200 ≈ 138.89, rounds to 139 (~0.08% error)
    const baud_divider = 139;
    const systick_reload = 15_999; // 16MHz / 1000 - 1 = 1ms tick

    pub const Config = struct {
        systick_tick: *const fn () void,
    };

    pub fn init(_: *Hardware, config: Config) void {
        chip.peripherals.RCC.IOPENR.modify(.{ .IOPAEN = 1 });
        chip.peripherals.RCC.APBENR1.modify(.{ .USART2EN = 1 });

        led.configure(.{ .mode = .output });
        usart2_tx.configure(.{ .mode = .alternate, .af = 1 });
        usart2_rx.configure(.{ .mode = .alternate, .af = 1 });

        serial.init(.{ .baud_divider = baud_divider });

        startup.setSysTickCallback(config.systick_tick);

        const systick = chip.peripherals.SysTick;
        systick.RVR.write_raw(systick_reload);
        systick.CVR.write_raw(0);
        systick.CSR.write(.{ .CLKSOURCE = 1, .TICKINT = 1, .ENABLE = 1 });
    }
};
