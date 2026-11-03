"""Parts routes, called in process against a temp data folder. No server needed.
Run: uv run --project webapp python webapp/test_parts_api.py"""
import os
import sys
import tempfile
from pathlib import Path

D = Path(tempfile.mkdtemp())
os.environ["CADDY_DATA_DIR"] = str(D / "data")
os.environ.pop("CAD_KEY_STDIN", None)
os.environ.pop("ANTHROPIC_API_KEY", None)  # canned edits only
sys.path.insert(0, str(Path(__file__).parent))
import numpy as np  # noqa: E402
from fastapi import HTTPException  # noqa: E402

import app  # noqa: E402
import processing as P  # noqa: E402

DATA = app.DATA
JOIN_MSG = "Push them together so they touch, then join."
MISS_MSG = "That line did not go through the part. Draw it across the part."


def err(fn, *args):
    """Call a route that should fail. Return (code, message)."""
    try:
        fn(*args)
    except HTTPException as e:
        assert set(e.detail) == {"message", "detail"}, e.detail
        return e.status_code, e.detail["message"]
    raise AssertionError(f"{fn.__name__} did not fail")


def start(tris):
    """Make tris the scanned model, as /api/scan would."""
    P._write_stl(DATA / "v0.stl", tris)
    app.state.update(status="ready", sample=False, redo=[], versions=[{"file": "v0.stl", "instruction": "Your scan"}])


def x_range(part):
    t = P.placed(part, DATA)[..., 0]
    return float(t.min()), float(t.max())


P.parts_op({"op": "library", "name": "cube", "out": str(D / "cube.stl")})  # 30 mm cube, seated
cube = P._read_stl(D / "cube.stl")

# split of one piece: state unchanged, with a note
start(cube)
s = app.parts_split({})
assert s["note"] == "It is one piece" and s["parts"] == [] and len(s["versions"]) == 1, s

# split of two far cubes: two parts side by side, no overlap
start(np.concatenate([cube + [-60, 0, 0], cube + [60, 0, 0]]))
s = app.parts_split({})
a, b = s["parts"]
assert len(s["versions"]) == 2 and s["note"] is None and s["putAway"] == [], s
assert x_range(a)[1] < x_range(b)[0] and a["z"] == b["z"] == 0, (x_range(a), x_range(b))
assert set(a) == {"id", "name", "file", "x", "y", "z", "yaw"}
assert set(app.status()) >= {"parts", "putAway", "note"}
assert err(app.parts_split, {})[0] == 409

# part files: served by name, no path tricks
assert str(app.part_file(a["file"]).path) == str(DATA / a["file"])
for bad in ("../v0.stl", "v0.stl", "state.json", "p1.stl"):
    assert err(app.part_file, bad)[0] == 404, bad

# move, then undo and redo restore the parts list
s = app.parts_move(app.Move(id=a["id"], x=-100, y=5, z=0, yaw=90))
assert s["parts"][0]["x"] == -100 and s["parts"][0]["yaw"] == 90, s
s = app.undo()
assert s["parts"][0]["x"] == a["x"] and len(s["redo"]) == 1, s
s = app.redo()
assert s["parts"][0]["x"] == -100 and not s["redo"], s
a = s["parts"][0]

# duplicate: new id, same file, 5 mm clear of the right-most part
s = app.parts_duplicate(app.PartId(id=a["id"]))
dup = s["parts"][-1]
assert len(s["parts"]) == 3 and dup["id"] != a["id"] and dup["file"] == a["file"] and dup["x"] - 15 >= max(float(app.processing.placed(p, app.DATA)[..., 0].max()) for p in s["parts"][:-1]) + 5 - 1e-3, s

# delete puts it in the tray, restore brings it back
s = app.parts_delete(app.PartId(id=dup["id"]))
assert len(s["parts"]) == 2 and s["putAway"] == [dup], s
assert err(app.parts_delete, app.PartId(id="nope"))[0] == 404
s = app.parts_restore(app.PartId(id=dup["id"]))
assert len(s["parts"]) == 3 and s["putAway"] == [] and s["parts"][-1] == dup, s
s = app.parts_delete(app.PartId(id=dup["id"]))

# add a library shape: on the floor, clear of the others
s = app.parts_add(app.AddShape(name="star"))
star = s["parts"][-1]
assert star["name"] == "Star" and star["z"] == 0 and x_range(star)[0] > max(x_range(p)[1] for p in s["parts"][:-1]), s
assert err(app.parts_add, app.AddShape(name="dragon"))[0] == 400
# add at a spot, as a hand drops it on the floor
s = app.parts_add(app.AddShape(name="cube", x=-60, y=35))
assert (s["parts"][-1]["x"], s["parts"][-1]["y"], s["parts"][-1]["z"]) == (-60, 35, 0), s
s = app.parts_delete(app.PartId(id=s["parts"][-1]["id"]))

# join: far apart is refused with the kid message, touching joins into one part
code, msg = err(app.parts_join, app.Join(ids=[a["id"], b["id"]]))
assert (code, msg) == (400, JOIN_MSG), (code, msg)
s = app.parts_move(app.Move(id=b["id"], x=a["x"] + 20, y=a["y"], z=0, yaw=0))
n = len(s["parts"])
s = app.parts_join(app.Join(ids=[a["id"], b["id"]]))
joined = s["parts"][-1]
assert len(s["parts"]) == n - 1 and joined["id"] not in (a["id"], b["id"]), s
assert abs(x_range(joined)[0] + 115) < 0.5 and abs(x_range(joined)[1] + 65) < 0.5, x_range(joined)

