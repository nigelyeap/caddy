# Scan guidance engine

Checks a student's scanning technique from camera frames and tracks which sides of the object have been seen. Feed it about one frame per second.

## Setup and run

```
cd guidance
uv sync
uv run python test_guidance.py                 # about 25 s, includes synthetic scans and a 720p latency check
uv run python replay.py my_scan.mov --fps 1 --out log.json
uv run python calibrate.py my_scan.mov --notes notes.txt --laps 1
uv run python eval_orbit.py                    # angle error on every synthetic scenario
```

Dependencies are pinned in `pyproject.toml`: numpy 2.5.4 and opencv-python-headless 5.0.0.93. The environment lives in `guidance/.venv`.

## Files

- `guidance.py`: the engine.
- `test_guidance.py`: tests. Plain asserts, run as a script.
- `synth.py`: renders synthetic scans with known camera poses (textured, plain or shiny part, cluttered or plain room, hand shake, rolling shutter, auto exposure, noise, JPEG, off-centre framing, roll, up and down, panning, jumps, covered lens).
- `eval_orbit.py`: angle error against ground truth, for synthetic scenarios and for Objectron clips.
- `calibrate.py`: histograms and suggested thresholds from a real video.
- `QUALITY_NOTES.md`: measured results, what is still unverified, and the real-world test protocol.

## Contract

```python
from guidance import Session

s = Session(sectors=12)
result = s.update(frame_bgr, t, depth=None, pose=None)
s.reset()
```

`frame_bgr` is a uint8 BGR image (grey also works). `t` is the capture time in seconds. `update` returns a JSON-safe dict:

```
{"blur": {"score": float, "ok": bool},
 "light": {"mean": float, "clipped_pct": float, "ok": bool, "issue": "dark"|"bright"|"glare"|None},
 "tracking": {"match_ratio": float, "ok": bool},
 "speed": {"value": float, "ok": bool},          # degrees per second
 "coverage": {"sectors": [0..1 per sector], "pct": float,     # pct is 0..100
              "rings": None | {"low": [...], "mid": [...], "high": [...]}},
 "orbit": {"angle_deg": float, "measured": bool, "panning": bool,
           "elevation_deg": float|None, "distance_m": float|None,
           "focal_frac": float, "loops_closed": int},
 "warnings": [str],
 "t": float}
```

`coverage.rings` and `orbit.elevation_deg` are only filled when a pose is given. `orbit.distance_m` needs depth or a pose. Older keys are unchanged.

Warning texts live in `MESSAGES` in `guidance.py`, in priority order. `warnings[0]` is the most important one. A warning appears after 2 bad frames in a row and stays up until the problem has been gone for 3 seconds.

## How each check works

- Blur: variance of the Laplacian on a 640 px wide grey frame. A frame is blurry below `BLUR_FLOOR`, or below `BLUR_MIN` and also well under this session's recent sharp frames. That stops a sharp but plain part on a plain table being called blurry.
- Light: mean grey level for too dark. Too bright needs a high mean and many blown out pixels, so a white part on a white table is fine. Share of clipped pixels for glare.
- Tracking: ORB features (with a softer second pass on low-texture frames, and highlights masked out) matched to the last tracked frame. Tracking is ok when enough matches, and at least 60 percent of them, agree on one camera motion. When lost, the engine tries to relock on stored keyframes, so a turn made while lost is counted once the student is back on known ground.
- Orbit angle: a full relative camera rotation is fitted to the matches with a robust estimator. Starting guesses come from a grid of turns about the learned vertical plus OpenCV's essential matrix. Yaw is the part of the rotation about the vertical, which the engine learns from the motion itself. That makes it hold up when the camera looks down, is held crooked, or the part is off-centre.
- Panning: if the camera turned but nearby and far points moved together (no parallax), the student turned on the spot. That frame is not counted and the panning warning shows.
- Loop closure: keyframes every 20 degrees. When the student comes back to the start, the engine measures the real lap and corrects the angle. On the first lap it also corrects the focal length guess, unless tracking was lost on the way round.
- Coverage: the orbit is split into 1 degree bins. A bin counts once a sharp, well lit, tracked frame has swept past it.
- Cost: about 20 ms per frame at 640 px wide, 35 ms for a 720p frame on Apple silicon.

## LiDAR and real pose

If `pose` is given (4x4 camera to world, y up, camera looking along -z, the ARKit convention), the orbit angle is the camera's azimuth around the object centre. The centre comes from depth when given (median depth in the middle of the frame), else from where the camera's view lines cross. With a pose you also get panning from the pose, elevation and upper, middle and lower rings. With depth you also get too close and too far warnings. Depth may be metres (float) or millimetres (integer).

## Calibration

All thresholds are module constants at the top of `guidance.py`. Record a few good and bad scans, write a notes file with the seconds where things went wrong, and run `calibrate.py`. See `QUALITY_NOTES.md` for the protocol.
