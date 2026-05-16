//! TMP102 temperature sensor driver.
//!
//! The TMP102 is a TI digital temperature sensor on I2C with a 12-bit
//! signed temperature register (0.0625 °C / LSB). The shield board in
//! this lab ties ADD0 to GND, fixing the 7-bit address at 0x48.
//!
//! One-shot operation: with `SD = 1` (shutdown) the device stays idle
//! until a `1` is written to the OS bit. Each OS-write triggers a
//! single conversion that takes <= 30 ms. We never run the device in
//! continuous mode here - that way `START`/`STOP` map directly onto
//! "fire a one-shot every second" / "stop firing one-shots".
const board = @import("board");

const i2c1 = board.Hardware.i2c1_bus;

const SLAVE_ADDR: u7 = 0x48;

const REG_TEMP: u8 = 0x00;
const REG_CONFIG: u8 = 0x01;

/// TMP102 configuration register, MSB-first on the wire.
const Config = packed struct(u16) {
    // LSB on the wire (datasheet "Byte 2") - low bits 7:0.
    _reserved: u4 = 0,
    EM: u1 = 0, // extended-mode (0 = 12-bit temperature)
    AL: u1 = 1, // alert (read-only - high in the reset default)
    CR: u2 = 0b10, // conversion rate (irrelevant in shutdown)
    // MSB on the wire (datasheet "Byte 1") - high bits 15:8.
    SD: u1 = 0, // shutdown mode
    TM: u1 = 0, // thermostat mode
    POL: u1 = 0, // alert polarity
    F: u2 = 0, // fault queue
    R: u2 = 0b11, // resolution (datasheet pin: always reads 11)
    OS: u1 = 0, // one-shot trigger

    fn toBytes(self: Config) [2]u8 {
        const bits: u16 = @bitCast(self);
        return .{ @truncate(bits >> 8), @truncate(bits & 0xFF) };
    }
};

const CONFIG_IDLE: Config = .{ .SD = 1 };
const CONFIG_TRIGGER: Config = .{ .SD = 1, .OS = 1 };

pub const Error = error{TransferFailed};

/// Configure the TMP102 into shutdown mode so subsequent OS-writes
/// produce exactly one conversion each. A NACK on the address byte
/// (surfaced as `Error.TransferFailed`) indicates the sensor is
/// missing or wired wrong.
pub fn initialize() Error!void {
    const idle = CONFIG_IDLE.toBytes();
    const config_write = [_]u8{ REG_CONFIG, idle[0], idle[1] };
    i2c1.write(SLAVE_ADDR, &config_write) catch return Error.TransferFailed;
}

/// Write `OS = 1` to the config register. The chip starts a single
/// conversion and clears OS once it completes; the result lands in the
/// temperature register and `readTemperatureRaw` picks it up after the
/// caller has waited the conversion time (~30 ms worst case).
pub fn triggerOneShot() Error!void {
    const trig = CONFIG_TRIGGER.toBytes();
    const bytes = [_]u8{ REG_CONFIG, trig[0], trig[1] };
    i2c1.write(SLAVE_ADDR, &bytes) catch return Error.TransferFailed;
}

/// Read the temperature register as a sign-extended 12-bit fixed-point
/// value where 1 LSB = 0.0625 °C. The wire format is 16 bits big-endian
/// with the 12 valid bits in the upper half; shifting right by 4 with
/// signed semantics drops the unused LSBs and preserves the sign.
pub fn readTemperatureRaw() Error!i16 {
    var rx: [2]u8 = undefined;
    const reg = [_]u8{REG_TEMP};
    i2c1.writeRead(SLAVE_ADDR, &reg, &rx) catch return Error.TransferFailed;

    const raw_16: u16 = (@as(u16, rx[0]) << 8) | rx[1];
    const signed_16: i16 = @bitCast(raw_16);
    return signed_16 >> 4;
}
