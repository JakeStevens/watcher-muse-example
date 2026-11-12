# Watcher Muse Example — coffee mug detection on the Seeed SenseCAP Watcher

The Himax HX6538 runs MobileNetV2 ImageNet classification
(ExecuTorch 1.6 + Ethos-U55) and sends each captured image plus
the top-5 class results to the ESP32-S3 host over SPI, using the
SSCMA AT/JSON wire format. The ESP32-S3 runs the Muse gadget
firmware: `watcher.coffee_mug` arms/disarms mug watching, and when
a coffee mug (class 504) is the top result above 75% confidence,
Muse pushes result + image. One thing watched at a time, once per
2 seconds.

This repo is the whole project: the SDKs come in as submodules
pinned to the working branches, the tools build and flash them,
and the ImageNet model binary is committed (Himax model zoo,
already quantized — no export needed). Check out this repo and
you have everything needed to build, flash, run, and substitute
other models.

## Repos and branches

| Path in this repo | Upstream / fork | Branch | Pinned commit |
| --- | --- | --- | --- |
| `sdk/muse-gadget-sdk` | `facebookincubator/muse-gadget-sdk`, fork `JakeStevens/muse-gadget-sdk` | `watcher-detection` | `abef0bb` |
| `sdk/Seeed_Grove_Vision_AI_Module_V2` | `HimaxWiseEyePlus/Seeed_Grove_Vision_AI_Module_V2`, fork `JakeStevens/Seeed_Grove_Vision_AI_Module_V2` | `watcher-detection` | `b14bdb4` |

The Grove fork branch contains the watcher HX app and the vendored
ExecuTorch 1.6 runtime; the Muse fork branch contains the
`watcher.coffee_mug` command and watch loop. The rest of this repo
(tools, model, tests, docs) is the project layer on top. Nothing else is vendored here
on purpose: no `backups/` (device-specific), no `.venv/`, no
build outputs.

## Checkout

```sh
git clone --recursive https://github.com/JakeStevens/watcher-muse-example.git
cd watcher-muse-example
git submodule status   # both lines, no leading -/+ : pinned SHAs above
```

For a faster clone, add `--shallow-submodules` to the clone command.
If the submodules are empty after checkout:

```sh
git submodule update --init --recursive
```

Do not clone the SDKs separately into `/tmp` and point the scripts
at them: the scripts default to the `sdk/` paths in this repo and
verify the coffee-mug content is present before building.

## Prerequisites (host)

Proven on macOS/arm64; Linux needs the equivalent tools (the HX
image generator falls back from the macOS binary to
`we2_local_image_gen`).

- Git with submodule support, `gh` CLI (only needed if you
  re-clone forks; not needed to build).
- GNU Make >= 4 (`gmake` on macOS; stock Make 3.81 fails the SDK
  build). Arm GNU Toolchain 13.2.rel1 (`arm-none-eabi-gcc`).
- Python 3 with `pyserial` + `xmodem` for flashing (or the
  ESP-IDF 6 Python env, which has both).
- ESP-IDF v6.0.3 (`idf.py` on PATH, or `IDF_EXPORT`/`IDF_PATH`
  pointing at an `export.sh`) for the ESP32 build and flash.
- For export only: a Python venv with torch 2.15 + ExecuTorch
  1.6.0 + Vela 5.2.0 (see Export below). No venv is committed.

## Build the HX firmware

```sh
MAKE=/tmp/make-4.4/make PATH=/tmp/arm-gnu-toolchain/bin:$PATH \
    sh tools/build_hx6538.sh
```

This builds `APP_TYPE=watcher_executorch` in the Grove submodule
and stages `build/watcher_executorch_16.img` (must be <= 1 MiB)
plus its SHA-256. It verifies the submodule contains the
coffee-mug app and refuses to build a stale tree. No sources are copied or
overlaid: the submodule branch already holds the app and the
runtime.

## Back up first (do this once, before any flashing)

This repo ships no backups. The Watcher has a backup battery, so
unplugging USB does NOT reset it. Save the stock firmware + NVS
from YOUR device before flashing anything:

```sh
mkdir -p backups
# At minimum, back up the factory NVS partition:
python -m esptool --chip esp32s3 --port /dev/cu.usbmodem5B6F0094393 \
  --baud 2000000 --before default_reset --after hard_reset --no-stub \
  read_flash 0x9000 204800 backups/nvsfactory.bin
```

Keep `backups/` intact (it is not committed here on purpose: it
holds device-specific factory state). The Muse flash script
refuses to run without `backups/nvsfactory.bin`.

## Flash the HX firmware + model

```sh
sh tools/flash_hx6538.sh [HX_PORT] [IMAGE] [PTE]
```

Defaults: HX port `/dev/cu.usbmodem5B6F0094391` (verify with
`ls /dev/cu.usbmodem*`; the other port is the ESP32 console),
image `build/watcher_executorch_16.img`, model
`model/mv2_quant_himax_ini_opt_size_vela_4_5_0_inout_in8.pte` at
flash offset `0xB7B000`.

