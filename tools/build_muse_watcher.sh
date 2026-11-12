#!/bin/sh
# Build the Muse Watcher firmware from the muse-gadget-sdk submodule,
# which is already on the watcher-detection branch carrying the
# watcher.coffee_mug command and watch loop. This script does NOT clone,
# fetch, check out, or patch: the submodule pins the content. If the
# coffee-mug command is missing, update the submodule, don't patch here.
# Requires ESP-IDF v6.0.3 (export.sh discoverable as in board.sh).
# No SDK token is baked in; set it later over serial / UI / flasher.
# Output: build/muse-watcher/{bootloader.bin,partition-table.bin,
#   ota_data_initial.bin,muse-gadget.bin,flash_args}
set -eu
SCRIPT_DIR="$(dirname "$0")"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SDK_DIR="${MUSE_SDK_DIR:-$ROOT/sdk/muse-gadget-sdk}"

if [ ! -f "$SDK_DIR/esp32/main/watcher_watch.c" ]; then
    echo "ERROR: watcher files not found under $SDK_DIR" >&2
    echo "Run: git submodule update --init --recursive" >&2
    exit 1
fi
if ! grep -q "watcher.coffee_mug" "$SDK_DIR/esp32/main/app.c"; then
    echo "ERROR: $SDK_DIR is not the coffee-mug detection tree (no watcher.coffee_mug)" >&2
    echo "Check the submodule is on watcher-detection." >&2
    exit 1
fi

if [ -n "${IDF_EXPORT:-}" ]; then
    . "$IDF_EXPORT" >/dev/null 2>&1
elif ! command -v idf.py >/dev/null 2>&1; then
    for d in "$HOME/.espressif/esp-idf-v6.0.3" "${IDF_PATH:-}" "$HOME/esp/esp-idf-v6.0.3"; do
        [ -n "$d" ] && [ -f "$d/export.sh" ] && { . "$d/export.sh" >/dev/null 2>&1; break; }
    done
fi
command -v idf.py >/dev/null 2>&1 || { echo "idf.py not found; activate ESP-IDF v6.0.3 first" >&2; exit 1; }

cd "$SDK_DIR/esp32"
rm -rf managed_components dependencies.lock
B=build-muse-sensecap-watcher
idf.py -B "$B" -DIDF_TARGET=esp32s3 -DSDKCONFIG="$B/sdkconfig" \
    -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;devices/sdkconfig.muse;devices/sdkconfig.muse-sensecap-watcher;devices/sdkconfig.muse-watcher-watch" \
    build
mkdir -p "$ROOT/build/muse-watcher"
cp "$B/bootloader/bootloader.bin" "$B/partition_table/partition-table.bin" \
   "$B/ota_data_initial.bin" "$B/muse-gadget.bin" "$ROOT/build/muse-watcher/"
# flash_args paths are flat: the binaries above are staged flat
# into build/muse-watcher/, and tools/flash_muse_watcher.sh runs
# esptool from that directory. (The IDF build dir's own
# flash_args uses bootloader/ and partition_table/ subdirs and
# must not be copied verbatim.)
printf '%s\n' "--flash-mode dio --flash-freq 80m --flash-size keep" \
    "0x0 bootloader.bin" \
    "0x10000 partition-table.bin" \
    "0x1d000 ota_data_initial.bin" \
    "0x20000 muse-gadget.bin" > "$ROOT/build/muse-watcher/flash_args"
echo "staged:"; ls -la "$ROOT/build/muse-watcher/"
shasum -a 256 "$ROOT/build/muse-watcher/muse-gadget.bin"
