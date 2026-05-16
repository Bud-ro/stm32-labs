#!/usr/bin/env python3
"""
Lab-06 serial test: TMP102 START/STOP command flow on the
NUCLEO-G071RB.

Usage:
    python3 lab-06/serial_test.py [PORT]

Default port: /dev/ttyACM0
Baud rate:    115200

Same fast event-driven style as lab-04's test: each `send` returns as
soon as the firmware prints the next `> ` prompt; temperature samples
are collected line-by-line until N have arrived (or a deadline hits).
The 1 Hz sample rate is the only inherent floor - everything else is
bounded by serial round-trip latency.

Requires a TMP102 sensor on PB8 (SCL) / PB9 (SDA). With no sensor
attached the firmware reports `TMP102 init FAILED` / `TMP102 trigger
failed`; the test surfaces these instead of waiting on temperature
lines that will never come.
"""

import re
import serial
import sys
import time

PORT = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyACM0"
BAUD = 115200

passed = 0
failed = 0

TEMP_RE = re.compile(rb"Temperature: (-?\d+)\.(\d{4}) C")


def open_serial():
    print(f"Opening {PORT} at {BAUD} baud...")
    ser = serial.Serial(PORT, BAUD, timeout=0.005, dsrdtr=False, rtscts=False)
    time.sleep(0.05)
    ser.reset_input_buffer()
    return ser


def read_until(ser, predicate, timeout):
    """Read bytes until `predicate(buf)` is truthy or `timeout` elapses.

    `predicate` receives the accumulated buffer (bytes); it can do
    substring checks or count regex matches. Returns the final buffer.
    """
    out = b""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            out += chunk
            if predicate(out):
                return out
    return out


def send(ser, text, timeout=2.0):
    """Write `text`, read until the next `> ` prompt or `timeout`."""
    ser.write(text.encode() if isinstance(text, str) else text)
    return read_until(ser, lambda b: b"> " in b, timeout).decode(errors="replace")


def collect_samples(ser, count, timeout):
    """Read until `count` Temperature lines have appeared or `timeout`."""
    out = read_until(ser, lambda b: len(TEMP_RE.findall(b)) >= count, timeout)
    return out.decode(errors="replace"), TEMP_RE.findall(out)


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
    """Substring check that prints the raw response on failure."""
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

    # Sync to a clean prompt regardless of when we connected.
    send(ser, "\r")

    section("Command Recognition")

    expect("STOP before START is graceful", send(ser, "STOP\r"), "not sampling")
    expect("Unknown command rejected", send(ser, "HELLO\r"), "undefined command")

    section("Sampling Lifecycle")

    expect("START acknowledged", send(ser, "START\r"), "sampling at 1 Hz")

    # First sample is triggered immediately on START (one-shot timer
    # fires ~35 ms later); the second arrives at ~1.04 s. Allow 1.5 s.
    _, matches = collect_samples(ser, count=2, timeout=1.5)
    check(
        ">= 2 readings within 1.5 s of START",
        len(matches) >= 2,
        f"got {len(matches)} reading(s)",
    )

    if matches:
        int_part, frac_part = matches[0]
        temp_c = float(f"{int_part.decode()}.{frac_part.decode()}")
        check(
            "First reading in plausible range (-40..125 C)",
            -40.0 <= temp_c <= 125.0,
            f"{temp_c} C",
        )

    expect("STOP acknowledged", send(ser, "STOP\r"), "sampling halted")

    # Drop the in-flight conversion (35 ms one-shot timer) and a comfy
    # margin, then verify the firmware stays quiet for > 1 sample period.
    time.sleep(0.1)
    ser.reset_input_buffer()
    _, matches = collect_samples(ser, count=1, timeout=1.2)
    check("No readings after STOP", not matches, f"got {len(matches)}")

    section("Re-arm")

    expect("Re-START acknowledged", send(ser, "START\r"), "sampling at 1 Hz")
    _, matches = collect_samples(ser, count=2, timeout=1.5)
    check(">= 2 readings after re-START", len(matches) >= 2, f"got {len(matches)}")
    send(ser, "STOP\r")

    section("Idempotency")

    expect("STOP-after-STOP is graceful", send(ser, "STOP\r"), "not sampling")
    expect("START re-arms cleanly", send(ser, "START\r"), "sampling at 1 Hz")
    send(ser, "STOP\r")

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
