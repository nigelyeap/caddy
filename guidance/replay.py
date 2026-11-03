"""Run the guidance engine on a video file and write a JSON log.

Usage: uv run python replay.py my_scan.mov --fps 1 --out log.json
"""

import argparse
import collections
import json

import cv2

import guidance


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--fps", type=float, default=1.0, help="frames per second fed to the engine")
    ap.add_argument("--out", default="replay_log.json")
    ap.add_argument("--sectors", type=int, default=12)
    args = ap.parse_args()

    cap = cv2.VideoCapture(args.video)
    if not cap.isOpened():
        raise SystemExit(f"cannot open {args.video}")
    vfps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    step = max(1, round(vfps / args.fps))

    session = guidance.Session(args.sectors)
    log, counts, i = [], collections.Counter(), 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if i % step == 0:
            r = session.update(frame, i / vfps)
            r["orbit_deg"] = r["orbit"]["angle_deg"]  # kept for older log readers
            log.append(r)
            counts.update(r["warnings"])
        i += 1
    cap.release()

    with open(args.out, "w") as f:
        json.dump(log, f, indent=1)
    if not log:
        raise SystemExit("no frames read")
    last = log[-1]
    print(f"{len(log)} frames, {last['t']:.1f} s, orbit {last['orbit_deg']:.0f} deg, coverage {last['coverage']['pct']:.0f} percent")
    print("sectors:", " ".join(f"{v:.1f}" for v in last["coverage"]["sectors"]))
    for msg, n in counts.most_common():
        print(f"  {n:3d} frames: {msg}")
    print("log written to", args.out)


if __name__ == "__main__":
    main()
