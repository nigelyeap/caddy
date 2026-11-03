"""Scan cleanup and mesh editing.

Mesh cleanup and edits call the bench code through its own uv environment,
or through the Python named by CADDY_PYTHON in the packaged app.
Video to mesh reconstruction does not exist yet, so a video input still gets
the sample cup.
"""
import json
import os
import struct
import subprocess
import time
from pathlib import Path

import numpy as np

BENCH = Path(__file__).resolve().parent.parent / "bench"
MESH_EXT = {".ply", ".obj", ".stl"}
# Turntable scanner SD card files (x,y,z lines). bench/turntable.py makes them a printable mm mesh.
TURNTABLE_EXT = {".txt", ".csv"}
TURNTABLE_CALIB = BENCH / "turntable_calib.json"


def _cmd():
    py = os.environ.get("CADDY_PYTHON")
    return [py] if py else ["uv", "run", "--project", str(BENCH), "python"]


def _env():
    """Read at call time: app.py sets ANTHROPIC_API_KEY after this module is imported."""
    return {k: v for k, v in os.environ.items() if k != "VIRTUAL_ENV"}


def _bench(script, *args):
    r = subprocess.run([*_cmd(), str(BENCH / script), *map(str, args)],
                       capture_output=True, text=True, timeout=300, env=_env())
    if r.returncode:
        # edit.py prints the technical reason on stdout and only the kid message on stderr, so keep both.
        raise RuntimeError((r.stdout[-400:] + "\n" + r.stderr)[-600:])


def clean_scan(path_in, path_out_stl):
    """Turn a scan into a clean, printable STL."""
    if Path(path_in).suffix.lower() in TURNTABLE_EXT:
        # Already printable mm with the base on z=0. clean.py would guess units and cut the base as a table.
        calib = ["--calib", TURNTABLE_CALIB] if TURNTABLE_CALIB.exists() else []
        _bench("turntable.py", path_in, path_out_stl, *calib)
        return
    if Path(path_in).suffix.lower() in MESH_EXT:
        _bench("clean.py", path_in, path_out_stl)
        return
    # ponytail: no video-to-mesh step yet, add reconstruction here (LiDAR or photogrammetry)
    time.sleep(3)
    _write_stl(path_out_stl, _cup())


def apply_edit(stl_in, instruction, stl_out):
    """Apply a plain-language edit through Claude (needs ANTHROPIC_API_KEY, else a canned script)."""
    _bench("edit.py", stl_in, instruction, stl_out)


# ---------- many parts ----------
# The webapp env has no trimesh or manifold3d, so mesh ops go to one long-lived `parts.py --serve` worker
# in the bench env. That pays the ~0.4 s start once. Callers hold app.edit_lock, so one op at a time.
_worker = None


def parts_op(req):
    """One parts.py op. Returns its JSON. A kid-facing refusal raises ValueError, a crash RuntimeError."""
    global _worker
    if _worker is None or _worker.poll() is not None:
        _worker = subprocess.Popen([*_cmd(), str(BENCH / "parts.py"), "--serve"], text=True, env=_env(),
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    # ponytail: no timeout on readline, ops are a few seconds. Add a watchdog thread if one ever hangs.
    _worker.stdin.write(json.dumps(req) + "\n")
    _worker.stdin.flush()
    line = _worker.stdout.readline()
    if not line:
        _worker = None
        raise RuntimeError(f"parts worker stopped during {req.get('op')}")
    out = json.loads(line)
    if "error" in out:
        raise ValueError(out["error"])
    return out


def _yaw(deg):
    a = np.radians(deg)
    return np.array([[np.cos(a), -np.sin(a), 0], [np.sin(a), np.cos(a), 0], [0, 0, 1]], np.float32)


def placed(part, base_dir):
    """A part's triangles in the build frame: turn about z by yaw, then move its bottom centre to x, y, z."""
    tris = _read_stl(os.path.join(base_dir, part["file"]))
    return tris @ _yaw(part.get("yaw", 0)).T + np.array([part["x"], part["y"], part["z"]], np.float32)


def bake(parts, base_dir):
    """All placed parts as one plain triangle soup. No union, so parts that do not touch still export."""
    return np.concatenate([placed(p, base_dir) for p in parts])


def reseat(path):
    """Seat an STL in place (centre on x, y, base on z=0). Returns the bottom centre it had."""
    tris = _read_stl(path)
    lo, hi = tris.reshape(-1, 3).min(0), tris.reshape(-1, 3).max(0)
    off = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]], np.float32)
    _write_stl(path, tris - off)
    return off


def _cup(n=48, r=20.0, h=40.0, wall=3.0):
    """Open-top cup with a floor, as an (N, 3, 3) array of triangles in mm."""
    a = np.linspace(0, 2 * np.pi, n + 1)
    tris = []
    for i in range(n):
        a0, a1 = a[i], a[i + 1]
        for rad, flip in ((r, False), (r - wall, True)):
            p0 = (rad * np.cos(a0), rad * np.sin(a0))
            p1 = (rad * np.cos(a1), rad * np.sin(a1))
            q = [(*p0, 0 if rad == r else wall), (*p1, 0 if rad == r else wall), (*p1, h), (*p0, h)]
            t = [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]
            tris += [x[::-1] for x in t] if flip else t
        ro, ri = r - wall, r
        c0, s0, c1, s1 = np.cos(a0), np.sin(a0), np.cos(a1), np.sin(a1)
        tris += [[(ro * c0, ro * s0, h), (ri * c0, ri * s0, h), (ri * c1, ri * s1, h)],
                 [(ro * c0, ro * s0, h), (ri * c1, ri * s1, h), (ro * c1, ro * s1, h)]]
        tris.append([(0, 0, 0), (r * c1, r * s1, 0), (r * c0, r * s0, 0)])
        tris.append([(0, 0, wall), (ro * c0, ro * s0, wall), (ro * c1, ro * s1, wall)])
    return np.array(tris, dtype=np.float32)


def stl_bytes(tris):
    tris = np.asarray(tris, dtype=np.float32)
    normals = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    normals /= np.linalg.norm(normals, axis=1, keepdims=True) + 1e-12
    rec = np.zeros(len(tris), dtype=[("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")])
    rec["n"], rec["v"] = normals, tris
    return b"cad-training".ljust(80, b" ") + struct.pack("<I", len(tris)) + rec.tobytes()


def _write_stl(path, tris):
    with open(path, "wb") as f:
        f.write(stl_bytes(tris))


def _read_stl(path):
    """Binary STL only. That is all this stub, trimesh and parts.py write."""
    with open(path, "rb") as f:
        f.seek(80)
        (count,) = struct.unpack("<I", f.read(4))
        rec = np.frombuffer(f.read(count * 50), dtype=[("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")])
    return rec["v"].copy()


if __name__ == "__main__":
    import os
    import tempfile
    d = tempfile.mkdtemp()
    a, b = os.path.join(d, "a.stl"), os.path.join(d, "b.stl")
    _write_stl(a, _cup())
    apply_edit(a, "make it 20 percent taller", b)
    za, zb = _read_stl(a)[..., 2].max(), _read_stl(b)[..., 2].max()
    assert zb > za * 1.1, (za, zb)
    print("ok")
