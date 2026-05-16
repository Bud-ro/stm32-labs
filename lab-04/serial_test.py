#!/usr/bin/env python3
"""
Lab-04 serial test: exercises the UART ring buffer and command parser
on the NUCLEO-G071RB.

Usage:
    python3 lab-04/serial_test.py [PORT]

Default port: /dev/ttyACM0
Baud rate:    115200

All sends are burst - the MCU's interrupt-driven RX buffers every byte
at wire speed. Reads wait for the "> " prompt, no fixed delays.
"""

import serial
import sys
import time

PORT = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyACM0"
BAUD = 115200

passed = 0
failed = 0


def open_serial():
    print(f"Opening {PORT} at {BAUD} baud...")
    ser = serial.Serial(PORT, BAUD, timeout=0.005, dsrdtr=False, rtscts=False)
    time.sleep(0.1)
    ser.reset_input_buffer()
    return ser


def send(ser, text):
    """Send text and read until the '> ' prompt appears."""
    ser.write(text.encode() if isinstance(text, str) else text)
    out = b""
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            out += chunk
            if b"> " in out:
                break
    return out.decode(errors="replace")


def check(label, response, expect_substr=None, expect_not=None):
    global passed, failed

    ok = True
    reasons = []

    if expect_substr:
        if expect_substr in response:
            reasons.append(f'found "{expect_substr}"')
        else:
            ok = False
            reasons.append(f'MISSING "{expect_substr}"')

    if expect_not:
        if expect_not in response:
            ok = False
            reasons.append(f'unexpected "{expect_not}"')

    if ok:
        passed += 1
        icon = "PASS"
    else:
        failed += 1
        icon = "FAIL"

    detail = " - " + "; ".join(reasons) if reasons else ""
    print(f"  [{icon}] {label}{detail}")


def section(title):
    print(f"\n  --- {title} ---")


def main():
    t0 = time.monotonic()
    ser = open_serial()

    section("Basic Commands")

    resp = send(ser, "STOP\r")
    check("STOP recognized", resp, expect_substr="STOP command received")

    resp = send(ser, "START\r")
    check("START recognized", resp, expect_substr="START command received")

    resp = send(ser, "CLEAR\r")
    check("CLEAR recognized", resp, expect_substr="CLEAR command received")

    section("Unknown / Edge-Case Commands")

    resp = send(ser, "HELLO\r")
    check("Unknown command rejected", resp, expect_substr="undefined command")

    resp = send(ser, "stop\r")
    check("Lowercase rejected", resp, expect_substr="undefined command")

    resp = send(ser, "CLEAN\r")
    check("CLEAN rejected (not CLEAR)", resp, expect_substr="undefined command")

    resp = send(ser, "\r")
    check("Empty enter (no crash)", resp, expect_substr=">")

    resp = send(ser, " \r")
    check("Single space rejected", resp, expect_substr="undefined command")

    section("Backspace Handling")

    resp = send(ser, "AB\x7fC\r")
    check("AB<del>C -> AC (undefined)", resp, expect_substr="undefined command")

    resp = send(ser, "\x7f\x7f\x7fSTOP\r")
    check("Backspace on empty then STOP", resp, expect_substr="STOP command received")

    resp = send(ser, "STAR\x7fRT\r")
    check("STAR<del>RT -> START", resp, expect_substr="START command received")

    section("Ring Buffer Boundaries")

    resp = send(ser, "ABCDEFGHIJKLMNOPQRS\r")
    check(
        "19 chars + CR = 20 (fills buffer, no overflow)",
        resp,
        expect_substr="Ring buffer:",
        expect_not="overflow",
    )

    resp = send(ser, "12345678901234567890\r")
    check("20 chars + CR = 21 (overflow detected)", resp, expect_substr="overflow")

    section("Ring Buffer History")

    send(ser, "STOP\r")
    send(ser, "START\r")
    resp = send(ser, "CLEAR\r")
    check("Buffer preserves history from prior commands", resp, expect_substr="Ring buffer:")

    section("Rapid-Fire Commands")

    for cmd in ["STOP", "START", "STOP", "START", "CLEAR"]:
        send(ser, f"{cmd}\r")

    resp = send(ser, "STOP\r")
    check("STOP after 5 rapid-fire commands", resp, expect_substr="STOP command received")

    section("26-Char Overflow")

    resp = send(ser, "ABCDEFGHIJKLMNOPQRSTUVWXYZ\r")
    check("26 chars -> overflow", resp, expect_substr="overflow")

    section("Continuous Parsing")

    resp = send(ser, "STOP\r")
    check("1st command", resp, expect_substr="STOP command received")

    resp = send(ser, "START\r")
    check("2nd command", resp, expect_substr="START command received")

    resp = send(ser, "CLEAR\r")
    check("3rd command", resp, expect_substr="CLEAR command received")

    resp = send(ser, "HELLO\r")
    check("4th command (unknown)", resp, expect_substr="undefined command")

    resp = send(ser, "STOP\r")
    check("5th command", resp, expect_substr="STOP command received")

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
