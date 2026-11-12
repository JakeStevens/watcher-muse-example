#!/usr/bin/env python3
"""Capture the ESP32-S3 console and summarise Watcher inference traffic.

Usage: python3 tools/verify_esp.py [ESP_PORT] [SECONDS] [OUT_LOG]

Reads the ESP32 console (115200 baud) without sending anything. The
Muse gadget firmware logs link heartbeats, per-cycle watcher
scores (`scores: mug=N | armed=mug`), matches above threshold,
JPEG dumps (`@@JPEG`), and classify failures. No scores at all
usually means watching is disarmed (arm `watcher.coffee_mug` in
Muse first) or the HX6538 is not answering AT commands on SPI
(check the HX6538 UART log at 921600 baud during boot for the
SPI-slave ready line). No output at all usually means the ESP32
task has not started (check the display) or the serial port is
wrong.

Exit code 0 when at least one classified cycle was logged,
2 otherwise.
"""
import re
import sys
import time

import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else "/dev/cu.usbmodem5B6F0094393"
SECONDS = float(sys.argv[2]) if len(sys.argv) > 2 else 30
OUT = sys.argv[3] if len(sys.argv) > 3 else None

PATTERNS = {
    "heartbeat": re.compile(rb"link\.heartbeat"),
    "scores": re.compile(rb"scores: mug=\d+"),
    "match": re.compile(rb"match: coffee mug \d+%"),
    "failed": re.compile(rb"classify failed"),
    "jpeg": re.compile(rb"@@JPEG "),
    "error": re.compile(rb"sscma|SSCMA.*(fail|error)", re.I),
}

counts = {k: 0 for k in PATTERNS}
ser = serial.Serial(PORT, 115200, timeout=0.2)
try:
    ser.reset_input_buffer()
    deadline = time.time() + SECONDS
    log = open(OUT, "wb") if OUT else None
    try:
        while time.time() < deadline:
            chunk = ser.read(4096)
            if not chunk:
                continue
            if log:
                log.write(chunk)
            for name, pat in PATTERNS.items():
                counts[name] += len(pat.findall(chunk))
    finally:
        if log:
            log.close()
finally:
    ser.close()

print(counts)
seen = counts["scores"]
print(f"classified cycles: {seen}")
raise SystemExit(0 if seen > 0 else 2)
