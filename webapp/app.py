"""CADDIY web app. Run: uv run uvicorn app:app --port 8000"""
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path

import cv2
import numpy as np
from fastapi import FastAPI, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, Response
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
    files = [f for v in _saved["versions"] + _saved["redo"]
             for f in [v["file"]] + [p["file"] for p in v.get("parts", []) + v.get("putAway", [])]]
    if all((DATA / f).exists() for f in files) and _saved["versions"]:
        state.update(status="ready", **_saved)
except (OSError, ValueError, KeyError):
    pass


def _snapshot():
    """The one state shape every state endpoint returns. Call with state_lock held.
    parts and putAway mirror the current version. Empty parts means the single model in versions[-1].file."""
    cur = state["versions"][-1] if state["versions"] else {}
    return {**state, "versions": list(state["versions"]), "redo": list(state["redo"]), "engine": ENGINE_NAME,
            "parts": list(cur.get("parts", [])), "putAway": list(cur.get("putAway", [])), "note": None}


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
    part: str | None = None


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
            parts, away = _scene()
            part = None
            if parts:
                part = next((p for p in parts if p["id"] == body.part), None)
                if part is None:
                    _fail(400, "Pick a part first.")
            cur = DATA / (part["file"] if part else state["versions"][-1]["file"])
            # Unique name so a redo entry is never overwritten.
            out = DATA / f"{'p' if part else 'v'}{time.time_ns()}.stl"
        try:
            processing.apply_edit(str(cur), text, str(out))
            if part:
                # Keep the part where it was: x, y follow the new centre, z stays on what it rested on.
                off = processing.reseat(str(out))
                dx, dy, _ = processing._yaw(part["yaw"]) @ [off[0], off[1], 0]
                new = {**part, "file": out.name, "x": part["x"] + float(dx), "y": part["y"] + float(dy)}
        except Exception as e:
            _fail(500, *_friendly(e))
        with state_lock:
            if part:
                _commit([new if p["id"] == part["id"] else p for p in parts], away, text)
            else:
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
        parts, _ = _scene()
        path = DATA / state["versions"][-1]["file"]
    if parts:
        return Response(processing.stl_bytes(processing.bake(parts, DATA)), media_type="model/stl",
                        headers={"Cache-Control": "no-store", "Content-Disposition": 'attachment; filename="model.stl"'})
    return FileResponse(path, media_type="model/stl", filename="model.stl",
                        headers={"Cache-Control": "no-store"})


# ---------- Many parts in one build ----------
# A part is {"id", "name", "file", "x", "y", "z", "yaw"}. file is a seated p<time_ns>.stl that is never
# rewritten or deleted, so undo and redo only swap JSON. Each version may carry "parts" and "putAway".

PART_FILE = re.compile(r"p\d+\.stl")
GAP = 10.0  # mm between parts laid out side by side


def _scene():
    """Current (parts, putAway) as fresh lists. Call with state_lock held."""
    cur = state["versions"][-1] if state["versions"] else {}
    return [dict(p) for p in cur.get("parts", [])], [dict(p) for p in cur.get("putAway", [])]


def _commit(parts, away, instruction):
    """Append one undoable version. Call with state_lock held. Returns the snapshot."""
    state["versions"].append({"file": state["versions"][-1]["file"], "instruction": instruction,
                              "parts": parts, "putAway": away})
    state["redo"] = []
    _save()
    return _snapshot()


def _new_part(name, file, x=0.0, y=0.0, z=0.0, yaw=0.0):
    return {"id": uuid.uuid4().hex[:8], "name": name, "file": file,
            "x": float(x), "y": float(y), "z": float(z), "yaw": float(yaw)}


def _find(parts, pid):
    p = next((p for p in parts if p["id"] == pid), None)
    if p is None:
        _fail(404, "That part is not in the build any more.")
    return p


def _width(file):
    tris = processing._read_stl(DATA / file).reshape(-1, 3)
    return float(tris[:, 0].max() - tris[:, 0].min())


