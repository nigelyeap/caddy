#!/bin/zsh
# Builds CADViewer in release, links a tiny runner against it and runs ViewerSelfCheck.
# usage: scripts/viewer_check.sh [--pictures DIR] [file.stl ...]
# With no files it makes samples with make_sample_stls.py and also checks bench/out/*_clean.stl.
set -euo pipefail
cd "${0:A:h}/.."
SCRATCH=.build-viewer
swift build --target CADViewer -c release --scratch-path $SCRATCH
REL=$SCRATCH/release
OUT=${TMPDIR:-/tmp}/cad_viewer_check
mkdir -p $OUT
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
  -I $REL/Modules -I $REL \
  scripts/viewer_check/main.swift $REL/CADViewer.o $REL/CADShared.o \
  -framework SceneKit -framework AppKit -framework SwiftUI \
  -o $OUT/viewer_check
if [[ $# -eq 0 ]]; then
  SAMPLES=$(python3 scripts/make_sample_stls.py "$OUT/samples")
  set -- --pictures "$OUT/pictures" "$SAMPLES"/*.stl ../bench/out/*_clean.stl
fi
rc=0
/usr/bin/time -l $OUT/viewer_check "$@" 2> $OUT/time.txt || rc=$?
grep -E "real|maximum resident" $OUT/time.txt
echo "pictures and logs: $OUT"
exit $rc
