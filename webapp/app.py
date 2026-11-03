"""CADDIY web app. Run: uv run uvicorn app:app --port 8000"""
import json
import math
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

import cv2
import numpy as np
from fastapi import FastAPI, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import processing

HERE = Path(__file__).parent
# The packaged app sets CADDIY_DATA_DIR, since its own folder is read only.
DATA = Path(os.environ.get("CADDIY_DATA_DIR") or HERE / "data")
DATA.mkdir(parents=True, exist_ok=True)


def _key_from_parent():
    """The Mac app sets CAD_KEY_STDIN=1 and owns our stdin.

    The first line is the Claude key, or empty. The key goes over a pipe so it never sits
    in the launch environment where other processes can read it. Never log it.
    When the app closes the pipe (it quit or crashed), stop the server so it is not orphaned.
    """
    if os.environ.get("CAD_KEY_STDIN") != "1":
        return
    key = sys.stdin.readline().strip()
    if key:
        os.environ["ANTHROPIC_API_KEY"] = key

    def _exit_on_eof():
        sys.stdin.read()
        os.kill(os.getpid(), signal.SIGTERM)

    threading.Thread(target=_exit_on_eof, daemon=True).start()


_key_from_parent()


# ---------- Guidance engine ----------
# CAD_GUIDANCE=auto (default): use ../guidance/guidance.py if it imports, else the stub.
# CAD_GUIDANCE=real: require the real engine. CAD_GUIDANCE=stub: always use the stub.

class StubSession:
    """STUB guidance engine. Blur and light are measured for real. Tracking, speed and coverage are fake."""

    def __init__(self, sectors=12):
        self.n = sectors
        self.reset()

    def reset(self):
        self.cov = [0.0] * self.n
        self.t0 = None

    def update(self, frame_bgr, t, depth=None, pose=None):
        if self.t0 is None:
            self.t0 = t
        gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
        blur = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        mean = float(gray.mean())
        clipped = float(((gray < 5) | (gray > 250)).mean() * 100)
        issue = "dark" if mean < 60 else "bright" if mean > 200 else "glare" if clipped > 10 else None
        # Fake walk-around: one sector every 2 seconds.
        k = int((t - self.t0) / 2) % self.n
        self.cov[k] = min(1.0, self.cov[k] + 0.35)
        speed = 0.5 + 0.4 * math.sin(t / 3)
        warnings = []
        if blur < 60:
            warnings.append("The picture is blurry. Hold the camera still for a moment.")
        if issue == "dark":
            warnings.append("It is too dark. Turn on more lights.")
        elif issue in ("bright", "glare"):
            warnings.append("Too much glare. Move away from bright lights.")
        if speed > 0.8:
            warnings.append("Slow down a little.")
        return {
            "blur": {"score": round(blur, 1), "ok": blur >= 60},
            "light": {"mean": round(mean, 1), "clipped_pct": round(clipped, 1), "ok": issue is None, "issue": issue},
            "tracking": {"match_ratio": 0.8, "ok": True},
            "speed": {"value": round(speed, 2), "ok": speed <= 0.8},
            "coverage": {"sectors": [round(c, 2) for c in self.cov], "pct": round(100 * sum(self.cov) / self.n, 1)},
            "warnings": warnings,
            "t": t,
        }


def _load_engine():
    mode = os.environ.get("CAD_GUIDANCE", "auto")
    if mode != "stub":
        sys.path.insert(0, str(HERE.parent))
        try:
            from guidance.guidance import Session
            return Session, "real"
        except ImportError:
            if mode == "real":
                raise
    return StubSession, "stub"


Engine, ENGINE_NAME = _load_engine()
guide = Engine(sectors=12)
guide_lock = threading.Lock()


# ---------- Model state (single user, kept in memory) ----------
# ponytail: one global session, fine for one Mac in one classroom.
# versions: [{"file", "instruction"}]. redo holds undone versions, newest last.
# sample is True when the model is the stand-in cup, so the page can say so.
state = {"status": "idle", "error": None, "detail": None, "versions": [], "redo": [],
         "sample": False, "started": None}
state_lock = threading.Lock()
edit_lock = threading.Lock()
STATE_FILE = DATA / "state.json"


def _save():
    """Keep the model across a server restart. Call with state_lock held."""
    if state["status"] == "ready":
        STATE_FILE.write_text(json.dumps({k: state[k] for k in ("versions", "redo", "sample")}))


try:
    _saved = json.loads(STATE_FILE.read_text())
    if all((DATA / v["file"]).exists() for v in _saved["versions"] + _saved["redo"]) and _saved["versions"]:
        state.update(status="ready", **_saved)
except (OSError, ValueError, KeyError):
    pass


def _snapshot():
    """The one state shape every state endpoint returns. Call with state_lock held."""
    return {**state, "versions": list(state["versions"]), "redo": list(state["redo"]), "engine": ENGINE_NAME}


def _fail(code, message, detail=None):
    """Every error the app raises has the same body: {"detail": {"message", "detail"}}."""
    raise HTTPException(code, {"message": message, "detail": detail})