def _right_edge(parts):
    """Largest x any placed part reaches, or None when there are none."""
    return max((float(processing.placed(p, DATA)[..., 0].max()) for p in parts), default=None)


def _ready_with_model():
    if not state["versions"]:
        _fail(409, "There is no model yet. Scan something first.")


@contextmanager
def _mesh_work():
    """Hold edit_lock for a parts.py op, and turn its errors into the usual error body."""
    if not edit_lock.acquire(blocking=False):
        _fail(409, "Still working on the last change. Wait a moment.")
    try:
        yield
    except ValueError as e:  # parts.py refusals are already plain words for the kid
        _fail(400, str(e))
    except subprocess.SubprocessError as e:
        _fail(500, *_friendly(e))
    except RuntimeError as e:
        _fail(500, "That did not work. Try again.", str(e)[-500:])
    finally:
        edit_lock.release()


@app.get("/api/part/{file}")
def part_file(file: str):
    path = DATA / file
    if not PART_FILE.fullmatch(file) or not path.exists():
        _fail(404, "That part file is missing.")
    return FileResponse(path, media_type="model/stl",
                        headers={"Cache-Control": "public, max-age=31536000, immutable"})


@app.post("/api/parts/split")
def parts_split(body: dict | None = None):
    with _mesh_work():
        with state_lock:
            _ready_with_model()
            if _scene()[0]:
                _fail(409, "This build is already in parts.")
            src = DATA / state["versions"][-1]["file"]
        found = processing.parts_op({"op": "split", "in": str(src), "out_dir": str(DATA)})["parts"]
        with state_lock:
            if len(found) < 2:
                return {**_snapshot(), "note": "It is one piece"}
            widths = [_width(p["file"]) for p in found]
            x = -(sum(widths) + GAP * (len(widths) - 1)) / 2
            parts = []
            for i, (p, w) in enumerate(zip(found, widths)):
                parts.append(_new_part(f"Part {i + 1}", p["file"], x + w / 2))
                x += w + GAP
            return _commit(parts, [], f"Split into {len(parts)} parts")


@app.post("/api/parts/wrap")
def parts_wrap(body: dict | None = None):
    """Turn a single model into one part, so it can be moved, copied and cut. No-op when it already is parts."""
    with _mesh_work():
        with state_lock:
            _ready_with_model()
            parts, away = _scene()
            if parts:
                return _snapshot()
            first = DATA / f"p{time.time_ns()}.stl"
            shutil.copyfile(DATA / state["versions"][-1]["file"], first)
            return _commit([_new_part("Model", first.name, *processing.reseat(str(first)))], away, "Ready to move and cut")


class Tip(BaseModel):
    id: str
    degrees: float
    axis: str | float = "x"  # "x", "y", or a flat azimuth in degrees (0 = x, 90 = y)


@app.post("/api/parts/rotate")
def parts_rotate(body: Tip):
    """Tip a part over the x (or y) axis. The mesh is rewritten as a new immutable file, so undo just points back."""
    with _mesh_work():
        with state_lock:
            parts, _ = _scene()
            p = _find(parts, body.id)
            src, yaw = DATA / p["file"], p["yaw"]
        out = processing.parts_op({"op": "rotate", "in": str(src), "out_dir": str(DATA), "axis": body.axis,
                                   "degrees": body.degrees, "yaw": yaw})
        with state_lock:
            parts, away = _scene()
            p = _find(parts, body.id)
            p["file"] = out["file"]
            return _commit(parts, away, f"Tipped {p['name']}")


def _reshape(pid, req, verb):
    """Run a parts.py op on one part as a new mesh file and commit it as one undoable version.
    The op may return yaw and a shift for x, y. A file of None means nothing changed."""
    with state_lock:
        p = _find(_scene()[0], pid)
        src, yaw = DATA / p["file"], p["yaw"]
    out = processing.parts_op({**req, "in": str(src), "out_dir": str(DATA), "yaw": yaw})
    with state_lock:
        parts, away = _scene()
        p = _find(parts, pid)
        if out["file"] is None:
            return _snapshot()
        dx, dy = out.get("shift", (0, 0))
        p.update(file=out["file"], x=p["x"] + dx, y=p["y"] + dy, yaw=float(out.get("yaw", p["yaw"])))
        return _commit(parts, away, f"{verb} {p['name']}")


