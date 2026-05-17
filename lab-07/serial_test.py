#!/usr/bin/env python3
"""
Lab-07 serial test: TMP102 + FRAM logger on the NUCLEO-G071RB.

Usage:
    python3 lab-07/serial_test.py [PORT]

Default port: /dev/ttyACM0
Baud rate:    115200

Verifies the four lab commands (START / STOP / TEMP / CLEAR) and that
sample data actually persists in FRAM across a STOP / START cycle.
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
SESSION_RE = re.compile(
    rb"Session: first=0x([0-9A-F]{4}) last=0x([0-9A-F]{4}) count=(\d+)"
)


def open_serial():
    print(f"Opening {PORT} at {BAUD} baud...")
    ser = serial.Serial(PORT, BAUD, timeout=0.005, dsrdtr=False, rtscts=False)
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


def send(ser, text, timeout=2.5):
    ser.write(text.encode() if isinstance(text, str) else text)
    return read_until(ser, lambda b: b"> " in b, timeout).decode(errors="replace")


def collect_samples(ser, count, timeout):
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

    section("Reset to known state")
    expect("CLEAR works", send(ser, "CLEAR\r"), "Clearing FRAM... done")
    expect("TEMP after CLEAR reports no data", send(ser, "TEMP\r"), "uninitialized")

    section("Sampling Lifecycle")
    expect("STOP before START is graceful", send(ser, "STOP\r"), "not sampling")
    expect("Unknown command rejected", send(ser, "HELLO\r"), "undefined command")
    expect("START acknowledged", send(ser, "START\r"), "sampling at 1 Hz")

    _, samples = collect_samples(ser, count=2, timeout=1.5)
    check(
        ">= 2 live temperatures within 1.5 s",
        len(samples) >= 2,
        f"got {len(samples)} live readings",
    )

    expect("STOP acknowledged", send(ser, "STOP\r"), "sampling halted")

    section("FRAM persistence in current session")
    resp = send(ser, "TEMP\r", timeout=3.0)
    session = SESSION_RE.search(resp.encode())
    check("TEMP reports a session header", session is not None, repr(resp[:120]))
    if session:
        first = int(session.group(1), 16)
        last = int(session.group(2), 16)
        count = int(session.group(3))
        check(
            "first_addr == 0x0004 (post-CLEAR session)",
            first == 0x0004,
            f"first=0x{first:04X}",
        )
        check(
            "session has >= 2 entries",
            count >= 2,
            f"count={count}, last=0x{last:04X}",
        )
        stored = TEMP_RE.findall(resp.encode())
        check(
            "TEMP body lists every entry",
            len(stored) == count,
            f"listed {len(stored)} of {count}",
        )

    section("Continue past previous session")
    expect("Second START acknowledged", send(ser, "START\r"), "sampling at 1 Hz")
    _, more = collect_samples(ser, count=2, timeout=1.5)
    check(
        ">= 2 readings in second session",
        len(more) >= 2,
        f"got {len(more)}",
    )
    send(ser, "STOP\r")

    resp = send(ser, "TEMP\r", timeout=3.0)
    session = SESSION_RE.search(resp.encode())
    check("Second session also reported", session is not None)
    if session:
        first = int(session.group(1), 16)
        check(
            "second session's first_addr is past the first session",
            first > 0x0004,
            f"first=0x{first:04X}",
        )

    section("Long burst: TEMP must dump all entries with no drops")
    # Earlier the ring-buffered TX path silently dropped bytes when
    # `handleTemp` ran from the USART2 ISR and produced more output
    # than the 256-byte ring could hold (around 6-7 entries). Collect
    # ~30 samples to exceed that threshold by 4x, then verify TEMP
    # reports them all and the indices are contiguous.
    send(ser, "CLEAR\r", timeout=3.0)
    send(ser, "START\r")
    burst_target = 30
    deadline = time.monotonic() + burst_target + 5.0
    burst_buf = b""
    while time.monotonic() < deadline and len(TEMP_RE.findall(burst_buf)) < burst_target:
        burst_buf += ser.read(ser.in_waiting or 1)
    live_count = len(TEMP_RE.findall(burst_buf))
    check(
        f"collected >= {burst_target} live samples",
        live_count >= burst_target,
        f"got {live_count}",
    )
    send(ser, "STOP\r")
    resp = send(ser, "TEMP\r", timeout=5.0)
    session = SESSION_RE.search(resp.encode())
    check("burst TEMP reports a session", session is not None)
    if session:
        count = int(session.group(3))
        entries = re.findall(rb"\[(\d+)\] @0x[0-9A-F]+: Temperature:", resp.encode())
        check(
            f"burst TEMP body lists all {count} entries (no ring overflow)",
            len(entries) == count,
            f"listed {len(entries)} of {count}",
        )
        indices = [int(b) for b in entries]
        check(
            "burst entry indices are contiguous 0..count-1",
            indices == list(range(count)),
            f"first 5: {indices[:5]}, last 5: {indices[-5:]}",
        )

    section("CLEAR wipes the device")
    send(ser, "CLEAR\r", timeout=3.0)
    expect("TEMP after CLEAR is empty again", send(ser, "TEMP\r"), "uninitialized")

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
