"""Harder synthetic scans: the failure modes real LiDAR and camera scans have.

Usage: uv run python synth_hard.py          # build, clean and check every hard case
Each case is a raw scan plus a check. run_bench.py picks these up through hard_cases().
"""
import sys
import time

import manifold3d as m3d
import numpy as np
import trimesh

from clean import _yaw_align, check, clean_scan, from_manifold
from run_bench import block, mug, roughen, toy

DIM_TOL = 0.02


def _gt(fn):
    gt = from_manifold(fn().refine_to_length(2.0))
    gt.apply_translation(-gt.bounds[0])
    return gt


def _noise(m, rng, sigma):
    m = m.copy()
    m.vertices += rng.normal(0, sigma, m.vertices.shape)
    return m


def _holes(m, rng, n, radius, centres=None):
    """Punch round holes, like shiny or dark patches the scanner could not see."""
    c = m.triangles_center
    keep = np.ones(len(m.faces), bool)
    for p in centres if centres is not None else c[rng.choice(len(c), n, replace=False)]:
        keep &= np.linalg.norm(c - p, axis=1) > radius
    m = m.copy()
    m.update_faces(keep)
    m.remove_unreferenced_vertices()
    return m


def _table(gt, rng, margin=0.5, cell=2.0):
    """A noisy flat sheet at z=0 reaching past the object on every side."""
    lo, hi = gt.bounds[0, :2], gt.bounds[1, :2]
    pad = margin * (hi - lo)
    t = trimesh.creation.box(extents=[*(hi - lo + 2 * pad), 1.0])
    t = trimesh.Trimesh(*trimesh.remesh.subdivide_to_size(t.vertices, t.faces, cell))
    t.update_faces(t.face_normals[:, 2] > 0.9)  # top sheet only, like a scan sees it
    t.remove_unreferenced_vertices()
    t.vertices[:, 2] = 0
    t.apply_translation([*((lo + hi) / 2), 0])
    return _noise(t, rng, 0.15)


def _rot(deg_xyz):
    return trimesh.transformations.euler_matrix(*np.radians(deg_xyz), "sxyz")


def _bottomless(gt, rng, cut=1.5):
    m = gt.copy()
    m.update_faces(m.triangles_center[:, 2] > cut)  # the table hides the underside
    m.remove_unreferenced_vertices()
    return _noise(m, rng, 0.0015 * gt.extents.max())


# ---------- the cases ----------

def case_big_holes(rng):
    """Shiny or dark patches: three holes a quarter of the object wide, one on top of the head."""
    gt = _gt(toy)
    top = gt.vertices[np.argmax(gt.vertices[:, 2])]
    r = 0.12 * gt.extents.max()
    cs = np.vstack([top, gt.triangles_center[rng.choice(len(gt.faces), 2, replace=False)]])
    raw = _noise(_holes(gt, rng, 0, r, cs), rng, 0.0015 * gt.extents.max())
    return raw, gt, {}


def case_bridged_handle(rng):
    """A 0.5 mm web fills the mug handle loop, like a scan that fused the handle to the body."""
    web = m3d.Manifold.cube((16, 0.5, 26)).translate((38, -0.25, 35))
    raw = roughen(from_manifold((mug() + web).refine_to_length(2.0)), seed=5, heavy=False)
    gt = _gt(mug)
    raw.apply_translation(-raw.bounds[0] + [0, 0, 0])
    return raw, gt, {"genus": True}


def case_table(fn, rot, metres):
    def make(rng):
        gt = _gt(fn)
        raw = trimesh.util.concatenate([_bottomless(gt, rng), _table(gt, rng)])
        raw.apply_transform(_rot(rot))
        if metres:
            raw.vertices *= 0.001
        return raw, gt, {"upright": True}
    return make


def case_drift(rng):
    """Tracking drift: one side of the toy scanned twice, 1.2 mm apart."""
    gt = _gt(toy)
    raw = _noise(gt, rng, 0.0015 * gt.extents.max())
    x = gt.triangles_center[:, 0]
    sheet = gt.copy()
    sheet.update_faces(x > np.percentile(x, 70))
    sheet.remove_unreferenced_vertices()
    sheet.vertices += sheet.vertex_normals * 1.2
    raw = trimesh.util.concatenate([raw, _noise(sheet, rng, 0.15)])
    return raw, gt, {}


def case_drift_fused(rng):
    """Worse drift: the whole toy scanned twice, 0.8 mm apart, stitched into one tangled surface."""
    gt = _gt(toy)
    a = _noise(gt, rng, 0.0015 * gt.extents.max())
    b = _noise(gt, rng, 0.0015 * gt.extents.max()).apply_translation([0.8, 0.5, 0.3])
    n = len(a.vertices)
    ia = rng.choice(n, 30, replace=False)  # stitch the two layers with slivers
    bridge = np.column_stack([ia, ia + n, (ia + 1) % n])
    raw = trimesh.Trimesh(np.vstack([a.vertices, b.vertices]),
                          np.vstack([a.faces, b.faces + n, bridge]), process=False)
    return raw, gt, {}


def case_hand(rng):
    """A hand holding the toy, fused to it. Known limit: nothing tells a hand from a part of the object."""
    c = m3d.Manifold.cylinder
    hand = m3d.Manifold.cube((22, 30, 40)).translate((26, -15, 15))
    for i in range(4):
        hand += c(40, 4.5, circular_segments=24).rotate((0, -90, 0)).translate((48, -12 + 8 * i, 50))
    raw = roughen(from_manifold((toy() + hand).refine_to_length(2.0)), seed=9, heavy=False)
    gt = _gt(toy)
    raw.apply_translation(-raw.bounds[0] + [gt.bounds[0][0] - raw.bounds[0][0], 0, 0])
    return raw, gt, {"known_limit": "a hand fused to the object is kept as part of it"}


