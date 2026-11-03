# Local API

The Python server is a local service. The web page in `static/` uses it today. The Mac app will use the same endpoints.

Start it with `uv run uvicorn app:app --host 127.0.0.1 --port 8000` from `webapp/`. Keep it on 127.0.0.1. There is no login, so it must never listen on the network.

Check it with `uv run python test_api.py http://localhost:8000` while the server runs. That test replaces the current model with the sample cup. The parts routes have their own test that needs no server: `uv run python test_parts_api.py`.

## Rules

- One user, one model. The server keeps one current model and its history.
- The model survives a server restart. It is saved to `data/state.json`. A new scan clears the old versions.
- Times are seconds. Sizes are millimetres. z is up.
- Every state endpoint returns the same State object, shown below.
- Every error has the same body. See Errors.

## State

Returned by `GET /api/status`, `POST /api/edit`, `POST /api/undo` and `POST /api/redo`.

```json
{
  "status": "idle | processing | ready | error",
  "error": "short message for the screen, or null",
  "detail": "raw text for the teacher, or null",
  "versions": [{"file": "v0.stl", "instruction": "Sample cup"}],
  "redo": [{"file": "v1730.stl", "instruction": "make it 20 percent taller"}],
  "sample": true,
  "started": 1793294437.2,
  "engine": "real | stub"
}
```

- `versions` is oldest first. The last entry is the current model. The first entry is the scan, named "Your scan" or "Sample cup".
- `redo` holds undone versions. The last entry is the next one `redo` brings back. A new edit empties it.
- `sample` is true when the model is the stand-in cup. Video to mesh does not exist yet, so every video upload gives the cup. Show this to the user.
- `started` is the Unix time the current scan upload began. Use it for an honest elapsed timer.
- `engine` says which guidance engine runs. `stub` fakes the coverage ring on a timer. Say so on screen.
- `file` is an internal name. Clients should not build paths from it. Use `GET /api/model.stl`.

## Errors

Any status code of 400 or above has this body:

```json
{"detail": {"message": "Plain words for the kid.", "detail": "Raw text for the teacher, or null."}}
```

Show `message` large. Put `detail` behind a "Details for the teacher" control. The one exception is FastAPI's own 422 for a malformed request body, where `detail` is a list. Treat it as a bug in the client.

| Code | When |
| --- | --- |
| 400 | Empty instruction, or a frame that is not a JPEG |
| 404 | No model yet |
| 409 | Busy: a scan is processing or an edit is running, or there is no model to edit |
| 500 | The edit failed. `message` says why in plain words |

## Endpoints

### GET /api/status

Returns State. Cheap. Poll it once a second while `status` is `processing`. Also use it as the health check on launch.

### POST /api/guidance/frame

Body: one JPEG image, `Content-Type: image/jpeg`. Send about one frame a second, around 640 px wide. Returns the guidance result. This shape is a fixed contract owned by `guidance/`:

```json
{"blur": {"score": 212.4, "ok": true},
 "light": {"mean": 121.0, "clipped_pct": 0.4, "ok": true, "issue": null},
 "tracking": {"match_ratio": 0.8, "ok": true},
 "speed": {"value": 12.5, "ok": true},
 "coverage": {"sectors": [1, 1, 0.4, 0, 0, 0, 0, 0, 0, 0, 0, 0], "pct": 20.3},
 "warnings": ["Slow down"],
 "t": 1234.5}
```

- `light.issue` is `"dark"`, `"bright"`, `"glare"` or null.
- `speed.value` is degrees per second with the real engine.
- `coverage.sectors` has 12 values from 0 to 1, clockwise from the top. `pct` is 0 to 100.
- `warnings` are already short and plain. Show the first one.
- About 50 ms per frame. Drop a frame if the last one has not answered yet.

### POST /api/guidance/reset

No body. Clears coverage and tracking. Call it when the user presses Start. Returns `{"ok": true}`.

### POST /api/scan

Multipart form with one file in the field `video`. The name matters: the extension picks the path.

- `.stl`, `.ply` or `.obj`: a real mesh, cleaned by `bench/clean.py`.
- Anything else, such as `.webm`, `.mp4` or `.mov`: video. Gives the sample cup for now. An empty file is fine for "use a sample".

Returns `{"status": "processing"}` right away. Then poll `GET /api/status`. 409 if something is already running.

### POST /api/edit

Body: `{"instruction": "make it 20 percent taller"}`. Blocks until the edit finishes, often 5 to 40 seconds with Claude. Use a client timeout of at least 150 seconds. Returns State with a new last version.

Without `ANTHROPIC_API_KEY` only the canned instructions in `bench/edit_cases.py` work. Every example chip in the UI is one of them, except "Name on it", which only fills the box. `bench/smoke.py` checks this. Anything else returns 500 with a message that says so.

### POST /api/undo, POST /api/redo

No body. Returns State. Undo never removes the first version. Both return 409 while an edit runs.

### GET /api/model.stl

The current model as binary STL. `Cache-Control: no-store`. 404 when there is no model.

## Many parts in one build

State also has these keys, on every state endpoint:

