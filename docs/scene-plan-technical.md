# CADDIY: many objects in one build (technical plan)

Scope: drag, add from a library or a new scan, smart split, join, cut by drawing a line, duplicate. Plus suggestions.
Status: ideas only. No project files changed.

## 1. What the code does today (the facts this plan rests on)

- `webapp/app.py` keeps one global `state`. `versions` is a list of `{"file", "instruction"}`. One STL per version. `redo` holds undone versions. `_save()` writes `data/state.json`.
- `GET /api/model.stl` returns `versions[-1]["file"]`. `POST /api/edit` runs `processing.apply_edit` on that one file.
- All mesh work runs in the bench env through `processing._bench()` (a `uv run` subprocess). The webapp env has no trimesh or manifold3d.
- `bench/edit.py` `edit()` calls `seat()` (centre on x, y, base on z=0), and `validate()` rejects any result where `components != 1`.
- `bench/clean.py` `clean_scan()` keeps every piece with at least `KEEP_PART` (15%) of the biggest area, then unions them with `batch_boolean(Add)` into ONE mesh and warns "Kept N separate pieces".
- Found bug: a scan of two separate objects already becomes one mesh with 2 components. Every edit on it then fails `validate()` with "it is in 2 separate pieces". Smart split fixes this for free.
- `ViewerScene` has one `modelNode` under `modelRoot`. `setModel()` swaps it with the sweep shader. Camera radius, grid and shadow fit that one node.
- `OrbitSCNView.mouseDragged` orbits on left drag and pans with Option. There is no hit testing anywhere.
- `AppModel.refreshModel()` downloads one STL to `model-N.stl`. `ModelViewer(stlURL:revision:)` takes one URL.
- `BuildLibrary` stores plain `<stamp> -- name.stl` files with no index.

## 2. Data model

One build is a scene: a list of parts. Each version is a full snapshot of that list.

```
Part    = {"id": "a3f9", "name": "Dog", "file": "p1730...stl", "x": 0, "y": 0, "z": 0, "yaw": 0}
Version = {"parts": [Part, ...], "instruction": "Moved the dog"}
```

- `file` is the mesh in its own local frame, seated by `seat()` (centred on x, y, base on z=0). Files are never rewritten. A new mesh always gets a new name `p{time_ns}.stl`.
- `x, y, z, yaw` place the part's bottom centre in the build, in mm and degrees about z. No tilt and no per-part scale in v1. Scale stays an edit, so it bakes into a new file.
- Because files are immutable, a move or a duplicate costs one JSON entry and zero mesh work. Undo of a move is free.
- Selection lives only in the app. It is not part of a version.
- Swift side (`mac/Sources/CADShared/Models.swift`): add `struct Part: Codable, Hashable, Identifiable` and change `ModelVersion` to `parts: [Part]` plus `instruction`. Remove `ModelVersion.file`. Its only reader is `AppModel.refreshModel()`.
- Migration: when `app.py` loads an old `state.json`, wrap each `{"file"}` version as `{"parts": [{"id": "a", "file": f, x, y, z, yaw all 0}]}`. Do it in the existing `try` block at module load.
- Rename the glob in `upload_scan()` from `v*.stl` to `p*.stl`. Add a prune in `_save()` that deletes `p*.stl` files no version or redo entry names.

## 3. Backend API (webapp/app.py)

Every scene change is one call that appends one version, clears `redo`, and returns `_snapshot()`. Same shape as `/api/edit` today, so undo, redo and the history list keep working.

| Call | Mesh work | Notes |
|---|---|---|
| `GET /api/part/{file}` | none | Immutable file, so send `Cache-Control: max-age` and let the app cache by name. Check `file` against `p\d+\.stl` (path safety). |
| `POST /api/parts/move` `{id, x, y, z, yaw}` | none | If the last version is a move of the same id, replace it instead of appending. Keeps history short. |
| `POST /api/parts/duplicate` `{id}` | none | Same `file`, new id, placed one width plus 5 mm to the right. |
| `POST /api/parts/delete` `{id}` | none | Refuse if it is the last part. |
| `POST /api/parts/add` `{library: "star"}` or multipart file | library: none or one call. scan: clean | A scan added this way reuses `_process()` with a `mode="add"` flag. |
| `POST /api/parts/split` `{id}` | `parts.py split` | Used by the auto split and by a "Pull apart" button. |
| `POST /api/parts/cut` `{id, point, normal}` | `parts.py cut` | Plane in the part's local frame. The app converts it (section 5). |
| `POST /api/parts/join` `{ids}` | `parts.py join` | Takes the world placements of each part. |
| `POST /api/edit` `{instruction, id}` | `edit.py` | Runs on that part's file only. Writes a new file. Keeps the part's x, y, yaw. |
| `GET /api/model.stl` | `parts.py bake` | The printable export. See below. |

