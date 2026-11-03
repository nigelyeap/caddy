"""Import an ELECTRONOOBS turntable IR scan (scan_001.txt) as a closed mesh in mm.

Usage:
  python turntable.py IN.txt OUT.stl [--legacy | --no-legacy] [--calib calib.json]
  python turntable.py --make-sample cylinder|sphere|mug OUT.txt [--legacy] [--noise]
  python turntable.py --selfcheck

File format: one `x,y,z` per line. x,y in cm, the surface point relative to the turntable
centre (dist = 8 - reading). z in mm. Commas, semicolons, tabs or spaces; extra columns,
headers, comments, blank and bad lines, NaN/inf are skipped.

Legacy firmware logs 1 degree per step instead of 1.8, so a revolution covers about 200
degrees. Legacy mode keeps radius = hypot(x, y) and re-derives the angle from the logged
step (round(logged_deg) = step index, same as point order when no lines were dropped) as
step * 360 / steps_per_rev. legacy=None auto-detects it from the angular coverage per layer.

Calibration JSON (all keys optional, defaults shown):
  z_units          "mm"   or "cm" (z is multiplied by 10)
  radius_scale     1.0    r_mm = hypot(x, y) * 10 * radius_scale + radius_offset_mm
  radius_offset_mm 0.0
  layer_height_mm  null   null = use z from the file, a number = re-space layers i * value
  min_radius_mm    1.0    readings outside [min, max] are dropped as sensor junk
  max_radius_mm    60.0   (sensor reads 2 to 15 cm and sits 8 cm from centre)
  smooth           5      median window across angle (also 3 across layers), 0 or 1 = off
  steps_per_rev    200    angle bins per layer
  legacy           null   null = auto-detect old firmware, false = never apply the fix, true = always
                          (set false for new firmware with fewer than about 100 points per turn)
  center_mm       80     sensor to turntable centre, kept for future raw-ADC input (unused)
Lookup when calib is None: <stem>.calib.json, then turntable_calib.json next to the file.

Mesh: one ring of steps_per_rev vertices per layer, flat fan caps at bottom and top.
The polar grid is built around the turntable centre, then the mesh is shifted so the mean
of the side vertices sits on x=y=0 and the base sits on z=0.
Limits: the object must be star-shaped around the turntable axis (no handles, no
undercuts seen from the sensor). Gaps are filled by linear interpolation.
"""
import json
import re
import struct
import sys
from pathlib import Path

import numpy as np
from scipy import ndimage
import trimesh

DEFAULTS = {"z_units": "mm", "radius_scale": 1.0, "radius_offset_mm": 0.0, "layer_height_mm": None,
            "min_radius_mm": 1.0, "max_radius_mm": 60.0, "smooth": 5, "steps_per_rev": 200,
            "legacy": None, "center_mm": 80.0}
LEGACY_STEP_DEG = 1.0  # what the buggy firmware logs per step


class TurntableError(ValueError):
    pass


def _fail(msg):
    raise TurntableError("turntable: " + msg)


def parse(text):
    """Text -> (N, 3) float array of raw x, y, z in file order."""
    rows = []
    for line in text.splitlines():
        parts = [p for p in re.split(r"[,;\s]+", line.strip()) if p]
        if len(parts) < 3:
            continue
        try:
            row = [float(p) for p in parts[:3]]
        except ValueError:
            continue
        if all(np.isfinite(row)):
            rows.append(row)
    return np.array(rows, float).reshape(-1, 3)


def _layer_ids(z, tol=0.1):
    """Group z values that differ by less than tol. Returns (labels, sorted layer z)."""
    u = np.unique(z)
    starts = np.concatenate([[0], np.nonzero(np.diff(u) > tol)[0] + 1])
    lab = np.searchsorted(u[starts], z, side="right") - 1
    return lab, np.array([np.median(z[lab == i]) for i in range(len(starts))])