Procedure (read before running): the sender waits for the 2nd-stage
bootloader prompt. Reset once (hard-reset the ESP32-S3, which
pulses HX RST: `esptool.py --chip esp32s3 --port <ESP_PORT>
chip-id`), wait ~6 s, start the script, reset again. The sender
starts only once the prompt has been stable for 4 s. The model
MUST go in ONE full transfer: split/chunked model writes corrupt
flash (models load but stall mid-inference). The transfer pauses
near 72% for ~20 s (slow flash-erase window): wait it out, do
not reset or unplug mid-transfer.

## Build + flash the ESP32 firmware (Muse gadget)

```sh
sh tools/build_muse_watcher.sh
sh tools/flash_muse_watcher.sh [ESP_PORT] [MUSE_SDK_DIR]
```

Defaults: ESP port `/dev/cu.usbmodem5B6F0094393`, SDK dir
`sdk/muse-gadget-sdk`. The build requires ESP-IDF v6.0.3 and
stages `build/muse-watcher/` (bootloader, partition table, OTA
data, `muse-gadget.bin`, `flash_args`). No SDK token is baked in.

**NVS warning:** the Muse partition table lives at `0x10000` with
`nvs` at `0x11000`, inside the stock `nvsfactory` range
(`0x9000–0x3B000`). Flashing overwrites the start of the factory
NVS region. Back up first (above); rollback reflashes the stock
bins plus `backups/nvsfactory.bin`.

**HX flashing while the Muse firmware runs:** the Muse firmware
keeps the Himax camera rail OFF while disarmed, so the HX never
reaches its bootloader while idle. To reflash the HX after the
Muse firmware is installed: flash the stock/monitor ESP firmware
first (which holds the HX up), flash the HX, then reflash the
Muse firmware and verify the token/pairing survived. Keep an NVS
backup from before each swap.

## Pair + run

1. Set the SDK token on the device (build config, serial
   `>sdk_token=mgst_…` — type it, then Ctrl-J for line-feed in
   miniterm; the console ignores carriage returns and echoes
   nothing — or settings UI, or web flasher). Do not paste the
   token value into chat. Pairing (over BLE) delivers Wi-Fi and
   account credentials; it records the token, it does not
   create it.
2. Pair in the Muse app: Developer mode on, Add Device, BLE
   `MuseGadget-XXXXXX`, button confirm.
3. In Muse, invoke `watcher.coffee_mug` with `{"enabled": true}`. Every
   2 seconds it runs ImageNet classification; when a coffee
   mug is the top result above 75% it pushes "Watcher detected
   coffee mug with confidence X%." plus the
   image. Set `{"enabled": false}` to disarm. Double-click the
   wheel for the on-device live preview to check framing; close
   the preview before relying on the watch loop (preview owns
   the camera while open).

## Verify

```sh
sh tests/run_tests.sh
```

Host tests (SPI framing + event contract; the framing source is
read from the Grove submodule). Then capture both consoles at
once (e.g. 60 s) and expect: HX logs `Classifier Top 5` /
`Coffee mug (target 504): N%` per frame with zero `watcher NPU
wait timeout` lines and a nonzero `WD3_RAW` address at boot;
the ESP console logs `scores: mug=N | armed=mug` per cycle and
`@@JPEG` dumps. Verified behavior: 32 top-5 cycles with 0 ESP
timeouts, mug=0 with no mug in view, then 79/95/93/87/92% on a
centered white mug with 5 pushes. A threshold that never fires
is visible in the per-cycle mug percents instead of silent.

## Export a model + integrate other models

The committed model is the Himax model-zoo MobileNetV2 (see
`model/MODEL.md`). No export reproduces it:

```sh
cp sdk/Seeed_Grove_Vision_AI_Module_V2/model_zoo/torch_mb_cls/mv2_quant_himax_ini_opt_size_vela_4_5_0_inout_in8.pte model/
```

Verify the copy's SHA-256 (`70d2e36f…`, 3,516,944 bytes) and
on-device behavior before committing it. A different PyTorch
model needs a fresh export with the ExecuTorch 1.6 PTQ flow
(torch 2.15, ExecuTorch 1.6.0, Vela 5.2.0,
`model/himax_vela.ini`) instead; there is no export script in
this repo.

### The integration contract (read before substituting a model)

A model is integrable here when it meets all of these; anything
else needs new HX/ESP code, not just a new `.pte`:

1. **Delegate-friendly graph.** The whole backbone must
   partition to the Ethos-U delegate (Vela: ~100% NPU operators,
   no unsupported ops). Keep data-movement ops (reshape/permute/
   concat) trivial; keep box decoding and thresholding OFF the
   graph (CPU post-processing in the HX app).
