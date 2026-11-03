# Local API

The Python server is a local service. The web page in `static/` uses it today. The Mac app will use the same endpoints.

Start it with `uv run uvicorn app:app --host 127.0.0.1 --port 8000` from `webapp/`. Keep it on 127.0.0.1. There is no login, so it must never listen on the network.

Check it with `uv run python test_api.py http://localhost:8000` while the server runs. That test replaces the current model with the sample cup.

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

## For the Mac app

- Launch the server as a child process on a fixed port on 127.0.0.1. Wait for `GET /api/status` to answer before showing the first screen.
- If a request fails to connect, show the "lost contact" state and retry `GET /api/status` every 3 seconds.
- After the server comes back, read State. If `status` is not `ready` while the user is on the edit screen, the model is gone. Go back to Scan and say so.
- `depth` and `pose` hooks exist in the guidance engine but not in this API yet. Adding them means a new endpoint or a multipart frame. Agree the shape with the `guidance/` owner first.
