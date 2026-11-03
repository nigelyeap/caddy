#!/bin/zsh
# Builds CADBackend, then runs an end to end check against the real Python server.
# Uses a fake Claude key and a spare port (default 8765). It replaces the current model with the sample cup.
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${1:-8765}"
swift build --target CADBackend --scratch-path .build-backend
B=.build-backend/debug
mkdir -p "$B/backend_check"
swiftc -I "$B" -I "$B/Modules" "$B/CADShared.o" "$B/CADBackend.o" scripts/backend_check/main.swift \
  -o "$B/backend_check/run" -target arm64-apple-macosx14.0 -swift-version 5
"$B/backend_check/run" "$PORT"