class Resize(BaseModel):
    id: str
    sx: float
    sy: float
    sz: float  # factors in world axes, 0.05 to 20


@app.post("/api/parts/resize")
def parts_resize(body: Resize):
    with _mesh_work():
        return _reshape(body.id, {"op": "resize", "sx": body.sx, "sy": body.sy, "sz": body.sz}, "Resized")


class Mirror(BaseModel):
    id: str
    axis: str | float = "x"  # mirror plane normal: "x", "y", or a flat azimuth in degrees


@app.post("/api/parts/mirror")
def parts_mirror(body: Mirror):
    with _mesh_work():
        return _reshape(body.id, {"op": "mirror", "axis": body.axis}, "Mirrored")


class LayFlat(BaseModel):
    id: str


@app.post("/api/parts/layflat")
def parts_layflat(body: LayFlat):
    with _mesh_work():
        return _reshape(body.id, {"op": "layflat"}, "Laid flat")


class Move(BaseModel):
    id: str
    x: float
    y: float
    z: float
    yaw: float


@app.post("/api/parts/move")
def parts_move(body: Move):
    _busy_check()
    with state_lock:
        parts, away = _scene()
        p = _find(parts, body.id)
        p.update(x=body.x, y=body.y, z=body.z, yaw=body.yaw)
        return _commit(parts, away, f"Moved {p['name']}")


class PartId(BaseModel):
    id: str


@app.post("/api/parts/duplicate")
def parts_duplicate(body: PartId):
    _busy_check()
    with state_lock:
        parts, away = _scene()
        p = _find(parts, body.id)
        c = _new_part(p["name"], p["file"], 0, p["y"], p["z"], p["yaw"])
        xs = processing.placed(c, DATA)[..., 0]  # copy goes 5 mm clear of the right-most part
        c["x"] = float(_right_edge(parts) + 5 - xs.min())
        parts.append(c)
        return _commit(parts, away, f"Copied {p['name']}")


@app.post("/api/parts/delete")
def parts_delete(body: PartId):
    _busy_check()
    with state_lock:
        parts, away = _scene()
        p = _find(parts, body.id)
        parts.remove(p)
        return _commit(parts, away + [p], f"Put away {p['name']}")


@app.post("/api/parts/restore")
def parts_restore(body: PartId):
    _busy_check()
    with state_lock:
        parts, away = _scene()
        p = _find(away, body.id)
        away.remove(p)
        return _commit(parts + [p], away, f"Brought back {p['name']}")


class AddShape(BaseModel):
    name: str
    # Where to put it, bottom centre in mm. Left out, it goes to the right of the other parts.
    x: float | None = None
    y: float | None = None


@app.post("/api/parts/add")
def parts_add(body: AddShape):
    with _mesh_work():
        with state_lock:
            _ready_with_model()
        out = DATA / f"p{time.time_ns()}.stl"
        processing.parts_op({"op": "library", "name": body.name, "out": str(out)})
        with state_lock:
            parts, away = _scene()
            if not parts:  # first add to a single model: that model becomes part one, left where it was
                first = DATA / f"p{time.time_ns()}.stl"
                shutil.copyfile(DATA / state["versions"][-1]["file"], first)
                parts = [_new_part("Model", first.name, *processing.reseat(str(first)))]
            if body.x is not None:
                x, y = body.x, body.y or 0.0
            else:
                edge = _right_edge(parts)
                x, y = (0.0 if edge is None else edge + GAP + _width(out.name) / 2), 0.0
            parts.append(_new_part(body.name.capitalize(), out.name, x, y))
            return _commit(parts, away, f"Added a {body.name}")


class Join(BaseModel):
    ids: list[str]


