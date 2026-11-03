"""Runnable checks for parts.py. Usage: uv run python test_parts.py"""
import os
import tempfile

import numpy as np
import trimesh

import parts
from edit import box, seat, union

D = tempfile.mkdtemp()


def save(mesh, name):
    path = os.path.join(D, name)
    mesh.export(path)
    return path


def load(name):
    return trimesh.load(os.path.join(D, name), force="mesh")


def refused(fn, *args):
    try:
        fn(*args)
    except ValueError as e:
        return str(e)
    return None


# split: two far cubes become 2 seated parts, volume kept, offsets point back at the originals
two = trimesh.util.concatenate([box((20, 20, 20), (-30, 0, 10)), box((10, 10, 10), (40, 0, 5))])
r = parts.split(save(two, "two.stl"), D)["parts"]
assert len(r) == 2, r
assert abs(sum(p["volume"] for p in r) - 9000) < 1, r
assert np.allclose(r[0]["offset"], [-30, 0, 0], atol=1e-4) and np.allclose(r[1]["offset"], [40, 0, 0], atol=1e-4), r
assert np.allclose(load(r[0]["file"]).bounds, [[-10, -10, 0], [10, 10, 20]], atol=1e-4)

# split drops a speck under 2% of the biggest piece
speck = trimesh.util.concatenate([box((20, 20, 20)), box((2, 2, 2), (40, 0, 0))])
assert len(parts.split(save(speck, "speck.stl"), D)["parts"]) == 1

# cut: a cube cut by a plane gives two closed halves whose volumes add up to the cube
r = parts.cut(save(box((40, 40, 40), (0, 0, 20)), "cube.stl"), D, (5, 0, 0), (1, 0, 0))["parts"]
assert len(r) == 2 and abs(sum(p["volume"] for p in r) - 64000) < 1, r
assert all(load(p["file"]).is_watertight for p in r)
assert {p["side"]: round(p["volume"]) for p in r} == {"+": 15 * 40 * 40, "-": 25 * 40 * 40}, r

# cut: a U shape cut across both arms gives 3 pieces (two arm tips above, the U below)
u = union(box((60, 20, 10), (0, 0, 5)), box((10, 20, 40), (-25, 0, 20)), box((10, 20, 40), (25, 0, 20)))
r = parts.cut(save(u, "u.stl"), D, (0, 0, 30), (0, 0, 1))["parts"]
assert sorted(p["side"] for p in r) == ["+", "+", "-"], r

# cut that misses the part is refused
assert refused(parts.cut, os.path.join(D, "cube.stl"), D, (0, 0, 100), (0, 0, 1)) == parts.MISS_MSG

# cut plane sign: SceneKit y up versus STL z up, on a box that is NOT seated, so the setModel offset matters.
# Box spans x 0..20, y -5..15, z 20..40. setModel puts it at scene (x - 10, z - 20, 5 - y).
lo, hi = np.array([0, -5, 20.0]), np.array([20, 15, 40.0])
assert np.allclose(parts.scene_to_stl([0, 0, 0], lo, hi), [10, 5, 20])     # scene origin = bottom centre
assert np.allclose(parts.scene_to_stl([0, 0, 5], lo, hi), [10, 0, 20])     # scene +z = STL -y (front)
assert np.allclose(parts.scene_dir_to_stl([0, 1, 0]), [0, 0, 1])           # scene up = STL up
assert np.allclose(parts.scene_dir_to_stl([0, 0, 1]), [0, -1, 0])
off = save(box((20, 20, 20), (10, 5, 30)), "off.stl")
# Camera in front (scene +z), eye at scene height 10, a level stroke at that height: a horizontal cut at STL z = 30.
n, p = parts.cut_plane([0, 10, 200], [-50, 10, 0], [50, 10, 0])
assert np.allclose(n, [0, -1, 0])  # left to right stroke: normal points down in the scene
ns, ps = parts.scene_dir_to_stl(n), parts.scene_to_stl(p, lo, hi)
assert np.allclose(ns, [0, 0, -1]) and np.isclose(ps[2], 30), (ns, ps)
r = parts.cut(off, D, ps, ns)["parts"]
plus = next(q for q in r if q["side"] == "+")
assert np.isclose(plus["offset"][2], 20) and np.isclose(plus["volume"], 4000), r  # + side is the bottom half
# Vertical stroke at screen x = 3, bottom to top: plane at STL x = 13, normal +x.
n, p = parts.cut_plane([3, 10, 200], [3, -40, 0], [3, 60, 0])
ns, ps = parts.scene_dir_to_stl(n), parts.scene_to_stl(p, lo, hi)
assert np.allclose(ns, [1, 0, 0]) and np.isclose(ps[0], 13), (ns, ps)
r = parts.cut(off, D, ps, ns)["parts"]
assert {q["side"]: round(q["volume"]) for q in r} == {"+": 7 * 400, "-": 13 * 400}, r
# Same stroke drawn top to bottom flips the normal. Same cut, sides swap.
n2, _ = parts.cut_plane([3, 10, 200], [3, 60, 0], [3, -40, 0])
assert np.allclose(n2, -n)

