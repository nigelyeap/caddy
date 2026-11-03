"""Measure orbit angle error against ground truth.

    uv run python eval_orbit.py                      # all synthetic scenarios
    uv run python eval_orbit.py --only handheld,pan_in_place
    uv run python eval_orbit.py --objectron DIR      # also real Objectron clips (video.MOV + geometry.pbdata per folder)
    uv run python eval_orbit.py --engine old.py      # compare another copy of guidance.py

Angles are signed degrees. The engine's sign is aligned to the truth once,
on the clean scenario, then kept for every row, so a flipped run shows up.
"""

import argparse
import importlib.util
import math
import pathlib
import struct
import sys
import time

import cv2
import numpy as np

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE))
import synth  # noqa: E402


def load_engine(path):
    spec = importlib.util.spec_from_file_location("engine_under_test", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run(engine, frames, use_pose=False):
    """frames: iterable of (img, t, truth). Returns per-frame (true_az, est_angle, result)."""
    s = engine.Session(sectors=12)
    rows, ms = [], []
    for img, t, truth in frames:
        t0 = time.perf_counter()
        r = s.update(img, t, pose=truth["pose"] if use_pose else None)
        ms.append((time.perf_counter() - t0) * 1000)
        est = r["orbit"]["angle_deg"] if "orbit" in r else s._angle
        rows.append((truth["azimuth_deg"], est, r))
    return rows, ms


def summarize(rows, sign):
    true = np.array([a for a, _, _ in rows])
    est = sign * np.array([e for _, e, _ in rows])
    err = est - (true - true[0])
    lost = sum(not r["tracking"]["ok"] for _, _, r in rows)
    warn = {}
    for _, _, r in rows:
        for w in r["warnings"]:
            warn[w] = warn.get(w, 0) + 1
    return {"true": true[-1] - true[0], "est": est[-1], "final": err[-1], "max": np.abs(err).max(),
            "cov": rows[-1][2]["coverage"]["pct"], "lost": lost, "n": len(rows), "warn": warn}


# ---------- Objectron (real iPhone video with ARKit poses) ----------

def _varint(b, i):
    r = s = 0
    while True:
        c = b[i]
        i += 1
        r |= (c & 0x7F) << s
        s += 7
        if c < 128:
            return r, i


def _fields(b):
    i = 0
    while i < len(b):
        k, i = _varint(b, i)
        f, w = k >> 3, k & 7
        if w == 0:
            v, i = _varint(b, i)
        elif w == 1:
            v, i = b[i:i + 8], i + 8
        elif w == 5:
            v, i = b[i:i + 4], i + 4
        elif w == 2:
            n, i = _varint(b, i)
            v, i = b[i:i + n], i + n
        else:
            raise ValueError(f"wire type {w}")
        yield f, v


def read_objectron(folder):
    """ARFrame list from geometry.pbdata: (timestamp, 4x4 camera to world, 3x3 K). Schema: a_r_capture_metadata.proto."""
    d = (pathlib.Path(folder) / "geometry.pbdata").read_bytes()
    out, i = [], 0
    while i < len(d):
        n = struct.unpack("<I", d[i:i + 4])[0]
        ts, T, K = None, None, None
        for f, v in _fields(d[i + 4:i + 4 + n]):
            if f == 1:
                ts = struct.unpack("<d", v)[0]
            elif f == 4:  # ARCamera
                for g, u in _fields(v):
                    if g == 3:
                        T = np.frombuffer(u, "<f4").reshape(4, 4).astype(float)
                    elif g == 7:
                        K = np.frombuffer(u, "<f4").reshape(3, 3).astype(float)
        out.append((ts, T, K))
        i += 4 + n
    return out


def fixation_point(poses):
    """Least squares point closest to every camera's optical axis. That is the object the student circles."""
    A, b = np.zeros((3, 3)), np.zeros(3)
    for T in poses:
        c, d = T[:3, 3], -T[:3, 2]
        P = np.eye(3) - np.outer(d, d)
        A += P
        b += P @ c
    return np.linalg.solve(A, b)


def objectron_frames(folder, fps):
    ar = read_objectron(folder)
    centre = fixation_point([T for _, T, _ in ar])
    cap = cv2.VideoCapture(str(pathlib.Path(folder) / "video.MOV"))
    vfps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    step = max(1, round(vfps / fps))
    az0, prev = None, None
    for k, (ts, T, K) in enumerate(ar):
        ok, img = cap.read()
        if not ok:
            break
        p = T[:3, 3] - centre
        az = math.degrees(math.atan2(p[0], p[2]))
        if prev is not None:  # unwrap
            az = prev + (az - prev + 180) % 360 - 180
        prev = az
        if k % step:
            continue
        yield img, float(ts), {"azimuth_deg": az, "pose": T, "focal_px": K[0, 0], "K": K}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", default=str(HERE / "guidance.py"))
    ap.add_argument("--only", default="")
    ap.add_argument("--objectron", nargs="*", default=[])
    ap.add_argument("--fps", type=float, default=1.0)
    ap.add_argument("--pose", action="store_true", help="feed the ground truth pose (LiDAR path)")
    args = ap.parse_args()
    eng = load_engine(args.engine)

    names = [n for n in synth.SCENARIOS if not args.only or n in args.only.split(",")]
    clean, _ = run(eng, synth.scenario("clean"))
    a = np.array([e for _, e, _ in clean])
    sign = 1.0 if a[-1] >= 0 else -1.0

    print(f"{'scenario':20s} {'true':>7s} {'est':>7s} {'final':>7s} {'max':>6s} {'cov%':>5s} {'lost':>5s} ms  warnings")
    all_ms = []
    jobs = [(n, lambda n=n: synth.scenario(n)) for n in names]
    jobs += [(f"objectron:{pathlib.Path(f).name}", lambda f=f: objectron_frames(f, args.fps)) for f in args.objectron]
    for name, fn in jobs:
        rows, ms = run(eng, fn(), use_pose=args.pose)
        all_ms += ms[1:]
        s = summarize(rows, sign)
        w = ", ".join(f"{k[:22]}:{v}" for k, v in s["warn"].items())
        print(f"{name:20s} {s['true']:7.1f} {s['est']:7.1f} {s['final']:7.1f} {s['max']:6.1f} {s['cov']:5.0f} "
              f"{s['lost']:2d}/{s['n']:<2d} {np.median(ms):3.0f}  {w}")
    print(f"latency per frame: median {np.median(all_ms):.0f} ms, p95 {np.percentile(all_ms, 95):.0f} ms")


if __name__ == "__main__":
    main()
