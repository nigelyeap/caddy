# Turntable scan import: report

Date: 2026-11-01. Built by three parallel agents (importer, backend plumbing, UI), then integrated and checked in one pass. Nothing is committed.

## What was built

A kid can take the SD card out of the ELECTRONOOBS turntable scanner, open `scan_001.txt` (or a `.csv`) in CADDIY, and get a printable STL on the Edit screen.

- `bench/turntable.py` reads the `x,y,z` text, groups points into layers, and turns each layer into a radius profile around the turntable axis. It removes bad readings, fills gaps, adds flat top and bottom caps, and writes a watertight, outward-facing mesh in mm with the base on z=0.
- Old firmware files (the 1 degree angle bug, points spread over only 200 degrees) are detected on their own and fixed. `--legacy` and `--no-legacy` force either mode.
- Calibration comes from a JSON file. Keys: `z_units`, `radius_scale`, `radius_offset_mm`, `layer_height_mm`, `min_radius_mm`, `max_radius_mm`, `smooth`, `steps_per_rev`, `center_mm`. The module docstring lists the defaults. The importer looks for `--calib`, then `<stem>.calib.json`, then `turntable_calib.json` next to the file. The helper passes `bench/turntable_calib.json` when it exists, so one machine calibration covers every scan.
- The helper sends `.txt` and `.csv` straight to the importer. It skips `clean.py`, because the unit guess and table cut there would damage an already clean mm mesh. `clean.load()` also routes these files to the importer, so the bench tools can read them.
- Bad files get short kid messages: no scan points, too few layers, scan stopped early, or readings out of range. The raw error stays in the detail for the teacher.
- On the Scan screen the side panel has a new "Turntable scanner" section with three buttons: "Scan from turntable…", "How to use the turntable" (a 5 step help sheet with tips), and "Try a sample turntable scan" (a bundled cylinder). The skip dialog also has "Scan from turntable…". Dropping a `.txt` file on the window works too.

## Files changed

- New: `bench/turntable.py` (importer, sample generator, self-check)
- New: `mac/Sources/CADApp/Resources/turntable_sample.txt` (30 mm radius cylinder, 40 mm tall, fixed firmware format)
- New: `mac/Tests/CADAppTests/ScanFilesTests.swift`
- New: `webapp/test_turntable_route.py`
- `bench/clean.py` (`load()` routing)
- `webapp/processing.py` (`TURNTABLE_EXT`, calibration file, routing)
- `webapp/app.py` (`SCAN_HINTS`, `_friendly_scan`, sample check)
- `mac/Package.swift` (sample resource)
- `mac/Sources/CADApp/AppModel.swift` (`ScanFiles.turntable`, `ScanFiles.source`, error notes show the helper's message)
- `mac/Sources/CADBackend/MockBackendAPI.swift` (mock treats txt and csv as a real scan)
- `mac/Sources/CADApp/RootView.swift`, `mac/Sources/CADApp/Screens.swift` (new buttons, help sheet, picker text)

## How to test

```
cd /Users/nigelyeap/Documents/cad-training
uv run --project bench python bench/turntable.py --selfcheck          # ok
uv run --project webapp python webapp/test_turntable_route.py         # ok
uv run --project webapp python webapp/processing.py                   # ok (existing edit check)
cd mac && swift build && swift test                                   # 18 tests, 0 failures
```

End to end by hand:

```
uv run --project bench python bench/turntable.py --make-sample mug /tmp/x.txt --legacy --noise
uv run --project bench python bench/turntable.py /tmp/x.txt /tmp/x.stl   # prints layers, legacy, extents
```

Result on 2026-11-01: the legacy noisy mug was auto-detected and came out watertight and manifold, 70 x 70 x 50 mm, base on z=0, through both the CLI and `processing.clean_scan`. Self-check volumes are within 0.1 percent of the true shapes for cylinder, sphere and mug, clean, noisy (with a 30 degree gap) and legacy.

In the app: `./build_app.sh debug`, then the Scan screen, then "Try a sample turntable scan". Screenshots at large and largest text were checked. The help sheet itself was not screenshotted.

## Known limits

- Only shapes that are solid around the turntable axis come out right. Handles, undercuts, holes and mug insides are lost. Gaps are bridged with straight lines.
- Top and bottom are always flat caps.
- Wrong z units or a wrong lead screw distance cannot be detected. Fix them with `z_units` or `layer_height_mm`.
- Legacy fix assumes the old firmware logged exactly 1 degree per step.
- Readings past the centre (sensor reading over 8 cm) land 180 degrees off. The median filter hides single cases only.
- With `smooth` set to 0 or 1, spikes inside the radius range stay in the mesh.
- The sensor curve itself is not corrected. `radius_scale` and `radius_offset_mm` are a straight-line fix only.
- A calibration file next to the kid's own file is not uploaded by the app. The helper uses `bench/turntable_calib.json`.
- No live USB serial yet (Step 2 in IR_SCANNER_FEASIBILITY.md).

## What the hardware person must still send

1. A raw SD file of a known cylinder (for example a 60 mm can), plus its real diameter and height. This sets `radius_scale` and `radius_offset_mm`.
2. The measured distance from the sensor to the turntable centre.
3. The real layer height on the built machine, and whether z in the file is in mm or cm.
4. Which firmware the files come from (old 1 degree bug or fixed), and a raw file of one matte toy for a real-world check.
