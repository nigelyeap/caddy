# Backlog

## Colour in the model (parked 2026-10-30)
Colour is dropped today. STL has no colour, `bench/clean.py` ignores it, the viewer draws one grey, and the edit prompt refuses colour requests.
- Step 1: keep per-vertex colour from PLY or OBJ scans through cleanup and show it in the viewer (about a day).
- Step 2: export 3MF for colour printers (Tinkercad and FreeCAD ignore its colour). STL stays the main output.
- Step 3: colour edits such as "paint the handle red". Needs region selection. Bigger job.
- Open question: is colour for printing or only on-screen realism? Depends on whether the live camera gives colour.

## Waiting on the user
- Live camera and LiDAR details, then reconstruction and the guided fill-in scan interface.
- Run the live Claude bench with the API key (see bench/REPORT.md).
- Real footage and real scans for guidance tuning.

## FreeCAD live link
See mac/FREECAD_LINK_SCOPE.md. Option B (watcher macro) is next. FreeCAD is installed.