def _friendly(e):
    """Short message for the kid, plus the raw text for the teacher."""
    raw = str(e)[-500:]
    if isinstance(e, subprocess.TimeoutExpired):
        return "That took too long. Try a simpler change.", raw
    if "no API key" in raw or "no canned script" in raw:
        return "Without the Claude key I only know the example changes. Tap one of those.", raw
    if "refused" in raw:
        return "Claude would not make that change. Try asking for something else.", raw
    if "printable" in raw or "watertight" in raw:
        return "That change broke the shape, so I kept the old one. Try it a different way.", raw
    return "That change did not work. Try saying it another way.", raw


# Turntable importer error phrases (bench/turntable.py) mapped to what a kid can do about it.
# The page and the Mac app add "Scan again, or use the sample model." after this text.
SCAN_HINTS = {
    "no readable points": "This file has no scan points in it. Check you picked the scan file from the SD card.",
    "too few layers": "The scanner did not see enough layers. Let the scan run until the top of the object.",
    "too few points": "The scan stopped too early. Let the turntable go all the way round.",
    "out of range": "Most readings were too far or too close. Put the object in the middle of the turntable.",
}


def _friendly_scan(e):
    """Like _friendly, for a scan that could not become a shape."""
    raw = str(e)[-500:]
    if isinstance(e, subprocess.TimeoutExpired):
        return "The scan took too long to turn into a shape.", raw
    hint = next((m for k, m in SCAN_HINTS.items() if k in raw), None)
    return hint or "The scan could not be turned into a shape.", raw


def _process(video_path):
    out = DATA / "v0.stl"
    sample = video_path.suffix.lower() not in processing.MESH_EXT | processing.TURNTABLE_EXT
    try:
        processing.clean_scan(str(video_path), str(out))
        with state_lock:
            state.update(status="ready", sample=sample, redo=[],
                         versions=[{"file": out.name, "instruction": "Sample cup" if sample else "Your scan"}])
            _save()
    except Exception as e:
        with state_lock:
            msg, raw = _friendly_scan(e)
            state.update(status="error", error=msg, detail=raw)


app = FastAPI()


@app.get("/api/status")
def status():
    with state_lock:
        return _snapshot()


@app.post("/api/guidance/frame")
async def guidance_frame(request: Request):
    buf = np.frombuffer(await request.body(), np.uint8)
    frame = cv2.imdecode(buf, cv2.IMREAD_COLOR) if buf.size else None
    if frame is None:
        _fail(400, "Send one JPEG image as the request body.")
    with guide_lock:
        return guide.update(frame, time.monotonic())


@app.post("/api/guidance/reset")
def guidance_reset():
    with guide_lock:
        guide.reset()
    return {"ok": True}


@app.post("/api/scan")
def upload_scan(video: UploadFile):
    with state_lock:
        if state["status"] == "processing" or edit_lock.locked():
            _fail(409, "Still working on the last scan or change. Wait a moment.")
        state.update(status="processing", error=None, detail=None, versions=[], redo=[],
                     started=time.time())
    for old in DATA.glob("v*.stl"):
        old.unlink(missing_ok=True)
    path = DATA / ("scan" + Path(video.filename or "scan.webm").suffix)
    with open(path, "wb") as f:
        shutil.copyfileobj(video.file, f)
    threading.Thread(target=_process, args=(path,), daemon=True).start()
    return {"status": "processing"}


class Edit(BaseModel):
    instruction: str


@app.post("/api/edit")
def edit(body: Edit):
    text = body.instruction.strip()
    if not text:
        _fail(400, "Type what you want to change.")
    # The edit can take 30 s or more. Hold edit_lock, not state_lock, so status polls stay fast.
    if not edit_lock.acquire(blocking=False):
        _fail(409, "Still working on the last change. Wait a moment.")
    try:
        with state_lock:
            if not state["versions"]:
                _fail(409, "There is no model yet. Scan something first.")
            cur = DATA / state["versions"][-1]["file"]
            # Unique name so a redo entry is never overwritten.
            out = DATA / f"v{time.time_ns()}.stl"
        try:
            processing.apply_edit(str(cur), text, str(out))
        except Exception as e:
            _fail(500, *_friendly(e))
        with state_lock:
            state["versions"].append({"file": out.name, "instruction": text})
            state["redo"] = []
            _save()
            return _snapshot()
    finally:
        edit_lock.release()


def _busy_check():
    if edit_lock.locked():
        _fail(409, "Still working on the last change. Wait a moment.")


@app.post("/api/undo")
def undo():
    _busy_check()
    with state_lock:
        if len(state["versions"]) > 1:
            state["redo"].append(state["versions"].pop())
            _save()
        return _snapshot()


@app.post("/api/redo")
def redo():
    _busy_check()
    with state_lock:
        if state["redo"]:
            state["versions"].append(state["redo"].pop())
            _save()
        return _snapshot()


@app.get("/api/model.stl")
def model():
    with state_lock:
        if not state["versions"]:
            _fail(404, "There is no model yet. Scan something first.")
        path = DATA / state["versions"][-1]["file"]
    return FileResponse(path, media_type="model/stl", filename="model.stl",
                        headers={"Cache-Control": "no-store"})


app.mount("/", StaticFiles(directory=HERE / "static", html=True), name="static")
