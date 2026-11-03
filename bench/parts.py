"""Many parts in one build: split, cut, join and library shapes. JSON in, JSON out.

Usage (one op per process):
  uv run python parts.py '{"op": "split", "in": "scan.stl", "out_dir": "data"}'
  uv run python parts.py '{"op": "cut", "in": "p1.stl", "out_dir": "data", "point": [0,0,20], "normal": [0,0,1]}'
  uv run python parts.py '{"op": "join", "out_dir": "data", "parts": [{"file": "a.stl", "x": 0, "y": 0, "z": 0, "yaw": 0}, ...]}'
  uv run python parts.py '{"op": "library", "name": "star", "out": "data/library/star.stl"}'
Worker mode: uv run python parts.py --serve reads one JSON op per stdin line and prints one JSON line back.

Every output piece is written seated (centred on x, y, base on z=0), as edit.seat() does.
"offset" is where that piece's bottom centre was in the input frame, so the caller can place it unmoved.
On failure it prints {"error": "<kid-friendly reason>"} and exits 1.
"""
import json
import os
import sys
import time

import manifold3d as m3d
import numpy as np
import trimesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from edit import _m, _t, seat, box, sphere, cylinder, cone, pyramid, torus, shape  # noqa: E402

MIN_PIECE = 0.02  # drop pieces under 2% of the biggest piece's volume (specks, slivers)
JOIN_MSG = "Push them together so they touch, then join."
MISS_MSG = "That line did not go through the part. Draw it across the part."

LIBRARY = {
    "cube": lambda: box((30, 30, 30)), "ball": lambda: sphere(30), "cylinder": lambda: cylinder(30, 30),
    "cone": lambda: cone(30, 30), "pyramid": lambda: pyramid(30, 25), "donut": lambda: torus(36, 12),
    "star": lambda: shape("star", 30, 5), "heart": lambda: shape("heart", 30, 5),
    "base plate": lambda: box((60, 60, 3)),
}


def pieces(man):
    """Connected solids of a manifold, biggest first, specks dropped."""
    parts = sorted(man.decompose(), key=lambda p: -p.volume())
    if not parts:
        return []
    big = parts[0].volume()
    return [p for p in parts if p.volume() >= MIN_PIECE * big]


def _write(mans, out_dir):
    """Seat each manifold, save as p<time_ns>.stl, return [{file, offset, volume}]."""
    os.makedirs(out_dir, exist_ok=True)
    out = []
    for man in mans:
        mesh = _t(man)
        lo, hi = mesh.bounds
        name = f"p{time.time_ns()}.stl"
        seat(mesh).export(os.path.join(out_dir, name))
        out.append({"file": name, "offset": [float((lo[0] + hi[0]) / 2), float((lo[1] + hi[1]) / 2), float(lo[2])],
                    "volume": round(float(man.volume()), 3)})
    return out


def _load(path):
    return _m(trimesh.load(path, force="mesh", process=True))


# ---------- cut plane from a drawn line ----------

def cut_plane(eye, a, b):
    """Plane through the camera eye and two unprojected stroke points. Returns (unit normal, point).
    The normal sign follows the stroke direction, so callers must not read meaning into which side is first."""
    eye, a, b = (np.asarray(v, float) for v in (eye, a, b))
    n = np.cross(a - eye, b - eye)
    if np.linalg.norm(n) < 1e-9:
        raise ValueError("Draw a longer line.")
    return n / np.linalg.norm(n), eye


def scene_to_stl(p, lo, hi):
    """SceneKit point (y up) back into the STL frame (z up) of a mesh with bounds lo, hi.
    Mirrors ViewerScene.setModel: stl (x, y, z) -> scene (x - cx, z - lo.z, cy - y)."""
    c = (np.asarray(lo, float) + np.asarray(hi, float)) / 2
    return np.array([p[0] + c[0], c[1] - p[2], p[1] + lo[2]])


def scene_dir_to_stl(n):
    """SceneKit direction (y up) into STL (z up). Inverse of (x, y, z) -> (x, z, -y)."""
    return np.array([n[0], -n[2], n[1]], float)


# ---------- ops ----------

def split(src, out_dir):
    return {"parts": _write(pieces(_load(src)), out_dir)}


def cut(src, out_dir, point, normal):
    """Cut by a plane (in the file's own z-up frame). Each half then splits into its connected pieces."""
    n = np.asarray(normal, float)
    n /= np.linalg.norm(n)
    man = _load(src)
    pos, neg = man.split_by_plane(tuple(n), float(n @ np.asarray(point, float)))
    if pos.is_empty() or neg.is_empty() or min(pos.volume(), neg.volume()) < MIN_PIECE * man.volume():
        raise ValueError(MISS_MSG)
    out = []
    for side, half in (("+", pos), ("-", neg)):
        for p in _write(pieces(half), out_dir):
            out.append({**p, "side": side})
    return {"parts": out}