def case_points(table):
    def make(rng):
        gt = _gt(toy)
        pts = trimesh.sample.sample_surface_even(gt, 60_000, seed=int(rng.integers(1e6)))[0]
        if table:
            pts = pts[pts[:, 2] > 1.5]
            t = _table(gt, rng).vertices
            pts = np.vstack([pts, t])
        pts = pts + rng.normal(0, 0.15, pts.shape)
        pts *= 0.001  # metres
        return trimesh.Trimesh(pts, np.zeros((0, 3), int), process=False), gt, {"no_size": False}
    return make


def case_tilted(fn, rot, yup=False):
    def make(rng):
        gt = _gt(fn)
        raw = _noise(gt, rng, 0.0015 * gt.extents.max())
        raw.apply_transform(_rot((-90, 0, 0) if yup else rot))
        return raw, gt, {"upright": True}
    return make


def case_two_parts(rng):
    """Two objects scanned together, plus dust. Both should survive."""
    a, b = _gt(block), _gt(toy)
    b.apply_translation([a.extents[0] + 25, 0, 0])
    gt = trimesh.util.concatenate([a, b])
    raw = roughen(gt, seed=3, heavy=False)
    return raw, gt, {"parts": 2}


def case_units(fn, factor):
    def make(rng):
        gt = _gt(fn)
        raw = _noise(gt, rng, 0.0015 * gt.extents.max())
        raw.vertices *= factor
        return raw, gt, {"no_size": True}
    return make


CASES = {
    "hard_big_holes": case_big_holes,
    "hard_bridged_handle": case_bridged_handle,
    "hard_table_toy": case_table(toy, (0, 0, 0), True),
    "hard_table_block_tilted": case_table(block, (20, -10, 35), False),
    "hard_drift": case_drift,
    "hard_drift_fused": case_drift_fused,
    "hard_hand": case_hand,
    "hard_points": case_points(False),
    "hard_points_table": case_points(True),
    "hard_tilted_block": case_tilted(block, (40, 0, 25)),
    "hard_yup_mug": case_tilted(mug, None, yup=True),
    "hard_two_parts": case_two_parts,
    "hard_units_cm": case_units(toy, 0.1),
}


def judge(res, gt, opts):
    """List of failed checks for a clean_scan result against ground truth."""
    out = res["mesh"]
    c = check(out)
    fails = []
    if not (c["watertight"] and c["manifold"] and c["volume_mm3"] > 0):
        fails.append("not printable")
    if c["components"] != opts.get("parts", 1):
        fails.append(f"{c['components']} parts")
    tol = 0.05 if opts.get("no_size") else DIM_TOL
    e, g = out.extents, gt.extents
    if opts.get("upright"):  # spin about z is free, height is not. Square both up the same way.
        e = out.copy().apply_transform(_yaw_align(out)).extents
        g = gt.copy().apply_transform(_yaw_align(gt)).extents
        e, g = np.r_[np.sort(e[:2]), e[2]], np.r_[np.sort(g[:2]), g[2]]
    err = float(np.max(np.abs(e - g) / g))
    if err > tol:
        fails.append(f"dims off {err:.1%}")
    if opts.get("genus") and out.euler_number != gt.euler_number:
        fails.append(f"handle hole lost (euler {out.euler_number} vs {gt.euler_number})")
    vol = float(abs(out.volume - gt.volume) / gt.volume) if c["watertight"] else float("nan")
    return fails, err, vol


def hard_cases():
    """(name, raw mesh, gt, longest_mm, opts) for every hard case."""
    for i, (name, make) in enumerate(CASES.items()):
        raw, gt, opts = make(np.random.default_rng(100 + i))
        yield name, raw, gt, (None if opts.get("no_size") else float(gt.extents.max())), opts


def run_hard(logf=None):
    """Clean and judge every hard case. Returns one dict per case for the report."""
    rows = []
    for name, raw, gt, longest, opts in hard_cases():
        t = time.time()
        try:
            res = clean_scan(raw, longest)
            fails, err, vol = judge(res, gt, opts)
        except Exception as e:
            res, fails, err, vol = {"quality": 0, "warnings": [], "log": []}, [f"{type(e).__name__}: {e}"], float("nan"), float("nan")
        known = opts.get("known_limit") if fails else None
        rows.append({"name": name, "verdict": "PASS" if not fails else "KNOWN" if known else "FAIL",
                     "seconds": round(time.time() - t, 1), "dim_err": err, "vol_err": vol, "quality": res["quality"],
                     "fails": fails, "known": known, "warnings": res["warnings"], "doc": CASES[name].__doc__})
        if logf:
            print(f"[{name}]\n  " + "\n  ".join(res["log"] + [f"warning: {w}" for w in res["warnings"]]), file=logf)
    return rows


def main():
    rows = run_hard()
    for r in rows:
        print(f"{r['name']:<24} {r['verdict']:<5} {r['seconds']:5.1f}s dim {r['dim_err']:6.2%} vol {r['vol_err']:6.2%} "
              f"q {r['quality']:3d} {'; '.join(r['fails'])}")
        if r["known"]:
            print(f"{'':26}known limit: {r['known']}")
        for w in r["warnings"]:
            print(f"{'':26}- {w}")
    ok = sum(r["verdict"] != "FAIL" for r in rows)
    print(f"{ok}/{len(rows)} hard cases pass or fail only on a documented known limit")
    return 0 if ok == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
