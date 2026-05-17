//! Heartbeat LED driver. Periodically toggles a GPIO pin off an
//! `erd_core` timer. Lets a lab declare a one-liner heartbeat without
//! plumbing the timer callback by hand.
//!
//! Usage:
//!
//!   var blinky: common.Blinky = .{};
//!   blinky.init(&timer_module, board.Hardware.led);
//!
//! Override the default 1 Hz cadence by setting `.period_ms` before
//! calling `init`:
//!
//!   var blinky: common.Blinky = .{ .period_ms = 250 };
//!
//! `Pin` is any type that exposes a `pub fn toggle() void` - the BSP's
//! `gpio.Pin(.A, 5)` and friends satisfy this.
const erd_core = @import("erd_core");
const timer = erd_core.timer;

pub const Blinky = struct {
    timer: timer.Timer = .{},
    period_ms: u32 = 1000,
    toggle_fn: *const fn () void = undefined,

    /// Register the heartbeat against `timer_module`. `Pin` is a GPIO
    /// type whose `toggle()` is captured by pointer.
    pub fn init(self: *Blinky, timer_module: *timer.TimerModule, comptime Pin: type) void {
        self.toggle_fn = &Pin.toggle;
        timer_module.startPeriodic(&self.timer, self.period_ms, self, &onTick);
    }

    fn onTick(ctx: ?*anyopaque, _: *timer.TimerModule, _: *timer.Timer) void {
        const self: *Blinky = @ptrCast(@alignCast(ctx.?));
        self.toggle_fn();
    }
};