# join: two touching cubes become one part, two far cubes are refused
cube = os.path.basename(save(parts.seat(box((20, 20, 20))), "c20.stl"))
r = parts.join([{"file": cube, "x": 0, "y": 0, "z": 0}, {"file": cube, "x": 15, "y": 0, "z": 0, "yaw": 30}], D)["parts"]
assert len(r) == 1 and np.isclose(r[0]["offset"][2], 0), r
assert len(load(r[0]["file"]).split(only_watertight=False)) == 1
assert refused(parts.join, [{"file": cube, "x": 0}, {"file": cube, "x": 50}], D) == parts.JOIN_MSG
# stacked: one on top of the other, sunk 1 mm in
assert len(parts.join([{"file": cube}, {"file": cube, "z": 19}], D)["parts"]) == 1

# library shapes are seated, closed, one piece
for name in parts.LIBRARY:
    out = os.path.join(D, "lib", name + ".stl")
    parts.library(name, out)
    m = trimesh.load(out, force="mesh")
    assert m.is_watertight and abs(m.bounds[0][2]) < 1e-4 and len(m.split(only_watertight=False)) == 1, name

print("ok")

# rotate: a 10 x 20 x 40 bar tipped 90 degrees about x has its y and z sizes swapped, and still sits on z=0
bar = os.path.join(D, "bar.stl")
seat(box((10, 20, 40))).export(bar)
r = parts.run({"op": "rotate", "in": bar, "out_dir": D, "axis": "x", "degrees": 90})
m = trimesh.load(os.path.join(D, r["file"]))
assert np.allclose(m.extents, (10, 40, 20), atol=1e-3) and abs(m.bounds[0][2]) < 1e-3, m.extents
# turned 90 by yaw, a world x tip swaps the file's x and z instead
r = parts.run({"op": "rotate", "in": bar, "out_dir": D, "axis": "x", "degrees": 90, "yaw": 90})
m = trimesh.load(os.path.join(D, r["file"]))
assert np.allclose(m.extents, (40, 20, 10), atol=1e-3), m.extents
print("ok")

# an azimuth of 45 tips about the flat diagonal: a 10 x 20 x 40 bar ends up lying along that diagonal's perpendicular
r = parts.run({"op": "rotate", "in": bar, "out_dir": D, "axis": "90", "degrees": 90})
assert np.allclose(trimesh.load(os.path.join(D, r["file"])).extents, (40, 20, 10), atol=1e-3)
print("ok")

# resize: the 10 x 20 x 40 bar made 2x in y is 40 wide in y, and a turned part gets its yaw baked in
r = parts.run({"op": "resize", "in": bar, "out_dir": D, "sx": 1, "sy": 2, "sz": 1})
m = trimesh.load(os.path.join(D, r["file"]))
assert np.allclose(m.extents, (10, 40, 40), atol=1e-3) and r["yaw"] == 0 and np.allclose(r["shift"], 0, atol=1e-6), (m.extents, r)
r = parts.run({"op": "resize", "in": bar, "out_dir": D, "sx": 1, "sy": 2, "sz": 1, "yaw": 90})
assert np.allclose(trimesh.load(os.path.join(D, r["file"])).extents, (20, 20, 40), atol=1e-3) and r["yaw"] == 0, r
r = parts.run({"op": "resize", "in": bar, "out_dir": D, "sx": 2, "sy": 2, "sz": 2, "yaw": 30})
assert r["yaw"] == 30 and np.allclose(trimesh.load(os.path.join(D, r["file"])).extents, (20, 40, 80), atol=1e-3), r
assert "too big" in refused(parts.resize, bar, D, 1, 1, 7)
assert "too small" in refused(parts.resize, bar, D, 0.05, 1, 1)
assert refused(parts.resize, bar, D, 30, 1, 1)
print("ok")

# mirror: an L (long arm along +x, upright at -x) mirrored across x flips to the other side and stays closed
L = seat(union(box((40, 10, 10), (0, 0, 5)), box((10, 10, 30), (-15, 0, 15))))
src = save(L, "L.stl")
r = parts.run({"op": "mirror", "in": src, "out_dir": D, "axis": "x"})
m = load(r["file"])
want = L.copy()
want.apply_transform(trimesh.transformations.reflection_matrix([0, 0, 0], [1, 0, 0]))
assert m.is_watertight and m.volume > 0 and abs(m.volume - L.volume) < 1e-3, m.volume
hi_x = m.vertices[m.vertices[:, 2] > 20][:, 0]
assert hi_x.min() > 0, hi_x  # the upright moved from -x to +x
assert np.allclose(sorted(map(tuple, np.round(m.vertices, 3))), sorted(map(tuple, np.round(want.vertices, 3))))
# turned 90 by yaw, a world x mirror is a file y mirror: the L is symmetric in y, so nothing visible changes
r = parts.run({"op": "mirror", "in": src, "out_dir": D, "axis": 0, "yaw": 90})
assert np.allclose(load(r["file"]).bounds, L.bounds, atol=1e-3) and load(r["file"]).is_watertight
print("ok")

# layflat: the bar standing on its 10 x 20 end ends lying on a long face, and a second call does nothing
r = parts.run({"op": "layflat", "in": bar, "out_dir": D})
m = load(r["file"])
assert np.isclose(m.extents[2], 10, atol=1e-3), m.extents  # biggest face is 20 x 40, so it lies 10 high
assert np.isclose(m.extents.max(), 40, atol=1e-3) and abs(m.bounds[0][2]) < 1e-3
assert parts.run({"op": "layflat", "in": os.path.join(D, r["file"]), "out_dir": D})["file"] is None
r = parts.run({"op": "layflat", "in": bar, "out_dir": D, "yaw": 37})
assert np.isclose(load(r["file"]).extents[2], 20, atol=1e-3) or np.isclose(load(r["file"]).extents[2], 10, atol=1e-3)
print("ok")