```json
{
  "parts": [{"id": "73cc9fd1", "name": "Part 1", "file": "p1793696649401456000.stl", "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}],
  "putAway": [],
  "note": null
}
```

- `parts` and `putAway` mirror the current version. Each version entry may carry its own `parts` and `putAway`, so undo and redo bring back the parts list.
- Empty `parts` means the single-model behaviour above, unchanged. Nothing turns parts on except split, add and open.
- `x, y, z` are mm in the STL frame (z up) and place the part's bottom centre. `yaw` is degrees about z. Each part `file` is seated: centred on x, y with its base on z=0.
- `putAway` is the tray: parts set aside, same shape.
- `note` is null except on a split of one piece.
- Part files `p<time_ns>.stl` are never rewritten or deleted. Cache them by name.
- `versions[i].file` is still there. In parts mode it is the model the parts came from. Do not show it.

Every POST below takes a JSON body, returns State, and adds one undoable version, except bake (no change) and open (a new build). Mesh calls (split, add, join, cut, edit) return 409 while another one runs. Refusals use the usual error body with a 400.

| Call | Body | Does |
| --- | --- | --- |
| `GET /api/part/{file}` | | STL bytes of one part file. 404 for any name that is not `p<digits>.stl` or does not exist. |
| `POST /api/parts/split` | `{}` | Splits the current single model into its separate pieces, laid out side by side along x with a 10 mm gap. One piece: State unchanged with `note: "It is one piece"`. 409 if the build is already in parts. |
| `POST /api/parts/move` | `{id, x, y, z, yaw}` | Sets that part's placement. No mesh work. |
| `POST /api/parts/duplicate` | `{id}` | New id, same file, 20 mm further along x. |
| `POST /api/parts/delete` | `{id}` | Moves the part to `putAway`. |
| `POST /api/parts/restore` | `{id}` | Moves it back from `putAway` to the end of `parts`. |
| `POST /api/parts/add` | `{name}` | A library shape: `cube`, `ball`, `cylinder`, `cone`, `pyramid`, `donut`, `star`, `heart`, `base plate`. Placed on the floor, 10 mm to the right of everything. On a single model, that model first becomes a part named "Model", left where it was. |
| `POST /api/parts/join` | `{ids: [...]}` | Unions the parts at their placements into one new part at the union's bottom centre, yaw 0. Gaps up to about 2 mm still join. Too far apart: 400 "Push them together so they touch, then join." |
| `POST /api/parts/cut` | `{id, point: [x,y,z], normal: [x,y,z]}` | Plane in that part's own file frame. The pieces replace the part, each nudged 3 mm along the normal away from the other side, never below the floor. A plane that misses: 400 with a plain message. |
| `POST /api/parts/rotate` | `{id, degrees, axis}` | Tips the part about a flat world axis through its centre. `axis` is `"x"`, `"y"` or an azimuth in degrees (0 = x, 90 = y), default `"x"`. New file, base back on the floor, yaw kept. |
| `POST /api/parts/resize` | `{id, sx, sy, sz}` | Scale factors in world axes, each 0.05 to 20, about the part's bottom centre, which stays put. Non-uniform: the yaw is baked into the new file and the part comes back with yaw 0. Uniform keeps the yaw. 400 if the result is over 250 mm in x, y or z, or under 1 mm in any direction. |
| `POST /api/parts/mirror` | `{id, axis}` | Mirrors across the vertical plane through the part centre whose normal is `axis` (same values as rotate). Yaw kept, mesh stays closed. |
| `POST /api/parts/layflat` | `{id}` | Lies the part on its biggest stable flat side (convex hull face with the centre of mass above it, least turning among faces within 5 percent of the biggest). Yaw kept. Already lying on it (within 0.5 degrees): State unchanged, no new version. |
| `POST /api/edit` | `{instruction, part}` | In parts mode `part` (an id) is required, else 400 "Pick a part first.". The edit runs on that part's file. The result replaces it in place: same id, x and y follow its new centre, z stays. |
| `GET /api/model.stl` | | In parts mode: every placed part merged into one STL. No union, so unjoined parts still export as separate bodies. |
| `POST /api/parts/bake` | `{path}` | `path` is an absolute `.stl` path. Writes the merged STL there, and `path + ".parts/"` with `parts.json` (`{parts, putAway}`) and a copy of every part file used. 409 with no parts. |
| `POST /api/parts/open` | `{path}` | Reads `path + ".parts/parts.json"`, copies the part files back, and starts a new build with one version. 400 if the files are missing or bad. |

Mesh work runs in one long-lived `bench/parts.py --serve` worker started on first use, so only the first call pays the start-up cost.

## For the Mac app

- Launch the server as a child process on a fixed port on 127.0.0.1. Wait for `GET /api/status` to answer before showing the first screen.
- If a request fails to connect, show the "lost contact" state and retry `GET /api/status` every 3 seconds.
- After the server comes back, read State. If `status` is not `ready` while the user is on the edit screen, the model is gone. Go back to Scan and say so.
- `depth` and `pose` hooks exist in the guidance engine but not in this API yet. Adding them means a new endpoint or a multipart frame. Agree the shape with the `guidance/` owner first.
