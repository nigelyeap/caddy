"""Smoke test for the local API that the web page and the Mac app both use.

Start the server first, then: uv run python test_api.py [http://localhost:8000]
It replaces the current model with the sample cup.
"""
import json
import sys
import time
import urllib.error
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"
STATE_KEYS = {"status", "error", "detail", "versions", "redo", "sample", "started", "engine"}


def call(method, path, body=None, ctype=None):
    req = urllib.request.Request(BASE + path, data=body, method=method)
    if ctype:
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            data = r.read()
            return r.status, json.loads(data) if r.headers.get_content_type() == "application/json" else data
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def post_json(path, obj):
    return call("POST", path, json.dumps(obj).encode(), "application/json")


def upload_sample():
    b = "----x"
    body = (f"--{b}\r\nContent-Disposition: form-data; name=\"video\"; filename=\"sample.webm\"\r\n"
            f"Content-Type: video/webm\r\n\r\n\r\n--{b}--\r\n").encode()
    return call("POST", "/api/scan", body, f"multipart/form-data; boundary={b}")


def is_error(code, body, want):
    return code == want and set(body["detail"]) == {"message", "detail"}


code, s = upload_sample()
assert code == 200 and s == {"status": "processing"}, (code, s)
for _ in range(60):
    code, s = call("GET", "/api/status")
    assert set(s) == STATE_KEYS, s.keys()
    if s["status"] != "processing":
        break
    time.sleep(1)
assert s["status"] == "ready" and s["sample"] and len(s["versions"]) == 1, s

code, stl = call("GET", "/api/model.stl")
assert code == 200 and len(stl) > 84, code

code, s = post_json("/api/edit", {"instruction": "make it 20 percent taller"})
assert code == 200 and set(s) == STATE_KEYS and len(s["versions"]) == 2, (code, s)

code, s = call("POST", "/api/undo")
assert len(s["versions"]) == 1 and len(s["redo"]) == 1, s
code, s = call("POST", "/api/redo")
assert len(s["versions"]) == 2 and not s["redo"], s

code, body = post_json("/api/edit", {"instruction": "   "})
assert is_error(code, body, 400), (code, body)
code, body = call("POST", "/api/guidance/frame", b"not a jpeg", "image/jpeg")
assert is_error(code, body, 400), (code, body)
import cv2  # noqa: E402  (the webapp env has it)
import numpy as np  # noqa: E402
ok, jpg = cv2.imencode(".jpg", np.random.default_rng(0).integers(0, 255, (360, 640, 3), dtype=np.uint8))
code, g = call("POST", "/api/guidance/frame", jpg.tobytes(), "image/jpeg")
assert code == 200 and {"blur", "light", "tracking", "speed", "coverage", "warnings", "t"} <= set(g), g
code, body = call("POST", "/api/guidance/reset")
assert body == {"ok": True}, body
print("ok")