2. **Int8 IO with a known mapping.** Export with the Himax PTQ
   flow (`EthosUQuantizer`, symmetric config) plus
   `QuantizeInputs`/`QuantizeOutputs`. The HX must know the exact
   input mapping (here: `(pixel - 128)`, input scale
   0.0078393, zero point 0) and the output percent mapping
   (here: top-5 percents use the linear map
   `(raw + 128) * 100 / 255`, not softmax). Document both
   mappings in `model/MODEL.md` — never guess them.
3. **Small, fixed IO.** Input is one fixed shape (here:
   1x3x224x224). Outputs must be selectable by shape on device
   (here: one `(1, 1000)` output, top-5 scan). The HX decode
   is a top-5 raw-logit scan; no boxes, no NMS. A model that
   needs on-device NMS, tracking, or landmarks is a bigger
   build — decide that explicitly before starting.
4. **Memory budgets (hard).** The mm pool ends at `0x34200000`;
   ExecuTorch pools + WDMA buffers must fit or the raw allocation
   fails silently to address 0 (check `WD3_RAW` in the boot log;
   nonzero is required). Current sizing: temp pool 897 KiB,
   method pool 384 KiB. The `.pte` must fit the 3.5 MB region
   at `0xB7B000`, and the firmware image must stay <= 1 MiB.
   Re-check all three numbers for any new model.
5. **Calibration data that matches deployment.** Calibrate with
   preprocessed inputs in the exact form the device will feed
   (here: `(pixel - 128)` int8, target class present + absent
   scenes + solids/noise). Verify the quantized module
   preserves separation (present high, absent low) before
   flashing, then verify on device. A model that only works
   in float has not been proven.
6. **HX + ESP integration points.** HX: input resize dims and
   input conversion in `cvapp_mb_cls.cpp`, output selection by
   shape, score math + the single-entry result in
   `g_watcher_last_*` (`watcher_result.h`), percent emission in
   `watcher_at_server.cpp` (percents use the linear map; no
   softmax). ESP: the `watcher.coffee_mug` command + watch-loop
   branch in `watcher_watch.{h,c}`, the `watcher.coffee_mug`
   registration in `noise_control.cpp`, and the push text in
   `muse_chat_send_detection()`. Keep the 2-second cadence, the
   per-cycle score log, and the one-thing-watched-at-a-time rule
   unless the product decision changes.
7. **Threshold from live data.** Do not invent a threshold.
   Start from the reference value if the model has one
   (here: 0.75 linear-map percent), then calibrate from live
   confidences (target present vs absent vs cover scenes,
   framing confirmed on the live preview). Record the chosen
   threshold and its evidence in `model/MODEL.md`.

### Common pitfalls (all observed on this project)

- **Chunked model flashes corrupt flash.** Always one full
  XMODEM transfer; split writes load but stall mid-inference.
- **HX power gating.** With Muse firmware installed, the HX is
  unpowered while idle: reflash the HX only via the ESP swap
  (above), with an NVS backup.
- **Bootloader prompt races.** One ESP reset produces several HX
  boots ~1 s apart; use the two-reset dance and the sender's
  4 s stability guard.
- **The 72% pause** (~20 s, slow flash erase) is normal, not a
  stall; the sender's ACK timeout is 60 s.
- **`WD3_RAW[0]`** means the raw frame allocation failed (pool
  exhaustion): inference reads constant data at address 0 while
  the JPEG keeps changing. Fix the budgets, don't tune the
  model.
- **NPU timeouts** print a register dump (`watcher NPU wait
  timeout`); a stalled stream with no fault bits means the
  command stream itself is suspect, not the driver.
- **`raw=down`, gadget not seen in the app.** The ESP heartbeat
  shows `raw=down` while `wifi=up ws=up` when the data-plane
  tunnel is down. The tunnel opens only after the server acks
  `link.register`, and if registration never completes in that
  session nothing retries it. Unplug and replug USB: the device
  re-registers and heartbeats should show `raw=up`. Reflashing
  the same firmware does not fix an unregistered device.

## Layout

```
README.md                  this file
.gitmodules / sdk/         pinned SDKs (see table above)
tools/                     build + flash scripts
  build_hx6538.sh          HX firmware build (Grove submodule)
  flash_hx6538.sh          HX firmware + model flash (XMODEM)
  build_muse_watcher.sh    ESP32 firmware build (Muse submodule)
  flash_muse_watcher.sh    ESP32 flash (paced esptool)
  xmodem_send.py           guarded XMODEM sender
  verify_esp.py            ESP console checker
model/                     mv2_quant_himax_ini_opt_size_vela_4_5_0_inout_in8.pte, himax_vela.ini, MODEL.md
tests/                     host tests (SPI framing, event contract)
```

Upstream licenses govern the contents of `sdk/`; the files in
`tools/`, `model/` (except the committed `.pte`, whose weights
are the Himax model-zoo file), and this
README are the project layer. `backups/` is deliberately
absent: back up from your own device before flashing.
