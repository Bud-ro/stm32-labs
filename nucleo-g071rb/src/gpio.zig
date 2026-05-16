const std = @import("std");
const chip = @import("chip/STM32G071.zig");

pub const Port = enum { A, B, C, D, F };
pub const Mode = enum(u2) { input = 0b00, output = 0b01, alternate = 0b10, analog = 0b11 };
pub const OutputType = enum(u1) { push_pull = 0, open_drain = 1 };
pub const Pull = enum(u2) { none = 0b00, up = 0b01, down = 0b10 };

const Gpio = chip.types.peripherals.GPIOB;

pub const PinConfig = struct {
    mode: Mode,
    af: ?u4 = null,
    output_type: OutputType = .push_pull,
    pull: Pull = .none,
};

pub fn Pin(comptime port: Port, comptime pin: u4) type {
    return struct {
        const gpio: *volatile Gpio = @ptrCast(gpioPort(port));
        const moder_field = std.fmt.comptimePrint("MODER{d}", .{pin});
        const odr_field = std.fmt.comptimePrint("ODR{d}", .{pin});
        const idr_field = std.fmt.comptimePrint("IDR{d}", .{pin});
        const otyper_field = std.fmt.comptimePrint("OT{d}", .{pin});
        const pupdr_field = std.fmt.comptimePrint("PUPDR{d}", .{pin});

        pub fn configure(comptime config: PinConfig) void {
            gpio.MODER.modify_one(moder_field, @intFromEnum(config.mode));
            if (config.output_type != .push_pull)
                gpio.OTYPER.modify_one(otyper_field, @intFromEnum(config.output_type));
            if (config.pull != .none)
                gpio.PUPDR.modify_one(pupdr_field, @intFromEnum(config.pull));
            if (config.af) |af_val| {
                const afsel_field = std.fmt.comptimePrint("AFSEL{d}", .{pin});
                if (pin < 8) {
                    gpio.AFRL.modify_one(afsel_field, af_val);
                } else {
                    gpio.AFRH.modify_one(afsel_field, af_val);
                }
            }
        }

        pub fn set() void {
            gpio.BSRR.write_raw(@as(u32, 1) << @as(u5, pin));
        }

        pub fn clear() void {
            gpio.BSRR.write_raw(@as(u32, 1) << (@as(u5, pin) + 16));
        }

        pub fn toggle() void {
            if (@field(gpio.ODR.read(), odr_field) != 0) {
                clear();
            } else {
                set();
            }
        }

        pub fn read() u1 {
            return @field(gpio.IDR.read(), idr_field);
        }
    };
}

fn gpioPort(comptime port: Port) *volatile Gpio {
    return switch (port) {
        .A => @ptrCast(chip.peripherals.GPIOA),
        .B => chip.peripherals.GPIOB,
        .C => chip.peripherals.GPIOC,
        .D => chip.peripherals.GPIOD,
        .F => chip.peripherals.GPIOF,
    };
}