- New file `bench/parts.py`: a small CLI with `split`, `cut`, `join`, `bake`. It imports `_m`, `_t` and `seat` from `edit.py` and `check` from `clean.py`. It prints a JSON line with the output files and their offsets so `app.py` can place the new parts where the old one was. It needs an `assert`-based `__main__` self-check like `processing.py` has.
- `processing.py` gets thin wrappers next to `apply_edit()`: `split_part()`, `cut_part()`, `join_parts()`, `bake()`.
- `bake` applies each part's transform, then concatenates the parts. Separate parts print as separate bodies on one plate, which slicers handle. Parts that overlap but are not joined get unioned in `bake` so the STL stays clean. The app shows a note: "These parts touch. Join them so they print as one."
- Locking: hold `edit_lock` for every mesh call, same as `/api/edit`. Moves and duplicates only need `state_lock`.
- Edit race: an edit takes up to 40 s. A move done meanwhile would be lost when the edit appends its snapshot. v1 rule: the app blocks drag, cut and join while `isEditing` (it already greys most controls). Upgrade later: merge the edit result into the newest version by part id.

## 4. How edit.py fits

- `edit.py` stays one mesh in, one mesh out. The server passes the selected part's file, which is already seated, so the prompt's frame ("centred on x=0, y=0, base on z=0") stays true.
- After the edit, `app.py` re-seats the result. The base may move (cut_off bottom, add_base_plate). The part keeps its x, y, yaw and drops to the support height.
- No selection and one part: edit that part. No selection and many parts: the app asks "Tap the part you want to change first" without a server call.
- `make_lid` and `copies` keep working. A lid comes back as one mesh and replaces the part. Later idea: let `edit.py` return a list so "make a lid" adds a second part. That needs a `SYSTEM` prompt change and a new `result` contract, so it waits.
- Edits that mention other parts ("put the hat on the dog") are out of scope for v1. Claude would need every part's bounds in `describe()`. Unknown how well it reasons about two meshes.

## 5. Viewer (mac/Sources/CADViewer)

**Scene in ViewerScene.swift**
- Replace `modelNode` with `parts: [String: SCNNode]`. Each entry is a container node (x, y, z, yaw in SceneKit y-up) holding a child with the current STL z-up to y-up turn from `setModel()`.
- Cache `SCNGeometry` by file name. A duplicate shares the geometry. Give each node its own material copy so one can be highlighted.
- New `setScene(_ parts: [PartView], animate:)` diffs by id: add (scale-in pop), remove (fade), move (SCNTransaction), new file on same id (the existing sweep, run on that node only).
- `radius`, `center`, `rebuildGrid()` and `fitShadow()` use the union bounds of all parts. Today they use one mesh's bounds.
- `modelCorners` becomes all parts' corners, so `ViewerController.modelRect()` keeps working for Caddiy's overlay.
- Selection: emission tint on the selected node's material. An outline needs a second pass and is not worth it yet.

**ModelViewer.swift**
- `ModelViewer(stlURL:revision:)` becomes `ModelViewer(parts: [PartView], selected: String?, revision:)`. `PartView` = id, local URL, transform.
- `ViewerController.load()` keeps the cancel and failure logic. `info` and `sizeDelta` follow the selected part, or the whole build when nothing is selected.
- `AppModel.refreshModel()` downloads only part files it has not cached (`temporaryDirectory/CADDIY/parts/<file>`). Most changes then download nothing.

**Picking and dragging in OrbitSCNView**
- `mouseDown`: `hitTest(point, options: [.rootNode: partsRoot, .searchMode: SCNHitTestSearchMode.closest.rawValue])`. Walk up to the container to get the id.
- Drag on a part moves it. Drag on empty space orbits as today. This is the big UX risk (see section 8).
- Moving: build the mouse ray from `unprojectPoint` at depth 0 and 1. Intersect it with the horizontal plane at the grab point's height. Keep the grab offset so the part does not jump to the cursor centre.
- Support height: while dragging, cast `scene.rootNode.hitTestWithSegment` straight down from above the part's centre against the other parts. Rest on the highest hit, or the floor. This is what lets a hat sit on a head before a join.
- Clamp x, y to the 250 mm bed. Snap to 1 mm. Hold Shift to snap to the grid step.
- Turning: `rotate(with:)` (trackpad twist) turns the selected part instead of the camera. Keys `[` and `]` turn it 15 degrees.
- `mouseUp` after a real move: call `AppModel.movePart(id:to:)`, which posts `/api/parts/move`. Show the move straight away and roll back if the call fails.

