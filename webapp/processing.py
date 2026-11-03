"""Scan cleanup and mesh editing.

Mesh cleanup and edits call the bench code through its own uv environment,
or through the Python named by CADDIY_PYTHON in the packaged app.
Video to mesh reconstruction does not exist yet, so a video input still gets
the sample cup.
"""
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


def _bench(script, *args):
    py = os.environ.get("CADDIY_PYTHON")
    cmd = [py] if py else ["uv", "run", "--project", str(BENCH), "python"]
    r = subprocess.run([*cmd, str(BENCH / script), *map(str, args)],
                       capture_output=True, text=True, timeout=300,
                       env={k: v for k, v in os.environ.items() if k != "VIRTUAL_ENV"})
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


def _write_stl(path, tris):
    tris = np.asarray(tris, dtype=np.float32)
    normals = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    normals /= np.linalg.norm(normals, axis=1, keepdims=True) + 1e-12
    rec = np.zeros(len(tris), dtype=[("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")])
    rec["n"], rec["v"] = normals, tris
    with open(path, "wb") as f:
        f.write(b"cad-training".ljust(80, b" "))
        f.write(struct.pack("<I", len(tris)))
        f.write(rec.tobytes())


def _read_stl(path):
    """Binary STL only. That is all this stub writes."""
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
