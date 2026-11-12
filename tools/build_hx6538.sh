#!/bin/sh
# Build the watcher_executorch HX6538 firmware from the Grove SDK
# submodule (which already contains the watcher app and the vendored
# ExecuTorch 1.6 runtime on the watcher-detection branch).
#
# This script does NOT copy app sources and does NOT check out any
# commit: the submodule pins the branch content. If the app sources
# are missing or stale, update the submodule, don't overlay here.
#
# Requirements (host):
#   - GNU Make >= 4 (SDK uses $(file ...) response files). On macOS the
#     stock /usr/bin/make is 3.81 and fails at link time; build GNU Make
#     4.4 from source or `brew install make` (gmake). Pass its path as
#     MAKE=/path/to/gmake.
#   - Arm GNU Toolchain 13.2.rel1 (arm-none-eabi-gcc) on PATH.
#     Download: https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-darwin-arm64-arm-none-eabi.tar.xz
#
# Usage:
#   MAKE=/tmp/make-4.4/make PATH=/tmp/arm-gnu-toolchain/bin:$PATH \
#       sh tools/build_hx6538.sh [SDK_DIR]
#   SDK_DIR defaults to sdk/Seeed_Grove_Vision_AI_Module_V2 in this
#   repo (initialize submodules first).
# Output: build/watcher_executorch_16.img (must be <= 1 MiB) and its
#   SHA-256.
set -eu

SCRIPT_DIR="$(dirname "$0")"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SDK_DIR="${1:-$ROOT/sdk/Seeed_Grove_Vision_AI_Module_V2}"
MAKE_BIN="${MAKE:-make}"

APP_DIR="$SDK_DIR/EPII_CM55M_APP_S/app/scenario_app/watcher_executorch"
if [ ! -f "$APP_DIR/cvapp_mb_cls.cpp" ]; then
    echo "ERROR: watcher app not found under $APP_DIR" >&2
    echo "Run: git submodule update --init --recursive" >&2
    exit 1
fi
if ! grep -q "Classifier Top 5" "$APP_DIR/cvapp_mb_cls.cpp"; then
    echo "ERROR: $APP_DIR/cvapp_mb_cls.cpp is not the coffee-mug detection app" >&2
    echo "Check the submodule is on watcher-detection." >&2
    exit 1
fi

"$MAKE_BIN" --version | head -1
command -v arm-none-eabi-gcc >/dev/null || { echo "arm-none-eabi-gcc not on PATH" >&2; exit 1; }
arm-none-eabi-gcc --version | head -1

cd "$SDK_DIR/EPII_CM55M_APP_S"
"$MAKE_BIN" clean >/tmp/watcher_clean.log 2>&1 || true
"$MAKE_BIN" APP_TYPE=watcher_executorch -j4
ELF="obj_epii_evb_icv30_bdv10/gnu_epii_evb_WLCSP65/EPII_CM55M_gnu_epii_evb_WLCSP65_s.elf"
test -f "$ELF" || { echo "ERROR: ELF not produced" >&2; exit 1; }

mkdir -p "$SDK_DIR/we2_image_gen_local/input_case1_secboot"
cp "$ELF" "$SDK_DIR/we2_image_gen_local/input_case1_secboot/"
cd "$SDK_DIR/we2_image_gen_local"
./we2_local_image_gen_macOS_arm64 project_case1_blp_wlcsp.json >/tmp/watcher_imagegen.log 2>&1 || \
    ./we2_local_image_gen project_case1_blp_wlcsp.json
IMG="$SDK_DIR/we2_image_gen_local/output_case1_sec_wlcsp/output.img"
test -f "$IMG" || { echo "ERROR: output.img not produced" >&2; exit 1; }
SIZE="$(wc -c < "$IMG" | tr -d ' ')"
echo "output.img: $SIZE bytes"
if [ "$SIZE" -gt 1048576 ]; then
    echo "ERROR: firmware image exceeds 1 MiB cap" >&2
    exit 1
fi
mkdir -p "$ROOT/build"
cp "$IMG" "$ROOT/build/watcher_executorch_16.img"
echo "image: $ROOT/build/watcher_executorch_16.img"
shasum -a 256 "$ROOT/build/watcher_executorch_16.img"
