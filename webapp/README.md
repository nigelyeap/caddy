# CADDY web app

Scan an object with the camera, get a clean STL, then change it by typing what you want.

## Run

```
cd webapp && uv run uvicorn app:app --port 8000
```

Open http://localhost:8000 in Chrome or Safari and allow the camera.

## Steps

1. Scan. The camera view shows a ring that fills in as you walk around the object, plus speed, light and focus checks. About once a second a frame goes to `POST /api/guidance/frame`. The video is recorded and uploaded when you press Stop.
2. Clean up. The server turns the video into an STL.
3. Change and print. Turn the model with the mouse. Type a change or tap an idea, undo or redo it, then download the STL.

The endpoints and JSON shapes are in `API.md`. With the server running, `uv run python test_api.py http://localhost:8000` checks them. `UX_NOTES.md` has the UX changes and the design spec for the Mac app.

## What is stubbed

- `processing.py` holds `clean_scan(path_in, path_out_stl)` and `apply_edit(stl_in, instruction, stl_out)`. Both are stubs for now. `clean_scan` writes a sample cup. `apply_edit` only knows bigger, smaller, taller and shorter. Swap in `bench/clean.py` and `bench/edit.py` there.
- The guidance engine comes from `../guidance/guidance.py` when it imports. Otherwise a stub in `app.py` is used. The stub measures blur and light from the real frame and fakes speed, tracking and coverage. Set `CAD_GUIDANCE=stub` or `CAD_GUIDANCE=real` to force one. `GET /api/status` shows which one is running.

## Settings

- `ANTHROPIC_API_KEY` is read by the edit step once the real one is wired in. The app starts without it.
- Scans, STL versions and `state.json` are kept in `webapp/data/`. The model survives a server restart. Delete the folder to start fresh.
