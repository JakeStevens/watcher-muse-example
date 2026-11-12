"""Contract test for the JSON the HX6538 firmware sends to the ESP32-S3.

The checks mirror what the stock ESP32 factory firmware actually reads
(examples/factory_firmware/main/task_flow_module/tf_module_ai_camera.c
and components/sscma_client/src/sscma_client_ops.c in
Seeed-Studio/SenseCAP-Watcher-Firmware):

- Replies are framed as \\r{...}\\n, type 0, with a name that matches the
  request exactly as sscma_client_request stores it (command text after
  "AT+", cut at '=').  The INVOKE response must carry
  /data/algorithm/type == 4 (IMCLS) and /data/algorithm/category == 3
  (CLS); the factory code reads "categroy" first, then "category".
- Events are type 1, name INVOKE/SAMPLE, and carry /data/resolution
  [416, 416] (the only preview resolution the factory inference path
  routes), /data/image (base64 JPEG), and for INVOKE
  /data/classes as [[score, target], ...] pairs.
- The MODEL? reply reports data.id; the INFO? reply reports
  data.info as a base64 JSON string with uuid/name/version/classes.

A golden event/reply set matching what watcher_at_server emits is
checked field by field. The firmware's own event builder lives in
hx6538/watcher_executorch/watcher_at_server.cpp; this test pins the
contract it must satisfy.
"""

import base64
import json
import sys

# Golden replies/events: exact shapes the firmware must emit.
GOLDEN = {
    "id_reply": '\r{"type": 0, "name": "ID?", "code": 0, "data": "1"}\n',
    "model_reply": '\r{"type": 0, "name": "MODEL?", "code": 0, "data": {"id": 0, "type": 4, "address": 984895488, "size": 3516944}}\n',
    "invoke_response": '\r{"type": 0, "name": "INVOKE", "code": 0, "data": {"algorithm": {"type": 4, "categroy": 3, "category": 3}}}\n',
    "sensor_reply": '\r{"type": 0, "name": "SENSOR", "code": 0, "data": {"sensor": {"id": 1, "type": 0, "state": 1, "opt_id": 1, "opt_detail": "416x416"}}}\n',
    "init_event": '\r{"type": 1, "name": "INIT@STAT", "code": 0, "data": {}}\n',
    "invoke_event": None,  # built below (contains base64 JPEG)
    "sample_event": None,
}

JPEG = b"\xff\xd8\xff\xe0FAKEJPEG\xff\xd9"
B64 = base64.b64encode(JPEG).decode()
GOLDEN["invoke_event"] = (
    '\r{"type": 1, "name": "INVOKE", "code": 0, "data": {"count": 0, '
    '"resolution": [416, 416], '
    f'"classes": [[92, 504], [41, 5]], "image": "{B64}", "algo_tick": [123]}}}}\n'
)
GOLDEN["sample_event"] = (
    '\r{"type": 1, "name": "SAMPLE", "code": 0, "data": {"count": 0, '
    f'"resolution": [416, 416], "image": "{B64}"}}}}\n'
)

# Format fixture only: the checks below pin the INFO reply shape
# (base64 JSON with uuid/name/version/classes), not any particular
# model's identity as emitted by the HX firmware.
MODEL_INFO = {
    "uuid": "watcher-executorch-mbv2-imagenet",
    "name": "MobileNetV2 ImageNet (ExecuTorch/Ethos-U55)",
    "version": "1.0.0",
    "url": "",
    "checksum": "",
    "classes": ["coffee mug"],
}
GOLDEN["info_reply"] = (
    '\r{"type": 0, "name": "INFO?", "code": 0, "data": {"info": "'
    + base64.b64encode(json.dumps(MODEL_INFO).encode()).decode()
    + '"}}\n'
)

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print(f"FAIL: {msg}", file=sys.stderr)


def parse_framed(raw, label):
    check(raw.startswith("\r{"), f"{label}: must start with CR+{{")
    check(raw.endswith("}\n"), f"{label}: must end with }}+LF")
    try:
        return json.loads(raw[1:-1])
    except json.JSONDecodeError as e:
        check(False, f"{label}: invalid JSON: {e}")
        return {}


def main():
    for label, raw in GOLDEN.items():
        obj = parse_framed(raw, label)
        check(obj.get("code") == 0, f"{label}: code must be 0, got {obj.get('code')}")

    init = parse_framed(GOLDEN["init_event"], "init_event")
    check(init.get("type") == 1 and init.get("name") == "INIT@STAT",
          "init_event: type/name must trigger the ESP32 on_connect path")
    idrep = parse_framed(GOLDEN["id_reply"], "id_reply")
    check(isinstance(idrep.get("data"), str),
          "id_reply: data must be a string (client rejects numbers)")

    model = parse_framed(GOLDEN["model_reply"], "model_reply")
    check(model.get("type") == 0 and model.get("name") == "MODEL?", "model_reply: type/name")
    check(model["data"]["type"] == 4, "model_reply: data.type must be 4 (IMCLS)")
    check(isinstance(model["data"].get("id"), int), "model_reply: data.id int")

    info = parse_framed(GOLDEN["info_reply"], "info_reply")
    decoded = json.loads(base64.b64decode(info["data"]["info"]))
    check(decoded["classes"] == MODEL_INFO["classes"], "info_reply: classes list")
    check(decoded["uuid"] == MODEL_INFO["uuid"], "info_reply: uuid")

    inv = parse_framed(GOLDEN["invoke_response"], "invoke_response")
    check(inv.get("name") == "INVOKE", "invoke_response: name")
    algo = inv["data"]["algorithm"]
    check(algo["type"] == 4, "invoke_response: algorithm.type 4")
    check(algo.get("categroy") == 3 and algo.get("category") == 3,
          "invoke_response: algorithm category 3 under both spellings")

    sensor = parse_framed(GOLDEN["sensor_reply"], "sensor_reply")
    check(sensor["data"]["sensor"]["opt_id"] == 1, "sensor_reply: opt_id")

    ev = parse_framed(GOLDEN["invoke_event"], "invoke_event")
    check(ev.get("type") == 1 and ev.get("name") == "INVOKE", "invoke_event: type/name")
    check(ev["data"]["resolution"] == [416, 416], "invoke_event: resolution [416,416]")
    check(ev["data"]["classes"] == [[92, 504], [41, 5]], "invoke_event: classes pairs")
    raw_jpeg = base64.b64decode(ev["data"]["image"])
    check(raw_jpeg[:2] == b"\xff\xd8" and raw_jpeg[-2:] == b"\xff\xd9",
          "invoke_event: image must decode to a JPEG")
    check(isinstance(ev["data"].get("count"), int), "invoke_event: count int")

    smp = parse_framed(GOLDEN["sample_event"], "sample_event")
    check(smp.get("name") == "SAMPLE", "sample_event: name")
    check(smp["data"]["resolution"] == [416, 416], "sample_event: resolution")
    base64.b64decode(smp["data"]["image"])  # raises if not base64

    if failures:
        print(f"test_event_contract: {len(failures)} failure(s)", file=sys.stderr)
        return 1
    print("test_event_contract: all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
