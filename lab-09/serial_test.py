#!/usr/bin/env python3
"""
Lab-09 serial test: button-triggered ADC over DMA on the NUCLEO-G071RB.

Usage:
    python3 lab-09/serial_test.py [PORT]

Default port: /dev/ttyACM0
Baud rate:    115200

The lab is entirely interrupt-driven: pressing B1 (the blue user button)
kicks off a 10-sample ADC burst that DMA streams into RAM, and the
DMA TC ISR prints "Voltage: X.XXX V (raw avg N)". This test needs a
human in the loop to press the button - it prompts you, then verifies
the firmware's response.
"""

import re
import serial
import sys
import time

PORT = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyACM0"
BAUD = 115200

passed = 0
failed = 0

VOLT_RE = re.compile(rb"Voltage: (-?\d+)\.(\d{3}) V \(raw avg (\d+)\)")
BANNER_RE = re.compile(rb"button-triggered ADC over DMA")


def open_serial():
    print(f"Opening {PORT} at {BAUD} baud...")
    ser = serial.Serial(PORT, BAUD, timeout=0.05)
    time.sleep(0.05)
    ser.reset_input_buffer()
    return ser


def check(label, ok, detail=""):
    global passed, failed
    icon = "PASS" if ok else "FAIL"
    if ok:
        passed += 1
    else:
        failed += 1
    suffix = " - " + detail if detail else ""
    print(f"  [{icon}] {label}{suffix}")


def section(title):
    print(f"\n  --- {title} ---")


def collect_voltages(ser, target_count, timeout):
    out = b""
    deadline = time.monotonic() + timeout
    last_count = 0
    while time.monotonic() < deadline and len(VOLT_RE.findall(out)) < target_count:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            out += chunk
            found = VOLT_RE.findall(out)
            if len(found) > last_count:
                v = found[-1]
                print(
                    f"    [t={time.monotonic() - deadline + timeout:5.2f}s] "
                    f"Voltage: {int(v[0])}.{v[1].decode()} V (raw {int(v[2])})"
                )
                last_count = len(found)
    return out, VOLT_RE.findall(out)


def main():
    t0 = time.monotonic()
    ser = open_serial()

    section("Banner appears at boot")
    print("    Resetting board via openocd...")
    import subprocess
    subprocess.run(
        ["openocd", "-f", "interface/stlink.cfg", "-f", "target/stm32g0x.cfg",
         "-c", "init; reset run; exit"],
        capture_output=True,
    )
    time.sleep(0.3)
    banner_buf = b""
    deadline = time.monotonic() + 1.0
    while time.monotonic() < deadline and not BANNER_RE.search(banner_buf):
        banner_buf += ser.read(ser.in_waiting or 1)
    check("startup banner streams", bool(BANNER_RE.search(banner_buf)))

    section("Button press triggers ADC sample")
    print("    >>> Press B1 (blue user button) 3 times over the next 15 s <<<")
    ser.reset_input_buffer()
    _, samples = collect_voltages(ser, target_count=3, timeout=15.0)
    check(
        ">= 3 voltage readings collected",
        len(samples) >= 3,
        f"got {len(samples)}",
    )
    if samples:
        for whole, frac, raw in samples:
            volts = int(whole) + int(frac) / 1000
            raw_int = int(raw)
            check(
                f"raw avg {raw_int} in 12-bit range",
                0 <= raw_int <= 4095,
                f"raw={raw_int}",
            )
            check(
                f"voltage {volts:.3f} V in 0..3.3 V (VREF)",
                0.0 <= volts <= 3.3,
                f"volts={volts}",
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
