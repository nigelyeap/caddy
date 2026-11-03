#!/bin/zsh
# Builds CADDIY.app from the Swift package.
# Usage: ./build_app.sh [release|debug] [--open] [--bundle]
# --bundle puts Python, the packages and the server code inside the app, so it runs on a Mac
# without uv or the project folder, then writes dist/CADDIY-<version>-arm64.zip and .dmg. See DISTRIBUTION.md.
set -euo pipefail
unset DEVELOPER_DIR

HERE="${0:A:h}"
CONFIG=release; OPEN=0; BUNDLE=0
for a in "$@"; do
  case "$a" in
    release|debug) CONFIG="$a" ;;
    --open) OPEN=1 ;;
    --bundle) BUNDLE=1 ;;
    *) echo "usage: $0 [release|debug] [--open] [--bundle]"; exit 2 ;;
  esac
done

APP_NAME="CADDIY"
BUNDLE_ID="com.nigel.caddiy"
VERSION="0.1.0"
BUILD="$(date +%Y%m%d%H%M)"
SCRATCH="$HERE/.build-bundle"
OUT="$HERE/build"; (( BUNDLE )) && OUT="$HERE/dist"
APP="$OUT/$APP_NAME.app"

cd "$HERE"
echo "Building $CONFIG..."
swift build -c "$CONFIG" --product "$APP_NAME" --scratch-path "$SCRATCH"
BIN_DIR="$(swift build -c "$CONFIG" --product "$APP_NAME" --scratch-path "$SCRATCH" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
# SwiftPM resource bundles, if any target declares resources.
for b in "$BIN_DIR"/*.bundle(N); do cp -R "$b" "$APP/Contents/Resources/"; done

# Icon: render once, then cache it until make_icon.swift or the logo changes.
ICNS_CACHE="$SCRATCH/AppIcon.icns"
if [[ ! -f "$ICNS_CACHE" || "$HERE/Resources/make_icon.swift" -nt "$ICNS_CACHE" \
      || "$HERE/Resources/caddiy_logo_1024.png" -nt "$ICNS_CACHE" \
      || "$HERE/mascot/poses_ai/logo_neutral.png" -nt "$ICNS_CACHE" \
      || "$HERE/mascot/poses_ai/logo_neutral_1024.png" -nt "$ICNS_CACHE" ]]; then
  echo "Drawing the icon..."
  TMP="$(mktemp -d)"
  swift "$HERE/Resources/make_icon.swift" "$TMP/icon_1024.png"
  SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$ICNS_CACHE"
  rm -rf "$TMP"
fi
cp "$ICNS_CACHE" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CADDIY</string>
  <key>CFBundleDisplayName</key><string>CADDIY</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSCameraUsageDescription</key>
  <string>CADDIY uses the camera to see the object you want to scan. Nothing is saved until you press Start scan.</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>CADDIY keeps its helper program and your saved models in the cad-training folder in Documents.</string>
$( (( BUNDLE )) || echo "  <key>CADDIYProjectRoot</key><string>${HERE:h}</string>")
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>3D model or video</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.standard-tesselated-geometry-format</string>
        <string>public.polygon-file-format</string>
        <string>public.geometry-definition-format</string>
        <string>public.movie</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

if (( BUNDLE )); then
  ROOT="${HERE:h}"
  RT="$SCRATCH/runtime"
  PY="$RT/python/bin/python3"
  # The Python and packages take a few minutes, so keep them until a lock file or this script changes.
  if [[ ! -x "$PY" || "$ROOT/webapp/uv.lock" -nt "$RT" || "$ROOT/bench/uv.lock" -nt "$RT" || "$HERE/build_app.sh" -nt "$RT" ]]; then
    echo "Preparing the bundled Python..."
    # A python-build-standalone tree from uv. It is relocatable, unlike a venv. Get one with: uv python install 3.12
    PYSRC="$(uv python find --managed-python 3.12)"
    rm -rf "$RT"; mkdir -p "$RT"
    cp -R "${PYSRC:A:h:h}" "$RT/python"
    LIB="$RT/python/lib/python3.12"
    for p in webapp bench; do
      uv export --project "$ROOT/$p" --frozen --no-hashes --no-header --no-emit-project --no-dev -o "$SCRATCH/req-$p.txt" >/dev/null
    done
    # Into the interpreter's own site-packages: the sandboxed edit child runs with -I, which ignores PYTHONPATH.
    uv pip install --python "$PY" --target "$LIB/site-packages" --only-binary :all: \
      -r "$SCRATCH/req-webapp.txt" -r "$SCRATCH/req-bench.txt"
    # Drop what the helper never uses: Tk, IDLE, pip, headers, tests.
    rm -rf "$RT/python"/{include,share} "$RT/python/lib"/{itcl*,tcl*,tk*,thread*,libtcl*,libpython*,pkgconfig} \
      "$LIB"/{idlelib,tkinter,turtledemo,ensurepip,lib2to3,config-3.12-darwin,EXTERNALLY-MANAGED} \
      "$LIB"/lib-dynload/_tkinter* "$LIB"/site-packages/pip "$LIB"/site-packages/pip-*
    find "$RT/python/bin" -mindepth 1 ! -name python3 ! -name python3.12 -delete
    find "$RT" -depth -type d \( -name __pycache__ -o -name tests -o -name test \) -exec rm -rf {} +
    # Bytecode now, so the signed app never needs to write it. Unchecked hashes survive zip and copy.
    "$PY" -m compileall -q -j0 --invalidation-mode unchecked-hash "$LIB" >/dev/null || true
    touch "$RT"
  fi

  echo "Copying the runtime and server..."
  RES="$APP/Contents/Resources"
  ditto "$RT" "$RES/runtime"
  mkdir -p "$RES/server/webapp" "$RES/server/bench" "$RES/server/guidance"
  cp "$ROOT/webapp/app.py" "$ROOT/webapp/processing.py" "$RES/server/webapp/"
  cp -R "$ROOT/webapp/static" "$RES/server/webapp/"
  cp "$ROOT/bench"/{edit,edit_cases,clean,turntable}.py "$RES/server/bench/"
  [[ -f "$ROOT/bench/turntable_calib.json" ]] && cp "$ROOT/bench/turntable_calib.json" "$RES/server/bench/"
  cp "$ROOT/guidance/guidance.py" "$RES/server/guidance/"
  "$RES/runtime/python/bin/python3" -m compileall -q --invalidation-mode unchecked-hash "$RES/server" >/dev/null

  echo "Signing the bundled Python (ad hoc, inside out)..."
  # Every .so and .dylib first, then the interpreter. Library validation is off for it because
  # ad hoc signatures have no team ID, so the hardened runtime would refuse to load the packages.
  find "$RES/runtime" -type f \( -name '*.so' -o -name '*.dylib' \) -print0 \
    | xargs -0 -n 64 -P 8 codesign --force --sign - --timestamp=none 2>"$SCRATCH/sign.log"
  codesign --force --sign - --timestamp=none --options runtime \
    --entitlements "$HERE/Resources/Python.entitlements" "$RES/runtime/python/bin/python3.12"
fi

echo "Signing (ad hoc, hardened runtime)..."
# A fixed designated requirement keeps the macOS privacy answers (Camera, Documents) across rebuilds.
# Plain ad hoc signing ties them to the binary hash, so every build would ask again.
# No --deep: it would re-sign the bundled Python with the app's entitlements.
codesign --force --sign - --options runtime \
  --requirements '=designated => identifier "com.nigel.caddiy"' \
  --entitlements "$HERE/Resources/CADDIY.entitlements" "$APP"
codesign --verify --deep --strict "$APP"

if (( BUNDLE )); then
  DIST="$HERE/dist"
  NAME="$APP_NAME-$VERSION-arm64"
  mkdir -p "$DIST"
  rm -f "$DIST/$NAME.zip" "$DIST/$NAME.dmg"
  ditto -c -k --keepParent "$APP" "$DIST/$NAME.zip"
  STAGE="$(mktemp -d)"
  ditto "$APP" "$STAGE/$APP_NAME.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -format ULMO "$DIST/$NAME.dmg"
  rm -rf "$STAGE"
  echo "Packed $DIST/$NAME.zip and $NAME.dmg"
fi

echo "Built $APP"
(( OPEN )) && open "$APP"
exit 0
