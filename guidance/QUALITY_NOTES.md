# Guidance quality notes

Measured on 2026-10-30. Reproduce with `uv run python eval_orbit.py` (synthetic) and `uv run python eval_orbit.py --objectron DIR ... --fps 3` (real clips). Add `--pose` for the LiDAR path. "Before" is the engine as it was at the start of this work.

## Test bed

`synth.py` renders a box-shaped part with a boss on a table in a room, with known camera poses. 15 scenarios: clean, handheld (shake, speed jitter, rolling shutter, auto exposure, noise, JPEG 75), off_centre (part 12 degrees left and 8 degrees down in the frame), looking_down (35 degrees), crooked_roll (15 degrees), up_and_down (plus or minus 20 degrees of height), focal_1.1 and focal_0.6 (lens the engine does not expect), fast_steps (jumps of 35, 45 and 70 degrees), pan_in_place (student stops and turns the phone), lost_turning (lens covered for 3 frames while walking), plain_object, shiny_object, plain_everything (plain part in a plain room), two_laps_handheld. Frames are 640x480, one per 10 degrees of walking.

Real footage: four public Objectron clips (Google, C-UDA-1.0 licence, no sign-up). iPhone video at 1440x1920 with ARKit poses, so the true angle is known. Downloaded to the session scratchpad, not to the repo:

| clip | video | poses |
|---|---|---|
| cup/batch-16/47 | 19.9 MB | 2.0 MB |
| bottle/batch-3/14 | 9.2 MB | 1.2 MB |
| shoe/batch-9/25 | 11.5 MB | 1.1 MB |
| camera/batch-3/11 | 13.6 MB | 2.0 MB |

URL pattern: `https://storage.googleapis.com/objectron/videos/<class>/<batch>/<id>/video.MOV` and `.../geometry.pbdata`. The pose file is parsed with a small protobuf reader in `eval_orbit.py`, so no extra package is needed.

## Orbit angle error, camera only

Error is the estimated angle minus the true angle at the end of the scan. Max is the worst point during the scan. Degrees.

| scenario | before final | before max | after final | after max |
|---|---|---|---|---|
| clean | -23 | 84 | -0.4 | 6 |
| handheld | -430 | 447 | 4 | 22 |
| off_centre | -504 | 585 | -2.5 | 9 |
| looking_down | -455 | 475 | -1.4 | 8 |
| crooked_roll | -181 | 262 | -1.8 | 6 |
| up_and_down | -479 | 562 | 27 | 45 |
| focal_1.1 | -197 | 298 | 14 | 79 |
| focal_0.6 | -298 | 305 | 5 | 103 |
| fast_steps | -207 | 240 | -0.2 | 103 |
| pan_in_place | -293 | 295 | 0.4 | 13 |
| lost_turning | -166 | 276 | -1.9 | 30 |
| plain_object | -463 | 463 | 1.5 | 4 |
| shiny_object | -317 | 372 | 3.8 | 58 |
| plain_everything (half lap) | -63 | 73 | -49 | 100 |
| two_laps_handheld | -532 | 532 | -2.7 | 22 |

Objectron at 3 frames per second (camera only):

| clip | true | before error | after error |
|---|---|---|---|
| cup | -328 | 295 | 98 |
| bottle | 36 | -64 | -7.5 |
| shoe | 111 | 71 | -75 |
| camera | 109 | -74 | -2.9 |

Large max values on focal_1.1, focal_0.6 and fast_steps are the moment just before the lap closes. The loop closure then fixes the angle.

## With pose (LiDAR path)

Ground-truth ARKit poses fed in, no depth. Final error: clean 0.0, handheld -8, looking_down -2.8, up_and_down -1.3, focal_0.6 -2.4, fast_steps 0.0, pan_in_place -6.9 (panning warning shown), plain_everything 0.0, two_laps -8. Objectron: cup 22, bottle 10, shoe -5.7, camera -10. The weak case is off_centre at -41: without depth the object centre comes from where the view lines cross, and off-centre framing moves that point. With depth the centre comes from the depth map instead. Tests cover the pose orbit, rings and elevation, panning from pose, and too close and too far from depth (metres and millimetres).

## Latency

Apple silicon, measured inside `test_guidance.py`: 1280x720 median 35 ms, 720x1280 median 38 ms, max under 50 ms. At 640 px wide the median is about 20 ms. During the eval runs other jobs shared the CPU and p95 reached about 90 ms on 1440x1920 frames. That is still well under 200 ms.

## What changed and why

