#!/bin/sh
# Host tests for the Watcher firmware. No framework required: plain cc +
# python3 (stdlib only). Exits non-zero if any check fails.
# The SPI framing source under test lives in the Grove SDK submodule.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC="${CC:-cc}"
APP_DIR="$ROOT/sdk/Seeed_Grove_Vision_AI_Module_V2/EPII_CM55M_APP_S/app/scenario_app/watcher_executorch"
[ -f "$APP_DIR/sscma_spi_framing.c" ] || { echo "submodule app not found: run git submodule update --init --recursive" >&2; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

"$CC" -std=c11 -Wall -Wextra -Werror -O2 \
    -I"$APP_DIR" \
    "$ROOT/tests/test_sscma_spi_framing.c" \
    "$APP_DIR/sscma_spi_framing.c" \
    -o "$WORK/test_sscma_spi_framing"
"$WORK/test_sscma_spi_framing"

python3 "$ROOT/tests/test_event_contract.py"

echo "all host tests passed"