def join(parts, out_dir, base_dir=None):
    """Union placed parts. Each part: {file, x, y, z, yaw}. file is seated, so (x, y, z) is its bottom centre."""
    if len(parts) < 2:
        raise ValueError("Pick two or more parts to join.")
    placed = []
    for p in parts:
        man = _load(os.path.join(base_dir or out_dir, p["file"]))
        man = man.rotate((0, 0, float(p.get("yaw", 0)))).translate((float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0))))
        placed.append(man)
    out = m3d.Manifold.batch_boolean(placed, m3d.OpType.Add)
    if len(out.decompose()) != 1:
        # Near-miss: grow each part about 1 mm about its own centre and retry, so a 2 mm gap still joins.
        grown = []
        for m in placed:
            lo, hi = m.bounding_box()[:3], m.bounding_box()[3:]
            c = [(a + b) / 2 for a, b in zip(lo, hi)]
            s = 1 + 2.0 / max(b - a for a, b in zip(lo, hi))
            grown.append(m.translate([-v for v in c]).scale([s] * 3).translate(c))
        out = m3d.Manifold.batch_boolean(grown, m3d.OpType.Add)
        if len(out.decompose()) != 1:
            raise ValueError(JOIN_MSG)
    return {"parts": _write([out], out_dir)}


def library(name, out):
    if name not in LIBRARY:
        raise ValueError(f"no library shape called {name}, try one of {sorted(LIBRARY)}")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    seat(LIBRARY[name]()).export(out)
    return {"file": out}


def rotate(src, out_dir, axis, degrees, yaw=0.0):
    """Tip a part through its centre about a flat (horizontal) world axis. axis is "x", "y", or an
    azimuth in degrees (0 = x axis, 90 = y axis), so the app can tip about what the camera sees as
    left to right. The part sits turned by yaw, so turn the file back by yaw, tip, and turn it again."""
    a = np.radians(_az(axis))
    return _turn(src, out_dir, _R(np.radians(float(degrees)), [np.cos(a), np.sin(a), 0]), yaw)


_R = trimesh.transformations.rotation_matrix
MAX_XY, MAX_Z, MIN_SIZE = 250.0, 250.0, 1.0


def _az(axis):
    return {"x": 0.0, "y": 90.0}[axis] if axis in ("x", "y") else float(axis)


def _rz(yaw):
    return _R(np.radians(float(yaw)), [0, 0, 1])


def _save(mesh, out_dir):
    name = f"p{time.time_ns()}.stl"
    os.makedirs(out_dir, exist_ok=True)
    seat(mesh).export(os.path.join(out_dir, name))
    return name


def _turn(src, out_dir, T, yaw):
    """Apply world transform T (about the part centre) to a part placed turned by yaw: the file gets
    Rz(-yaw) T Rz(yaw), then is seated. Reflections flip the winding, trimesh turns the faces back."""
    mesh = trimesh.load(src, force="mesh")
    lo, hi = mesh.bounds
    mesh.apply_translation(-(lo + hi) / 2)
    mesh.apply_transform(_rz(-yaw) @ T @ _rz(yaw))
    mesh.fix_normals()
    return {"file": _save(mesh, out_dir)}


def resize(src, out_dir, sx, sy, sz, yaw=0.0):
    """Scale by world-axis factors about the placed part's bottom centre. A non-uniform scale would shear
    a turned part, so the yaw is baked into the new file and the part comes back with yaw 0.
    "shift" is how far to move the part's x, y so the bottom centre stays put."""
    s = np.array([sx, sy, sz], float)
    if not all(0.05 <= v <= 20 for v in s):
        raise ValueError("Pick a size between 0.05 and 20 times.")
    mesh = trimesh.load(src, force="mesh")
    mesh.apply_transform(_rz(yaw))  # placed shape, relative to the part's x, y, z
    lo, hi = mesh.bounds
    c = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]])
    size = (hi - lo) * s
    if max(size[:2]) > MAX_XY or size[2] > MAX_Z:
        raise ValueError(f"That is too big for the printer. Keep it under {MAX_XY:.0f} mm.")
    if min(size) < MIN_SIZE:
        raise ValueError("That is too small to print. Keep it at least 1 mm.")
    if np.allclose(s, s[0]):  # uniform: keep the yaw, scale the file, move so the bottom centre stays at c
        mesh = trimesh.load(src, force="mesh")
        mesh.apply_scale(s[0])
        return {"file": _save(mesh, out_dir), "yaw": float(yaw), "shift": ((1 - s[0]) * c[:2]).tolist()}
    mesh.apply_translation(-c)
    mesh.apply_scale(s)
    return {"file": _save(mesh, out_dir), "yaw": 0.0, "shift": c[:2].tolist()}


