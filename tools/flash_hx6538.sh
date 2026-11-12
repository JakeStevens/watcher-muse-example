#!/bin/sh
# Flash the HX6538 firmware image + ExecuTorch .pte model over the
# Himax USB UART (the /dev/cu.usbmodem* port that is NOT the ESP32-S3
# console) using the Himax XMODEM sender.
#
# The sender waits for the 2nd-stage bootloader prompt, so after
# starting this script, reset the Watcher (see below). The
# bootloader prompt appears on the Himax UART; the transfer then
# runs unattended.
#
# Reset procedure: one ESP32 reset produces several HX6538 boots
# about a second apart, so reset once, wait ~6 s, then start this
# script and reset again; the sender only starts the transfer
# once the prompt has been stable for 4 s. The backup battery
# means unplugging USB does NOT reset the HX6538 (and kills the
# sender's serial handle): reset by hard-resetting the ESP32-S3
# (esptool.py ... chip-id), which pulses HX6538 RST on startup.
# The model MUST be flashed in one full transfer: split/chunked
# model writes corrupt flash (models load but stall mid-inference).
# The transfer pauses near 72% for ~20 s during a slow flash-erase
# window; that is normal, not a stall.
#
# Back up first: this repo ships no backups. Before flashing, save
# the stock firmware + factory NVS from YOUR device (see README.md
# "Back up first"). If flashing fails part-way, re-run this script;
# to roll back, reflash your stock image with the same command
# pointed at it and no --model argument.
#
# Usage:
#   sh tools/flash_hx6538.sh [HX_PORT] [IMAGE] [PTE]
# Defaults: HX_PORT=/dev/cu.usbmodem5B6F0094391 (verify on your unit),
#   IMAGE=build/watcher_executorch_16.img, PTE=model/mv2_quant_himax_ini_opt_size_vela_4_5_0_inout_in8.pte
set -eu
SCRIPT_DIR="$(dirname "$0")"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT="${1:-/dev/cu.usbmodem5B6F0094391}"
IMAGE="${2:-$ROOT/build/watcher_executorch_16.img}"
MODEL="${3:-$ROOT/model/mv2_quant_himax_ini_opt_size_vela_4_5_0_inout_in8.pte}"

if [ ! -f "$IMAGE" ]; then echo "missing image: $IMAGE (run tools/build_hx6538.sh first)" >&2; exit 1; fi
if [ ! -f "$MODEL" ]; then echo "missing model: $MODEL" >&2; exit 1; fi
SENDER="$ROOT/tools/xmodem_send.py"
if [ ! -f "$SENDER" ]; then
    echo "xmodem sender not found: $SENDER" >&2
    exit 1
fi
PY=""
for cand in "$HOME/.espressif/python_env/idf6.0_py3.13_env/bin/python" python3; do
    if command -v "$cand" >/dev/null 2>&1; then PY="$cand"; break; fi
done
"$PY" -c "import serial, xmodem" 2>/dev/null || {
    echo "Python needs pyserial + xmodem: pip install pyserial xmodem" >&2
    exit 1
}
echo "HX port:  $PORT"
echo "image:    $IMAGE ($(wc -c < "$IMAGE" | tr -d ' ') bytes)"
echo "model:    $MODEL"
echo "Waiting for the HX6538 bootloader prompt. The HX6538 has a"
echo "backup battery, so unplugging USB does NOT reset it. Reset it by"
echo "hard-resetting the ESP32-S3 (which pulses HX RST on boot), e.g.:"
echo "esptool.py --chip esp32s3 --port <ESP_PORT> chip-id"
echo "Keep USB plugged in: unplugging kills this sender's serial handle."
# 0xB7B000 is the flash offset; the runtime reads the model at the
# XIP address 0x3AB7B000 (see common_config.h in the upstream app).
exec "$PY" "$SENDER" \
    --port="$PORT" --baudrate=921600 --protocol=xmodem \
    --file="$IMAGE" \
    --model="$MODEL 0xB7B000 0x00000"