@app.post("/api/parts/join")
def parts_join(body: Join):
    with _mesh_work():
        with state_lock:
            parts, away = _scene()
            picked = [_find(parts, i) for i in dict.fromkeys(body.ids)]
        r = processing.parts_op({"op": "join", "parts": picked, "out_dir": str(DATA)})["parts"][0]
        with state_lock:
            ids = {p["id"] for p in picked}
            rest = [p for p in parts if p["id"] not in ids]
            joined = _new_part(picked[0]["name"], r["file"], *r["offset"])
            return _commit(rest + [joined], away, f"Joined {len(picked)} parts")


class Cut(BaseModel):
    id: str
    point: list[float]
    normal: list[float]


@app.post("/api/parts/cut")
def parts_cut(body: Cut):
    if len(body.point) != 3 or len(body.normal) != 3 or not any(body.normal):
        _fail(400, "Draw a longer line.")
    with _mesh_work():
        with state_lock:
            parts, away = _scene()
            p = _find(parts, body.id)
        found = processing.parts_op({"op": "cut", "in": str(DATA / p["file"]), "out_dir": str(DATA),
                                     "point": body.point, "normal": body.normal})["parts"]
        # Each piece's offset is its bottom centre in the part's frame. Turn it into the build,
        # then nudge it 3 mm along the cut normal, away from the other side.
        rot = processing._yaw(p["yaw"])
        n = rot @ (np.asarray(body.normal, np.float32) / np.linalg.norm(body.normal))
        pieces = []
        for q in found:
            pos = rot @ np.asarray(q["offset"], np.float32) + [p["x"], p["y"], p["z"]]
            pos += (3 if q["side"] == "+" else -3) * n
            pieces.append(_new_part(p["name"], q["file"], pos[0], pos[1], max(float(pos[2]), 0.0), p["yaw"]))
        with state_lock:
            i = parts.index(p)
            return _commit(parts[:i] + pieces + parts[i + 1:], away, f"Cut {p['name']}")


class BakePath(BaseModel):
    path: str


def _sidecar(path):
    p = Path(path)
    if not p.is_absolute() or p.suffix.lower() != ".stl":
        _fail(400, "Give a full path to an .stl file.")
    return p, Path(str(p) + ".parts")


@app.post("/api/parts/bake")
def parts_bake(body: BakePath):
    """Write the merged build to path, and path.parts/ with parts.json and the part files to reopen it."""
    stl, side = _sidecar(body.path)
    with state_lock:
        _ready_with_model()
        parts, away = _scene()
        snap = _snapshot()
    if not parts:
        _fail(409, "This build has no parts. Save the model instead.")
    side.mkdir(parents=True, exist_ok=True)
    stl.write_bytes(processing.stl_bytes(processing.bake(parts, DATA)))
    for f in {p["file"] for p in parts + away}:
        shutil.copyfile(DATA / f, side / f)
    (side / "parts.json").write_text(json.dumps({"parts": parts, "putAway": away}, indent=1))
    return snap


@app.post("/api/parts/open")
def parts_open(body: BakePath):
    """Start a new build from a file saved by /api/parts/bake."""
    _busy_check()
    stl, side = _sidecar(body.path)
    try:
        saved = json.loads((side / "parts.json").read_text())
        parts, away = saved["parts"], saved.get("putAway", [])
        for p in parts + away:
            if not PART_FILE.fullmatch(p["file"]):
                raise ValueError(p["file"])
            p.update(id=str(p["id"]), name=str(p["name"]), **{k: float(p[k]) for k in ("x", "y", "z", "yaw")})
            if not (DATA / p["file"]).exists():  # same name means same bytes, files are never rewritten
                shutil.copyfile(side / p["file"], DATA / p["file"])
        model_file = f"v{time.time_ns()}.stl"
        shutil.copyfile(stl, DATA / model_file)
    except (OSError, ValueError, KeyError, TypeError) as e:
        _fail(400, "That saved build could not be opened.", str(e)[-500:])
    with state_lock:
        state.update(status="ready", error=None, detail=None, sample=False, redo=[], started=None,
                     versions=[{"file": model_file, "instruction": "Opened build", "parts": parts, "putAway": away}])
        _save()
        return _snapshot()


app.mount("/", StaticFiles(directory=HERE / "static", html=True), name="static")
