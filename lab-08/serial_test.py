#!/usr/bin/env python3
"""
Lab-08 serial test: motor PWM + encoder RPM on the NUCLEO-G071RB.

Usage:
    python3 lab-08/serial_test.py [PORT]

Default port: /dev/ttyACM0
Baud rate:    115200

Verifies the command parser (DUTY<n> / HALT / unknown commands) and the
1 Hz RPM tick. The motor + encoder don't need to be wired - this test
only checks the host-visible interface; pulses_per_second always reads
zero when nothing is driving PA0.
"""

import re
import serial
import sys
import time

PORT = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyACM0"
BAUD = 115200

passed = 0
failed = 0

RPM_RE = re.compile(rb"RPM: (\d+) \((\d+) pulses/s\)")


def open_serial():
    print(f"Opening {PORT} at {BAUD} baud...")
    ser = serial.Serial(PORT, BAUD, timeout=0.01)
    time.sleep(0.05)
    ser.reset_input_buffer()
    return ser


def read_until(ser, predicate, timeout):
    out = b""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            out += chunk
            if predicate(out):
                return out
    return out


def send(ser, text, timeout=1.5):
    ser.write(text.encode() if isinstance(text, str) else text)
    return read_until(ser, lambda b: b"> " in b, timeout).decode(errors="replace")


def check(label, ok, detail=""):
    global passed, failed
    icon = "PASS" if ok else "FAIL"
    if ok:
        passed += 1
    else:
        failed += 1
    suffix = " - " + detail if detail else ""
    print(f"  [{icon}] {label}{suffix}")


def expect(label, response, needle):
    if needle in response:
        check(label, True)
    else:
        cleaned = response.replace("\r", "\\r").replace("\n", "\\n")
        check(label, False, f'missing "{needle}" - got: "{cleaned}"')


def section(title):
    print(f"\n  --- {title} ---")


def main():
    t0 = time.monotonic()
    ser = open_serial()
    send(ser, "\r")

    section("Command parser")
    expect("DUTY0 acknowledged", send(ser, "DUTY0\r"), "DUTY 0% set")
    # The DG01D-E shield motor only overcomes static friction above
    # ~80% duty - lower values just whine without spinning, so the
    # operating-point check uses a value the motor actually responds to.
    expect("DUTY80 acknowledged", send(ser, "DUTY80\r"), "DUTY 80% set")
    expect("DUTY100 acknowledged", send(ser, "DUTY100\r"), "DUTY 100% set")
    expect("DUTY999 rejected (out of range)", send(ser, "DUTY999\r"), "undefined command")
    expect("DUTY (no value) rejected", send(ser, "DUTY\r"), "undefined command")
    expect("HALT acknowledged", send(ser, "HALT\r"), "motor stopped")
    expect("Unknown command rejected", send(ser, "BOGUS\r"), "undefined command")

    section("Encoder reports rotation when the motor spins")
    send(ser, "DUTY80\r")
    # Settle for one tick boundary, then collect ~4 fresh RPM lines.
    time.sleep(1.2)
    ser.reset_input_buffer()
    t_start = time.monotonic()
    buf = b""
    while time.monotonic() - t_start < 5.0 and len(RPM_RE.findall(buf)) < 4:
        buf += ser.read(ser.in_waiting or 1)
    ticks = RPM_RE.findall(buf)
    check(
        ">= 4 RPM ticks within 5 s",
        len(ticks) >= 4,
        f"got {len(ticks)}",
    )
    nonzero = [(int(r), int(p)) for r, p in ticks if int(p) > 0]
    check(
        "at least 3 of those ticks report pulses > 0",
        len(nonzero) >= 3,
        f"non-zero: {nonzero}, all: {[(int(r), int(p)) for r, p in ticks]}",
    )
    if nonzero:
        rpms = [r for r, _ in nonzero]
        # DG01D-E datasheet: 90 RPM no-load at 4.5 V, rated 3-9 V. The
        # class shield's motor driver level-shifts the PWM onto its own
        # 9 V rail (the Nucleo itself stays at 3.3 V), so at 80% duty
        # the motor sees roughly 9 V * 0.8 = 7.2 V - linearly that's
        # ~144 RPM no-load. Friction and load drag it down to the
        # ~100..130 band in practice. Allow a wide window (60..200);
        # anything way outside it suggests the gearbox / encoder
        # constants drifted or the supply rail changed.
        check(
            "RPM in plausible range for DG01D-E + DUTY80 (60..200)",
            all(60 <= r <= 200 for r in rpms),
            f"rpms={rpms}",
        )

    section("HALT stops the encoder pulses")
    send(ser, "HALT\r")
    time.sleep(2.0)  # let the motor coast and the next tick settle
    ser.reset_input_buffer()
    t_start = time.monotonic()
    buf = b""
    while time.monotonic() - t_start < 2.5 and len(RPM_RE.findall(buf)) < 2:
        buf += ser.read(ser.in_waiting or 1)
    halt_ticks = [(int(r), int(p)) for r, p in RPM_RE.findall(buf)]
    check(
        "after HALT, RPM/pulses return to zero",
        all(p == 0 for _, p in halt_ticks) and len(halt_ticks) >= 2,
        f"ticks: {halt_ticks}",
    )

    ser.close()
    elapsed = time.monotonic() - t0
    print(f"\n  {passed}/{passed + failed} passed in {elapsed:.1f}s", end="")
    if failed:
        print(f" ({failed} FAILED)")
    else:
        print(" - all good")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
