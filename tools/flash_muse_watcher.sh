#!/bin/sh
# Flash the Muse Watcher firmware (build/muse-watcher/) to the ESP32-S3.
#
# STOP AND READ: this replaces the stock ESP32 firmware and its
# partition layout, and partially overwrites the factory NVS region
# (0x9000-0x3B000). Back up the stock firmware + factory NVS from YOUR
# device first (see README.md "Back up first"); this repo ships no
# backups. Rollback reflashes the stock bins + nvsfactory.bin.
# The SDK token is NOT in this build: set it over serial
# (>sdk_token=mgst_...) or in the settings UI before pairing.
# Uses the SDK's paced esptool (CH342 drops bytes at full speed).
# Usage: sh tools/flash_muse_watcher.sh [ESP_PORT] [MUSE_SDK_DIR]
set -eu
SCRIPT_DIR="$(dirname "$0")"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT="${1:-/dev/cu.usbmodem5B6F0094393}"
SDK_DIR="${2:-$ROOT/sdk/muse-gadget-sdk}"
ART="$ROOT/build/muse-watcher"

[ -f "$ROOT/backups/nvsfactory.bin" ] || { echo "missing backups/nvsfactory.bin: back it up before flashing (see README.md)" >&2; exit 1; }
for f in bootloader.bin partition-table.bin ota_data_initial.bin muse-gadget.bin flash_args; do
    [ -f "$ART/$f" ] || { echo "missing $ART/$f: run tools/build_muse_watcher.sh first" >&2; exit 1; }
done
[ -x "$SDK_DIR/esp32/tools/muse/paced_esptool.py" ] || { echo "paced esptool not found under $SDK_DIR" >&2; exit 1; }
PY=""
for cand in "$HOME/.espressif/python_env/idf6.0_py3.13_env/bin/python" python3; do
    if command -v "$cand" >/dev/null 2>&1; then PY="$cand"; break; fi
done
echo "Flashing Muse firmware to $PORT (paced, 115200 baud)."
echo "This overwrites the stock ESP32 firmware and part of factory NVS."
echo "Rollback: reflash stock bins + nvsfactory.bin (see README.md)."
cd "$ART"
exec "$PY" "$SDK_DIR/esp32/tools/muse/paced_esptool.py" --chip esp32s3 -p "$PORT" -b 115200 --before default-reset --after hard-reset write-flash "@flash_args"