- Motion model. The old engine assumed a level circle with the part dead centre. Any tilt broke it. The new one fits the full camera rotation with a robust estimator and keeps only the turn about the vertical. The vertical is learned from the motion. This fixed off-centre, roll, looking down and the plain part.
- Focal length is now 0.8 times the long side of the image. Objectron iPhones measured 0.77 to 0.84. Two-view focal estimation was tried and is unstable for this motion, so the engine corrects the focal length at the first loop closure instead.
- Loop closure. Keyframes every 20 degrees. Coming back to the start corrects the lap total. Strong-match and lap-scale checks stop a look-alike side faking a closure. If tracking was lost on the way round, only the angle is fixed and the focal length is left alone.
- Relocalisation. When lost, the engine matches against nearby keyframes, so a turn made while lost is counted once tracking comes back.
- Panning. Turning the phone without walking shows no parallax. Those frames are not counted and a warning is shown.
- Tracking needs 60 percent of matches to agree. A blank scene gives noise matches that used to read as large bogus turns.
- Highlights are masked before feature detection, so a moving glint cannot fake a match.
- Blur is judged against the session's own recent frames, so a sharp plain part is not called blurry. Too bright needs blown out pixels, so a white part on a white table is fine.
- Optical flow fallback was considered and not added. When ORB fails at one frame per second, the step is too large for flow as well. Keyframe relocalisation helped more.

## Upper and lower rings

Only with a pose. Camera-only elevation is too noisy: up_and_down still drifts 27 degrees in yaw, and pitch is worse. With a pose, `coverage.rings` gives low, mid and high bands (split at 15 and 45 degrees above the part) and `orbit.elevation_deg` is filled. Without a pose `rings` is None. The webapp can ignore both until it wants them.

## Ideas borrowed from ARKit, Object Capture and Polycam

- Object Capture shows a ring of segments that fill as you walk, with separate rings for low, middle and high passes. That is what `coverage.rings` supports.
- ARKit tells users "move more slowly", "more light needed" and "point at a surface with more detail". The messages here follow that style: what is wrong, then one action.
- Polycam and Object Capture warn when the object is too close or too far. Here that needs depth.
- Object Capture recommends 20 to 40 degrees of overlap between shots. At one frame per second that means walking about 10 degrees per second, which matches SPEED_MAX_DEG_S of 20.

## Warning texts (for students aged 8 to 14)

| key | before | after |
|---|---|---|
| dark | Too dark, find more light | Too dark. Turn on a light. |
| bright | Too bright, move away from the light | Too bright. Turn away from the window or lamp. |
| blur | Hold still, the picture is blurry | Blurry picture. Hold the camera steady. |
| tracking | You lost the object, go back a little | Lost the object. Point the camera at it and step back to where you were. |
| speed | Slow down | Too fast. Walk around more slowly. |
| panning | (new) | Walk around the object. Do not just turn the camera. |
| too_close | (new, needs depth) | Too close. Take a step back. |
| too_far | (new, needs depth) | Too far away. Move closer to the object. |
| glare | Shiny glare, tilt the camera a little | Shiny spot on the object. Tilt the camera a little. |

## Still unverified until real footage

- Every threshold. Blur, light, glare and match ratio were set on synthetic frames and four short clips from one phone model. Webcams and Android phones may need different values.
- Real clips are much harder than synthetic ones. The cup clip walks about 37 degrees per second from 22 cm away and the engine loses it. The shoe clip reads 36 degrees for a true 111. The phone looks down about 67 degrees onto a flat cloth that fills most of the frame. A flat scene confuses rotation with sideways movement. Expect errors of tens of degrees on scans like that until it is tested with student footage.
- The pan threshold (parallax 0.08) has a thin margin on synthetic data: pans scored 0.02 to 0.08, real walking 0.09 and up. It has not been checked on a real student turning on the spot.
- A blank scene (plain part, plain room) still drifts. Lost frames there are scattered, so the lost warning may not appear.
- The pose path has only been tested with Objectron poses and synthetic poses. Real LiDAR depth maps have not been fed in.
- Latency was measured on this Mac only. Not on a school laptop.

## Real-world test protocol

Use the phone or webcam the students will use. Film at normal speed. The web app samples one frame per second.

1. Mark a circle of tape on the floor around a table, with marks every 45 degrees. Put a textured part (a labelled box) on the table.
2. Good scan: walk one full lap at a slow pace, about 40 seconds, keeping the part in frame. Repeat twice.
3. Bad scans, one video each, 30 to 60 seconds. Write down the seconds where each problem happens:
   - shake the phone hard for 5 seconds (blurry)
   - switch the room light off for 5 seconds (dark)
   - point at a window for 5 seconds (bright)
   - point at the ceiling for 5 seconds, then come back (lost)
   - stop and turn the phone left and right without walking (panning)
   - walk the lap in 10 seconds (too fast)
4. Repeat the good scan with a plain white part and with a shiny metal part.
5. For each video, write a notes file such as `0-20 good`, `21-26 blurry`, then run `uv run python calibrate.py video.mp4 --notes notes.txt --laps 1` (use `--laps` only on full-lap videos).
6. Check: the good scans give no warnings, each bad stretch gives the right warning within 2 seconds, and the lap reads within 30 degrees of 360. Move the thresholds the script suggests into `guidance.py` and run `uv run python test_guidance.py` again.
7. Send a few of these videos with notes to the guidance owner. They can be added to `eval_orbit.py` as fixed regression clips.
