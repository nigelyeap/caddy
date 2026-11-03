# Sharing CADDY with another Mac

## Build the package

```sh
cd mac
./build_app.sh --bundle
```

This writes `dist/CADDY.app`, `dist/CADDY-<version>-arm64.zip` and `dist/CADDY-<version>-arm64.dmg`.
The app carries its own Python 3.12, all packages and the helper code, so the other Mac needs no uv, no Python,
no internet and no `cad-training` folder.

The build Mac needs uv and a uv managed Python: `uv python install 3.12` (once). The prepared Python is
cached in `.build-bundle/runtime` and rebuilt when `webapp/uv.lock`, `bench/uv.lock` or `build_app.sh` changes.

## Limits

- Apple silicon only (arm64), macOS 14 or later.
- Ad hoc signature, not notarized. macOS blocks the first open (see below).
- About 320 MB installed. The zip is about 113 MB and the DMG about 145 MB.

## First open on the other Mac

macOS says the app "cannot be verified" because it is not notarized. Do this once:

1. Drag `CADDY.app` into Applications.
2. Right-click (or Control-click) it, choose Open, then Open again in the dialog.

On macOS 15 or later the dialog may only offer Done. Then open System Settings, Privacy & Security,
scroll down and click Open Anyway next to CADDY.

Or in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/CADDY.app
```

## Where things live on that Mac

- Saved models: `~/Library/Application Support/CADDY/data` (Settings, Show in Finder).
- Claude key: put `ANTHROPIC_API_KEY=...` in `~/Library/Application Support/CADDY/.env`, then reopen the app.
  Without a key only the quick changes work.
- Nothing is written inside the app, so its signature stays valid.
