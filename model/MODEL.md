# Reference model

Current: MobileNetV2 ImageNet coffee mug detection (ExecuTorch 1.6).

## MobileNetV2 ImageNet (current)

File: `mv2_quant_himax_ini_opt_size_vela_4_5_0_inout_in8.pte`

- Source: Himax model zoo (`model_zoo/torch_mb_cls`), already
  quantized for Ethos-U. No export is needed to reproduce it:
  copy the model-zoo file into `model/`.
- Task: ImageNet classification, 1000 classes. Input 1x3x224x224
  int8 IO. Output: (1, 1000) int8 logits. The HX app decodes
  the top 5 by raw int8 value; percents use the linear map
  `(raw + 128) * 100 / 255` (not softmax). Target 504 is the
  coffee mug: the ESP fires only when target 504 is the top
  entry above 75%.
- Quantization: Vela 4.5.0 int8, Ethos-U delegate. Input
  mapping on device: (pixel - 128) (input scale 0.0078393,
  zero point 0). Input size comes from the loaded method.
- Pools (HX firmware): temp pool 897 KiB, method pool 384 KiB.
  The 224x224 delegate scratch does not fit a 640 KiB temp
  pool, and the 736 KiB method pool exhausted the shared mm
  pool first (`WD3_RAW[0]`, DATAPATH init fail). Verify
  `WD3_RAW` is nonzero in the boot log.
- ET12 header, 3,516,944 bytes.
- SHA-256: `70d2e36f0c0c12d972230dc3ab51a327f46fa1da112d6e9a7a346f0a045f11e9`
- Runtime: ExecuTorch 1.6 vendored in the Grove SDK submodule
  (`library/inference/executorch160/`).
- Flash: ONE full XMODEM transfer of the `.pte` at `0xB7B000`
  (see `README.md` — split/chunked model writes corrupt flash).
- Verified on device: input `[1, 3, 224, 224]` int8, output
  `[1, 1000]` int8, `WD3_RAW` nonzero, 0 scratch failures,
  32 top-5 cycles with 0 ESP timeouts. Live calibration: 11
  no-mug cycles read mug=0, then a centered white mug read
  79/95/93/87/92% and fired 5 pushes. The 75% threshold is
  kept: the gap between 0% absent and 79% present is wide,
  and the 79% frame was the mug just entering the frame.