**Cut by drawing a line**
- A Cut tool mode. The stroke draws in a SwiftUI `Canvas` overlay. Use only its first and last points. A wobbly kid stroke still means one straight cut.
- Plane math, in a pure function `CutPlane.make(eye:a:b:)` in a new `CADViewer/CutPlane.swift`: unproject both screen points at depth 0.5 to get `A` and `B`. The plane holds the camera eye, `A` and `B`. Normal `n = normalize(cross(A - eye, B - eye))`, point `eye`.
- Because the plane holds the eye, it shows on screen as exactly the drawn line, extended. Preview it as a full-width dashed line before the kid lets go. The kid then sees that the cut runs right through, not only where they drew.
- Target part: the part under the stroke's midpoint by hit test, else the selected part. Ignore a stroke that misses every part.
- Convert the plane to the part's local z-up frame (inverse of the container and the y-up turn). Send `point` and `normal` to `/api/parts/cut`.
- Server: `parts.py cut` runs manifold3d `Manifold.split_by_plane(normal, offset)`. Both halves come back closed and capped. Each half then goes through the same split step, since cutting a cup's rim can make 3 pieces.
- Drop pieces under about 1% of the volume. Each piece is re-seated as a new part and placed so it looks unmoved. The app then slides the pieces 5 mm apart along the floor and drops any floating piece to the floor.

## 6. Feature by feature

1. **Drag.** Client hit test and ray-plane math, one `move` call on mouse up. No mesh work.
2. **Add from a library.** Build the library from the `edit.py` part helpers, so there are no asset files: star = `shape("star", 30, 5)`, ball = `sphere(30)`, cube, cylinder, cone, pyramid, donut = `torus`, heart, base plate. `parts.py library NAME OUT` writes it once into `data/library/`. Thumbnails: render each with `ViewerScene.snapshot()` the first time and cache it. My builds items can also be added as parts.
   **Add a new scan.** `AppModel.open()` today sets `pendingFile` and asks to replace. Give that dialog two buttons, "Add to this build" and "Start a new build". Add uploads to `/api/parts/add`. The processing screen runs as today, then returns to Edit with the new part placed to the right.
3. **Smart split.** In `clean.py`, the pieces exist before the union. Simplest change: after `clean_scan()`, `parts.py split` runs `Manifold.decompose()` on the final mesh and seats each piece. Call it from `app._process()`, then build version 0 with one part per piece, kept where they were. Limit: objects touching in the scan fuse into one component, so they will not split. The Cut tool is the manual fallback.
4. **Join.** `parts.py join` bakes each part's transform, runs `batch_boolean(Add)`, then checks `num_components`. If it is more than 1 the parts do not touch: refuse with "Push them together so they touch, then join." The result is one new part at the union's bottom centre. It drags as one because it is one. A soft "group" (drag together, stay separate) is not needed for what was asked. Add it if kids want to unjoin without undo.
5. **Cut.** Section 5.
6. **Duplicate.** Server side only, no mesh work. Cmd+D in the app.

## 7. History, undo and My builds

- Each scene call is one version, so `EditScreen`'s history rows, `canUndo` and `canRedo` keep working. Instructions are made on the server: "Added a star", "Moved the dog", "Cut the dog in two", "Joined 2 parts", "Split the scan into 2 parts".
- Consecutive moves of the same part merge into one version (section 3).
- My builds: `BuildLibrary.save()` keeps writing `<stamp> -- name.stl` (the baked export, so old builds and the print path still work). Next to it, write a folder `<stamp> -- name.parts/` with `scene.json` and the part STLs. `reload()` already ignores non-STL entries. `delete()` removes both.
- `AppModel.openBuild()`: if the `.parts` folder exists, post it to a new `POST /api/scene/load`, else upload the STL as today. Old builds open as one part.
- `save()` (Save a copy) and Print download `/api/model.stl`, the baked export.

