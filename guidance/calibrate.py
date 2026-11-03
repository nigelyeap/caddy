"""Suggest guidance thresholds from a real video.

    uv run python calibrate.py scan.mp4
    uv run python calibrate.py scan.mp4 --notes notes.txt --laps 1

The video is sampled at --fps (default 1, the same rate the web app uses)
and every frame goes through guidance.Session. You get text histograms of
blur score, brightness, clipped pixels and match ratio, plus suggested
values for the knobs at the top of guidance.py.

notes.txt is optional. One line per stretch of video, seconds then a label:

    0-20 good
    21-26 blurry
    27-35 dark
    40-44 bright
    50-55 lost

Labels: good, blurry, dark, bright, lost. With notes, each threshold is
put halfway between the good frames and the bad ones. Without notes you
only get the spread of values and a cautious suggestion.

--laps N says the student walked exactly N full laps. The script then
compares the measured angle with N x 360 and suggests FOCAL_FRAC.
"""

import argparse
import pathlib
import sys

import cv2
import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import guidance as g  # noqa: E402

LABELS = ("good", "blurry", "dark", "bright", "lost")


def read_notes(path):
    spans = []
    for line in pathlib.Path(path).read_text().splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        rng, label = line.split()
        a, b = (float(x) for x in rng.split("-"))
        if label not in LABELS:
            raise SystemExit(f"unknown label {label!r}, use one of {', '.join(LABELS)}")
        spans.append((a, b, label))
    return spans


def label_at(spans, t):
    for a, b, lab in spans:
        if a <= t <= b:
            return lab
    return None


def sample(video, fps):
    cap = cv2.VideoCapture(str(video))
    if not cap.isOpened():
        raise SystemExit(f"cannot open {video}")
    vfps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    step = max(1, round(vfps / fps))
    k = 0
    while True:
        ok, img = cap.read()
        if not ok:
            return
        if k % step == 0:
            yield k / vfps, img
        k += 1


def histogram(name, values, bins=12, width=40, mark=None):
    v = np.asarray(values, float)
    print(f"\n{name}: n={len(v)} min={v.min():.3g} p10={np.percentile(v, 10):.3g} "
          f"median={np.median(v):.3g} p90={np.percentile(v, 90):.3g} max={v.max():.3g}")
    lo, hi = v.min(), v.max()
    if hi <= lo:
        hi = lo + 1
    counts, edges = np.histogram(v, bins=bins, range=(lo, hi))
    top = max(counts.max(), 1)
    for c, a, b in zip(counts, edges[:-1], edges[1:]):
        flag = " <- current threshold" if mark is not None and a <= mark < b else ""
        print(f"  {a:9.3g} .. {b:9.3g} | {'#' * round(c / top * width):<{width}} {c}{flag}")


def split(good, bad, below=True):
    """Threshold halfway between good and bad. below=True when bad values are the low ones."""
    if not good or not bad:
        return None
    if below:
        return (np.percentile(good, 10) + np.percentile(bad, 90)) / 2
    return (np.percentile(good, 90) + np.percentile(bad, 10)) / 2


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video")
    ap.add_argument("--notes")
    ap.add_argument("--fps", type=float, default=1.0)
    ap.add_argument("--laps", type=float, help="full laps the student really walked")
    args = ap.parse_args()

    spans = read_notes(args.notes) if args.notes else []
    s = g.Session(sectors=12)
    rows = []
    for t, img in sample(args.video, args.fps):
        r = s.update(img, t)
        rows.append((t, label_at(spans, t), r))
    if not rows:
        raise SystemExit("no frames read")

    col = {k: [] for k in ("blur", "mean", "clip", "ratio")}
    by = {lab: {k: [] for k in col} for lab in LABELS}
    for t, lab, r in rows:
        vals = {"blur": r["blur"]["score"], "mean": r["light"]["mean"],
                "clip": r["light"]["clipped_pct"], "ratio": r["tracking"]["match_ratio"]}
        for k, v in vals.items():
            col[k].append(v)
            if lab:
                by[lab][k].append(v)

    print(f"{args.video}: {len(rows)} frames at {args.fps:g} per second")
    histogram("blur score (Laplacian variance)", col["blur"], mark=g.BLUR_MIN)
    histogram("brightness (mean grey 0..255)", col["mean"])
    histogram("clipped pixels %", col["clip"], mark=g.BRIGHT_CLIP_PCT)
    histogram("match ratio", col["ratio"][1:] or [0], mark=g.MATCH_RATIO_MIN)

    warn = {}
    for _, _, r in rows:
        for w in r["warnings"]:
            warn[w] = warn.get(w, 0) + 1
    print("\nwarnings shown:")
    for w, n in sorted(warn.items(), key=lambda x: -x[1]):
        print(f"  {n:4d}  {w}")

    print("\nsuggested thresholds (current value in brackets):")
    good = by["good"]
    tips = [
        ("BLUR_MIN", g.BLUR_MIN, split(good["blur"], by["blurry"]["blur"])),
        ("DARK_MEAN", g.DARK_MEAN, split(good["mean"], by["dark"]["mean"])),
        ("BRIGHT_CLIP_PCT", g.BRIGHT_CLIP_PCT, split(good["clip"], by["bright"]["clip"], below=False)),
        ("MATCH_RATIO_MIN", g.MATCH_RATIO_MIN, split(good["ratio"], by["lost"]["ratio"])),
    ]
    if not spans:
        # No labels. Only say how many sharp-looking frames each knob would flag.
        b = np.array(col["blur"])
        print(f"  no notes given. BLUR_MIN={g.BLUR_MIN:g} would flag {np.mean(b < g.BLUR_MIN) * 100:.0f}% of frames.")
        print(f"  If the whole video was sharp, try BLUR_MIN around {np.percentile(b, 5) * 0.8:.0f}.")
    for name, cur, new in tips:
        if new is not None:
            print(f"  {name} = {new:.3g}   ({cur:g})")
        elif spans:
            print(f"  {name}: needs both good and bad frames in the notes")

    angle = rows[-1][2]["orbit"]["angle_deg"]
    print(f"\nmeasured orbit angle: {angle:.0f} deg, loops closed: {rows[-1][2]['orbit']['loops_closed']}")
    if args.laps:
        true = 360 * args.laps
        # A focal length guess that is too short makes every angle too big, and the other way round.
        f_now = rows[-1][2]["orbit"]["focal_frac"]
        if abs(angle) > 30:
            print(f"  walked {true:.0f} deg. Suggested FOCAL_FRAC = {f_now * abs(angle) / true:.2f}   ({g.FOCAL_FRAC:g})")


if __name__ == "__main__":
    main()