# cut: a plane through the middle gives two halves in place of the part, a few mm apart
s = app.parts_cut(app.Cut(id=joined["id"], point=[0, 0, 15], normal=[0, 0, 1]))
halves = s["parts"][-2:]
assert len(s["parts"]) == n and sorted(h["z"] for h in halves) == [0, 18], halves
code, msg = err(app.parts_cut, app.Cut(id=star["id"], point=[0, 0, 500], normal=[0, 0, 1]))
assert (code, msg) == (400, MISS_MSG), (code, msg)

# edit needs a part in parts mode, and replaces that part in place
assert err(app.edit, app.Edit(instruction="make it 20 percent taller"))[1] == "Pick a part first."
s = app.edit(app.Edit(instruction="make it 20 percent taller", part=star["id"]))
star2 = next(p for p in s["parts"] if p["id"] == star["id"])
assert star2["file"] != star["file"] and abs(star2["x"] - star["x"]) < 0.5 and star2["z"] == 0, star2
h = P._read_stl(DATA / star2["file"])[..., 2]
assert h.min() > -1e-3 and h.max() > 1.1 * P._read_stl(DATA / star["file"])[..., 2].max(), h.max()

# the export is every placed part merged, unjoined parts included
body = app.model().body
assert int.from_bytes(body[80:84], "little") == sum(len(P._read_stl(DATA / p["file"])) for p in s["parts"])

# bake writes the STL and a sidecar, open brings the build back
before = s
out = D / "saved" / "my build.stl"
app.parts_bake(app.BakePath(path=str(out)))
assert out.exists() and (D / "saved" / "my build.stl.parts" / "parts.json").exists()
assert err(app.parts_bake, app.BakePath(path="relative.stl"))[0] == 400
app.parts_add(app.AddShape(name="ball"))
s = app.parts_open(app.BakePath(path=str(out)))
assert s["parts"] == before["parts"] and s["putAway"] == before["putAway"] and len(s["versions"]) == 1, s
assert (DATA / s["versions"][0]["file"]).exists()
assert err(app.parts_open, app.BakePath(path=str(D / "nothing.stl")))[0] == 400

# single model mode still works: no parts, edit without a part, plain model.stl
start(cube)
s = app.edit(app.Edit(instruction="make it 20 percent taller"))
assert s["parts"] == [] and len(s["versions"]) == 2 and s["versions"][-1]["file"].startswith("v"), s
assert str(app.model().path).endswith(s["versions"][-1]["file"])
print("ok")

# wrap: a single model becomes one part, a second wrap changes nothing
start(cube)
s = app.parts_wrap()
assert len(s["parts"]) == 1 and s["parts"][0]["name"] == "Model" and len(s["versions"]) == 2, s
assert len(app.parts_wrap()["versions"]) == 2

# rotate: tipping 90 about x is one undoable version and writes a new mesh file
start(cube)
w = app.parts_wrap()
t = app.parts_rotate(app.Tip(id=w["parts"][0]["id"], degrees=90))
assert len(t["versions"]) == 3 and t["parts"][0]["file"] != w["parts"][0]["file"], t
print("ok")

t2 = app.parts_rotate(app.Tip(id=t["parts"][0]["id"], degrees=45, axis=35.0))
assert len(t2["versions"]) == 4
print("ok")

# resize, mirror, lay flat: each is one version with a new file, lay flat twice adds only one
P._write_stl(D / "bar.stl", P._read_stl(D / "cube.stl") * [10 / 30, 20 / 30, 40 / 30])  # 10 x 20 x 40, standing
start(P._read_stl(D / "bar.stl"))
w = app.parts_wrap()
pid, n = w["parts"][0]["id"], len(w["versions"])
s = app.parts_resize(app.Resize(id=pid, sx=1, sy=2, sz=1))
t = P.placed(s["parts"][0], DATA).reshape(-1, 3)
assert len(s["versions"]) == n + 1 and np.isclose(np.ptp(t[:, 1]), 40, atol=1e-3), np.ptp(t, 0)
assert err(app.parts_resize, app.Resize(id=pid, sx=1, sy=1, sz=7))[0] == 400
f = s["parts"][0]["file"]
s = app.parts_mirror(app.Mirror(id=pid, axis="y"))
assert len(s["versions"]) == n + 2 and s["parts"][0]["file"] != f, s
s = app.parts_layflat(app.LayFlat(id=pid))
t = P.placed(s["parts"][0], DATA).reshape(-1, 3)
assert len(s["versions"]) == n + 3 and np.ptp(t[:, 2]) < 40 - 1e-3 and abs(t[:, 2].min() - s["parts"][0]["z"]) < 1e-3, np.ptp(t, 0)
assert len(app.parts_layflat(app.LayFlat(id=pid))["versions"]) == n + 3
s = app.undo()
assert len(s["versions"]) == n + 2
print("ok")


def test_key_set_after_import_reaches_children():
    import processing
    os.environ["ANTHROPIC_API_KEY"] = "test-key"
    try:
        assert processing._env()["ANTHROPIC_API_KEY"] == "test-key"
    finally:
        os.environ.pop("ANTHROPIC_API_KEY")