def detect_legacy(points):
    """True when layers cover only about 200 degrees (1-degree-per-step firmware bug)."""
    pts = np.asarray(points, float).reshape(-1, 3)
    pts = pts[np.hypot(pts[:, 0], pts[:, 1]) > 1e-3]
    if len(pts) == 0:
        return False
    lab, _ = _layer_ids(pts[:, 2])
    cover = []
    for i in np.unique(lab):
        a = np.degrees(np.arctan2(pts[lab == i, 1], pts[lab == i, 0])) % 360
        if len(a) >= 20:  # 10-degree sectors holding at least 2 points
            cover.append(np.mean(np.bincount((a // 10).astype(int) % 36, minlength=36) >= 2))
    return bool(cover) and float(np.median(cover)) < 0.75


def _calib(path, calib):
    if calib is None:
        for c in (path.parent / (path.stem + ".calib.json"), path.parent / "turntable_calib.json"):
            if c.is_file():
                calib = c
                break
    if isinstance(calib, (str, Path)):
        calib = json.loads(Path(calib).read_text())
    cfg = dict(DEFAULTS)
    cfg.update({k: v for k, v in (calib or {}).items() if v is not None or k == "layer_height_mm"})
    return cfg


def _fill_circular(row):
    ok = np.isfinite(row)
    idx = np.arange(len(row))
    return np.interp(idx, idx[ok], row[ok], period=len(row))


def grid(pts, legacy, cfg):
    """Raw points -> (layer z mm, radius grid [layers, steps_per_rev] mm)."""
    n = int(cfg["steps_per_rev"])
    z = pts[:, 2] * (10.0 if cfg["z_units"] == "cm" else 1.0)
    r = np.hypot(pts[:, 0], pts[:, 1]) * 10 * cfg["radius_scale"] + cfg["radius_offset_mm"]
    deg = np.degrees(np.arctan2(pts[:, 1], pts[:, 0])) % 360
    step = np.round(deg / LEGACY_STEP_DEG) if legacy else np.round(deg / (360 / n))
    step = step.astype(int) % n
    lab, zs = _layer_ids(z)
    if len(zs) < 2:
        _fail(f"too few layers ({len(zs)} found, need at least 2)")
    ok = (r >= cfg["min_radius_mm"]) & (r <= cfg["max_radius_mm"])
    if ok.mean() < 0.1:
        _fail(f"out of range: {ok.mean():.0%} of readings inside {cfg['min_radius_mm']}-{cfg['max_radius_mm']} mm")
    flat = lab[ok] * n + step[ok]
    cnt = np.bincount(flat, minlength=len(zs) * n)
    tot = np.bincount(flat, r[ok], minlength=len(zs) * n)
    R = np.where(cnt > 0, tot / np.maximum(cnt, 1), np.nan).reshape(len(zs), n)
    good = np.isfinite(R).sum(1) >= max(6, n // 10)
    if good.sum() < 2:
        _fail(f"too few points: only {good.sum()} layers have enough readings to mesh")
    R[good] = [_fill_circular(row) for row in R[good]]
    gi = np.nonzero(good)[0]
    for j in range(n):  # fully or mostly missing layers come from their neighbours
        R[~good, j] = np.interp(np.nonzero(~good)[0], gi, R[gi, j])
    w = int(cfg["smooth"])
    if w > 1:
        pad = np.pad(R, ((1, 1), (w, w)), mode="wrap")
        pad[0], pad[-1] = pad[1], pad[-2]  # edge-pad across layers, wrap across angle
        R = ndimage.median_filter(pad, size=(3, w))[1:-1, w:-w]
    if cfg["layer_height_mm"]:
        zs = np.arange(len(zs)) * float(cfg["layer_height_mm"])
    return zs, np.clip(R, cfg["min_radius_mm"], cfg["max_radius_mm"])


def mesh_from_grid(zs, R):
    L, n = R.shape
    th = np.arange(n) * 2 * np.pi / n
    v = np.column_stack([(R * np.cos(th)).ravel(), (R * np.sin(th)).ravel(), np.repeat(zs, n)])
    v = np.vstack([v, [0, 0, zs[0]], [0, 0, zs[-1]]])
    i, j = np.meshgrid(np.arange(L - 1), np.arange(n), indexing="ij")
    a, b = i * n + j, i * n + (j + 1) % n
    c, d = b + n, a + n
    side = np.concatenate([np.stack([a, b, c], -1).reshape(-1, 3), np.stack([a, c, d], -1).reshape(-1, 3)])
    jj = np.arange(n)
    bot = np.column_stack([np.full(n, L * n), (jj + 1) % n, jj])
    top = np.column_stack([np.full(n, L * n + 1), (L - 1) * n + jj, (L - 1) * n + (jj + 1) % n])
    v[:, :2] -= v[:-2, :2].mean(0)
    v[:, 2] -= zs[0]
    return trimesh.Trimesh(v, np.concatenate([side, bot, top]), process=False)


def load(path, legacy=None, calib=None):
    path = Path(path)
    try:
        text = path.read_text(errors="replace")
    except OSError as e:
        _fail(f"no readable points ({e.strerror})")
    pts = parse(text)
    if len(pts) == 0:
        _fail("no readable points in file")
    cfg = _calib(path, calib)
    if legacy is None:
        legacy = cfg["legacy"]
    if legacy is None:
        legacy = detect_legacy(pts)
    zs, R = grid(pts, legacy, cfg)
    mesh = mesh_from_grid(zs, R)
    mesh.metadata["turntable"] = {"layers": len(zs), "points": len(pts), "legacy": bool(legacy)}
    return mesh


def write_stl(mesh, out):
    tri = mesh.vertices[mesh.faces].astype(np.float32)
    rec = np.zeros(len(tri), [("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")])
    rec["n"], rec["v"] = mesh.face_normals, tri
    with open(out, "wb") as f:
        f.write(b"turntable".ljust(80, b" ") + struct.pack("<I", len(tri)) + rec.tobytes())


# ---------- synthetic scans ----------

def profile(shape):
    """(z array in mm, radius function) for the sample shapes."""
    if shape == "cylinder":
        return np.arange(0, 40.01, 0.5), lambda z: np.full_like(z, 30.0)
    if shape == "sphere":  # r=25, clipped at +-22 so the end layers keep r of about 11.9
        return np.arange(-22, 22.01, 0.5), lambda z: np.sqrt(625 - z ** 2)
    if shape == "mug":  # straight wall, flared lip over the top 10 mm
        return np.arange(0, 50.01, 0.5), lambda z: 30 + 5 * np.clip((z - 40) / 10, 0, 1) ** 2
    raise ValueError(f"unknown shape {shape}")


def make_sample(shape, legacy=False, noise=False, seed=0):
    rng = np.random.default_rng(seed)
    zs, rf = profile(shape)
    k = np.arange(200)
    lines = ["# synthetic turntable scan " + shape, ""] if noise else []
    for z in zs:
        r = rf(np.full(200, z))
        keep = np.ones(200, bool)
        if noise:
            r = r + rng.normal(0, 0.3, 200)
            spikes = rng.random(200) < 0.02
            r[spikes] += rng.choice([-12, 12, 70], spikes.sum())
            keep = ~((k * 1.8 >= 100) & (k * 1.8 < 130))  # 30 degree blind spot
        a = np.radians(k * (LEGACY_STEP_DEG if legacy else 1.8))
        for x, y in zip(np.cos(a[keep]) * r[keep] / 10, np.sin(a[keep]) * r[keep] / 10):
            lines.append(f"{x:.3f},{y:.3f},{z - zs[0]:.1f}")
        if noise and z == zs[3]:
            lines += ["garbage,line", "nan,1,2", lines[-1]]
    return "\r\n".join(lines) + "\r\n"


def analytic_volume(shape):
    zs, rf = profile(shape)
    zf = np.linspace(zs[0], zs[-1], 20001)
    return float(np.trapezoid(np.pi * rf(zf) ** 2, zf))


# ---------- self-check ----------

def selfcheck():
    import tempfile
    sys.path.insert(0, str(Path(__file__).parent))
    from clean import to_manifold
    tmp = Path(tempfile.mkdtemp())

    def run(shape, legacy=False, noise=False):
        p = tmp / f"{shape}_{legacy}_{noise}.txt"
        p.write_text(make_sample(shape, legacy, noise))
        m = load(p)
        zs, rf = profile(shape)
        tol = 0.10 if noise else 0.05
        vol = analytic_volume(shape)
        name = p.name
        assert m.is_watertight and to_manifold(m) is not None, name
        assert m.volume > 0, f"{name}: inward winding"
        assert abs(m.volume - vol) / vol < tol, f"{name}: volume {m.volume:.0f} vs {vol:.0f}"
        assert abs(m.extents[2] - (zs[-1] - zs[0])) < 1, f"{name}: height {m.extents[2]}"
        rmax = np.hypot(m.vertices[:, 0], m.vertices[:, 1]).max()
        assert abs(rmax - rf(zs).max()) < 1 + 2 * noise, f"{name}: rmax {rmax}"
        assert m.metadata["turntable"]["legacy"] == legacy, f"{name}: legacy not detected"
        assert abs(m.bounds[0, 2]) < 1e-9 and np.abs(m.vertices[:, :2].mean(0)).max() < 1
        return m

    for shape in ("cylinder", "sphere", "mug"):
        base = run(shape)
        run(shape, noise=True)
        leg = run(shape, legacy=True)
        assert abs(leg.volume - base.volume) / base.volume < 0.01, f"{shape}: legacy volume"
        run(shape, legacy=True, noise=True)

    def bad(text, phrase, **kw):
        p = tmp / "bad.txt"
        p.write_text(text)
        try:
            load(p, **kw)
        except TurntableError as e:
            assert str(e).startswith("turntable:") and phrase in str(e), str(e)
            return
        raise AssertionError(f"no error for {phrase}")

    # 50 points per turn looks like old firmware to the detector, the calib switch must override it
    p = tmp / "sparse.txt"
    p.write_text("\n".join(l for i, l in enumerate(make_sample("mug").splitlines()) if i % 4 == 0))
    assert load(p).metadata["turntable"]["legacy"], "sparse file should fool the detector"
    m = load(p, calib={"legacy": False, "steps_per_rev": 50})
    assert not m.metadata["turntable"]["legacy"] and abs(m.extents[2] - 50) < 1

    bad("", "no readable points")
    bad("hello world\nfoo,bar,baz\n\x00\x01\n", "no readable points")
    bad("".join(f"3,{i * 0.01},0\n" for i in range(200)), "too few layers")
    bad("3,0,0\n3,0.1,0\n3,0,0.5\n0,3,0.5\n", "too few points")
    bad("".join(f"9,{i * 0.01},{z}\n" for z in (0, 0.5) for i in range(200)), "out of range")

    sample = Path(__file__).parent.parent / "mac/Sources/CADApp/Resources/turntable_sample.txt"
    m = load(sample)
    rmax = np.hypot(m.vertices[:, 0], m.vertices[:, 1]).max()
    assert m.is_watertight and abs(rmax - 30) < 1 and abs(m.extents[2] - 40) < 1, (rmax, m.extents)
    assert not m.metadata["turntable"]["legacy"]
    write_stl(m, tmp / "s.stl")
    back = trimesh.load(tmp / "s.stl")
    assert back.is_watertight and abs(back.volume - m.volume) < 1
    print("ok")


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(description="Turntable IR scan importer")
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--legacy", dest="legacy", action="store_true", default=None)
    ap.add_argument("--no-legacy", dest="legacy", action="store_false")
    ap.add_argument("--calib")
    ap.add_argument("--make-sample", metavar="SHAPE", choices=["cylinder", "sphere", "mug"])
    ap.add_argument("--noise", action="store_true")
    ap.add_argument("--selfcheck", action="store_true")
    a = ap.parse_args(argv)
    if a.selfcheck:
        return selfcheck()
    if a.make_sample:
        if len(a.paths) != 1:
            ap.error("--make-sample SHAPE OUT.txt")
        Path(a.paths[0]).write_text(make_sample(a.make_sample, bool(a.legacy), a.noise), newline="")
        return
    if len(a.paths) != 2:
        ap.error("need IN.txt OUT.stl")
    try:
        m = load(a.paths[0], a.legacy, a.calib)
    except TurntableError as e:
        print(e, file=sys.stderr)
        sys.exit(1)
    write_stl(m, a.paths[1])
    print(json.dumps({**m.metadata["turntable"], "extents_mm": [round(float(e), 2) for e in m.extents],
                      "watertight": bool(m.is_watertight)}))


if __name__ == "__main__":
    main(sys.argv[1:])
