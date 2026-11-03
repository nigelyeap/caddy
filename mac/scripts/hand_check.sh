#!/bin/zsh
# Builds CADGesture and CADViewer, links a small playground app against them and opens it.
# No helper, no uv and no Xcode needed, so it is the quickest way to try hand control.
# usage: scripts/hand_check.sh [file.stl]     (default: the sample mug)
set -euo pipefail
unset DEVELOPER_DIR
cd "${0:A:h}/.."
SCRATCH=.build-hands
swift build --target CADGesture -c release --scratch-path $SCRATCH
swift build --target CADViewer -c release --scratch-path $SCRATCH
REL=$SCRATCH/release
APP=build/HandCheck.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
  -I $REL/Modules -I $REL \
  scripts/hand_check/main.swift $REL/CADGesture.o $REL/CADViewer.o $REL/CADShared.o \
  -framework SceneKit -framework AppKit -framework SwiftUI -framework AVFoundation -framework Vision \
  -o $APP/Contents/MacOS/HandCheck
cp ../samples/mug.stl $APP/Contents/Resources/
# A real app bundle, so macOS asks for the camera in this app's own name.
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>HandCheck</string>
  <key>CFBundleExecutable</key><string>HandCheck</string>
  <key>CFBundleIdentifier</key><string>com.nigel.caddy.handcheck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key>
  <string>The hand playground watches your hand so you can turn the model by pinching.</string>
</dict>
</plist>
PLIST
codesign --force --sign - $APP
echo "built $APP"
if [[ $# -gt 0 ]]; then open $APP --args "${1:A}"; else open $APP; fi
