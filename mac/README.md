# CADDY for Mac

A native SwiftUI app. A kid scans an object, gets a clean mesh, types a change, and saves an STL for Tinkercad or FreeCAD. The app starts the Python helper in `../webapp` as a child process and talks to it on 127.0.0.1. The API is in `../webapp/API.md`. The design spec is in `../webapp/UX_NOTES.md`.

## Build and run

```sh
cd mac
./build_app.sh                 # release build, writes build/CADDY.app
./build_app.sh debug           # faster debug build
./build_app.sh release --open  # build, then launch it
```

The script:
- builds the `CADDY` product with SwiftPM (scratch folder `.build-bundle`)
- draws the icon from `Resources/make_icon.swift` and turns it into `AppIcon.icns` (cached until that file changes)
- writes `Info.plist`: bundle id `com.nigel.caddy`, macOS 14 or later, the camera prompt text, and the key `CADDYProjectRoot` set to the repo root, so the app can find `webapp/`
- signs ad hoc with the hardened runtime and `Resources/CADDY.entitlements` (camera, outgoing network, no App Sandbox because the app runs `uv`)

The Mac needs Xcode or the command line tools, plus `uv` for the Python helper.

## Working on one part

Each folder in `Sources/` has one owner, so build only your target while others work:

```sh
swift build --target CADApp --scratch-path .build-app
```

| Target | What it holds |
| --- | --- |
| CADShared | API models, the `BackendAPI` protocol, the design tokens in `Theme.swift` |
| CADBackend | Starts and watches the Python helper. `HTTPBackendAPI`, `BackendService` |
| CADScan | Camera, guidance overlay, coverage ring |
| CADViewer | 3D model viewer, size badge, export |
| CADApp | Window, steps, edit panel, settings, menus |

## Files

- `Resources/make_icon.swift` draws the 1024 px icon with Core Graphics.
- `Resources/CADDY.entitlements` is used when signing.
- `build/` and `.build*/` are build output. Delete them freely.