## 8. Risks and unknowns (prototype in this order)

1. **Drag versus orbit for kids.** Left drag orbits today. If dragging a part also uses left drag, kids will move parts when they meant to turn the view. Prototype both: (a) grab a part to move it, drag empty space to orbit, (b) a Look / Move / Cut tool switch. Test with 2 or 3 kids. Half a day in `ViewerScene` with two hard-coded boxes.
2. **Frame conversion for the cut.** The STL z-up to SceneKit y-up turn plus the seat offset is easy to get wrong by a sign. Write `CutPlane` as a pure function with a unit test, and draw the plane as a debug quad before wiring the server.
3. **Subprocess cost.** Each mesh call is a `uv run` startup plus trimesh and manifold3d imports. Guess 1 to 3 s. Not measured. If it is too slow, keep one long-running bench worker (stdin JSON lines) instead of a process per call.
4. **split_by_plane on real scans.** `clean.py` output should be manifold, but slivers after decimation may give thin wedges. Check against `bench/scans`.
5. **Join of near-touching parts.** A 0.2 mm gap reads as touching to a kid and fails the union. Option: if the gap is under 2 mm, nudge one part down or across before the union. Untested.
6. **Touching objects in one scan** do not split (section 6.3). Real segmentation is research, not a weekend.
7. **Fit on the bed.** `bake` must check the whole layout fits 250 mm, not only each part.
8. **Viewer load.** 10 parts at 50k faces each is fine for SceneKit. Not measured past that. Cap parts at about 12.

## 9. Tests

- `bench/parts.py` `__main__` self-check: two far boxes split into 2 parts with the same total volume. A box cut by a plane gives 2 watertight halves whose volumes sum to the box. A cut through a hollow cup rim gives the right piece count. Two overlapping boxes join into 1 component. Two far boxes are refused. A bake places a moved part at the right bounds.
- `webapp/test_scene.py` with FastAPI `TestClient`, and the bench calls stubbed: add, move, move again (one version), duplicate, delete, undo, redo, an old `state.json` migrates, the prune keeps files that `redo` still names.
- Swift `Tests/CADAppTests`: `Part` and `ModelVersion` decoding. `CutPlane.make` puts eye, A and B on the plane. A ray-plane test for dragging.
- Extend `ViewerSelfCheck.swift`: load two parts, hit test the centre of each on screen, expect the right id.
- By hand: `bench/scans` files with two objects, a cut through each sample, and a kid session for risk 1.

## 10. Build order and rough effort

| Phase | Work | Effort |
|---|---|---|
| 0 | Prototype drag versus orbit and `CutPlane` with hard-coded boxes. Kid test. | 1 to 2 days |
| 1 | Scene data model, migration, `/api/part`, multi-node `ViewerScene`, part cache in `AppModel`. Still one part per build. Nothing visible changes. | 3 days |
| 2 | Selection, drag, turn, `move` call with merge, duplicate, delete. Edit on the selected part. | 3 days |
| 3 | `bench/parts.py` (split, bake), auto split after a scan, baked export, My builds sidecar. | 2 to 3 days |
| 4 | Library from helpers, "Add to this build" for a scan. | 2 days |
| 5 | Join with the touch check and support height while dragging. | 2 days |
| 6 | Cut tool: overlay, preview line, server cut, slide apart. | 3 days |
| 7 | Tests in section 9, kid session, fixes. | 2 days |

About 3 to 4 weeks for one person. Phase 1 is the risky refactor. Ship it alone first so a bug there shows up before the new tools pile on.

## 11. More features worth adding (cheapest first)

- **Lay flat**: rest a part on its biggest flat face. After a cut, that is the cut face, which is the best print side. One `parts.py` call using `trimesh.Trimesh.compute_stable_poses`.
- **Mirror copy**: duplicate plus `mirror()` from `edit.py`. Handy for ears and wings.
- **Arrange on the plate**: pack all parts on the 250 mm bed before printing. A simple row packing is enough.
- **Snap to touch**: while dragging, if a part comes within 3 mm of another, pull it into contact. Makes Join work first time (risk 5).
- **Subtract** ("use this part to cut a hole in that one"): manifold difference, same plumbing as join. A cookie cutter and a box with a shaped hole become easy.
- **Colour per part**: a different clay tint per part in the viewer. It is display only, but it makes many parts readable at a glance.
- **Scale handle** on the selected part, baked into a new file on release through `scale_by`.