def mirror(src, out_dir, axis, yaw=0.0):
    """Mirror across the vertical plane through the part centre whose normal is the flat azimuth axis."""
    a = np.radians(_az(axis))
    return _turn(src, out_dir, trimesh.transformations.reflection_matrix([0, 0, 0], [np.cos(a), np.sin(a), 0]), yaw)


def _inside(p, tri):
    """Is p (projected onto tri's plane) inside triangle tri? Barycentric test with a small tolerance."""
    a, b, c = tri
    v0, v1, v2 = b - a, c - a, p - a
    d00, d01, d11, d20, d21 = v0 @ v0, v0 @ v1, v1 @ v1, v2 @ v0, v2 @ v1
    den = d00 * d11 - d01 * d01
    if abs(den) < 1e-12:
        return False
    v = (d11 * d20 - d01 * d21) / den
    w = (d00 * d21 - d01 * d20) / den
    return v >= -1e-6 and w >= -1e-6 and v + w <= 1 + 1e-6


def layflat(src, out_dir, yaw=0.0):
    """Lie the part on its biggest stable flat face. Returns {"file": None} when it already lies on it."""
    mesh = trimesh.load(src, force="mesh")
    mesh.apply_transform(_rz(yaw))
    hull = mesh.convex_hull
    com = mesh.center_mass
    # Flat faces of the hull: merged coplanar facets plus lone triangles.
    in_facet = set(np.concatenate(hull.facets)) if len(hull.facets) else set()
    faces = [(float(a), n, f) for f, a, n in zip(hull.facets, hull.facets_area, hull.facets_normal)]
    faces += [(float(hull.area_faces[i]), hull.face_normals[i], [i]) for i in range(len(hull.faces)) if i not in in_facet]
    stable = []
    for area, n, fs in faces:
        tris = hull.triangles[fs]
        p = com - ((com - tris[0][0]) @ n) * n  # centre of mass dropped onto the face plane
        if any(_inside(p, t) for t in tris):
            stable.append((area, np.asarray(n, float)))
    if not stable:
        raise ValueError("That part has no flat side to lie on.")
    top = max(a for a, _ in stable)
    down = np.array([0, 0, -1.0])
    # Among faces within 5 percent of the biggest, take the one that needs the least turning.
    area, n = max((s for s in stable if s[0] >= 0.95 * top), key=lambda s: s[1] @ down)
    if n @ down >= np.cos(np.radians(0.5)):
        return {"file": None}
    T = np.eye(4)
    T[:3, :3] = trimesh.geometry.align_vectors(n, down)[:3, :3]
    return _turn(src, out_dir, T, yaw)


def run(req):
    op = req.get("op")
    if op == "split":
        return split(req["in"], req["out_dir"])
    if op == "cut":
        if "eye" in req:  # plane from the drawn line, given in the file's z-up frame
            normal, point = cut_plane(req["eye"], req["a"], req["b"])
        else:
            normal, point = req["normal"], req["point"]
        return cut(req["in"], req["out_dir"], point, normal)
    if op == "rotate":
        return rotate(req["in"], req["out_dir"], req.get("axis", "x"), req["degrees"], req.get("yaw", 0))
    if op == "resize":
        return resize(req["in"], req["out_dir"], req["sx"], req["sy"], req["sz"], req.get("yaw", 0))
    if op == "mirror":
        return mirror(req["in"], req["out_dir"], req.get("axis", "x"), req.get("yaw", 0))
    if op == "layflat":
        return layflat(req["in"], req["out_dir"], req.get("yaw", 0))
    if op == "join":
        return join(req["parts"], req["out_dir"], req.get("base_dir"))
    if op == "library":
        return library(req["name"], req["out"])
    raise ValueError(f"unknown op {op!r}")


def _one(line):
    try:
        return json.dumps(run(json.loads(line))), 0
    except (ValueError, KeyError) as e:
        return json.dumps({"error": str(e)}), 1


if __name__ == "__main__":
    if sys.argv[1:] == ["--serve"]:
        for line in sys.stdin:
            if line.strip():
                print(_one(line)[0], flush=True)
        sys.exit(0)
    text, code = _one(sys.argv[1])
    print(text)
    sys.exit(code)
