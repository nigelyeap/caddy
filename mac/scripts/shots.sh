#!/bin/zsh
# Harness: launches build/CADDY.app in light and dark with a demo mesh and saves window-only PNGs.
# usage: scripts/shots.sh [mesh.stl] [outdir]   (build first: ./build_app.sh debug)
set -euo pipefail
cd "${0:A:h}/.."
MESH=${1:-../samples/mug.stl}; OUT=${2:-${TMPDIR:-/tmp}/caddy_shots}; mkdir -p $OUT
WINID=$OUT/winid; swiftc -O scripts/winid.swift -o $WINID 2>/dev/null
quit_app() {  # waits until the app is gone, so its last settings write lands before ours
  osascript -e 'tell application "CADDY" to quit' 2>/dev/null || true; sleep 2; pkill -x CADDY 2>/dev/null || true
  for i in {1..20}; do pgrep -x CADDY >/dev/null || break; sleep 0.5; done; sleep 1
}
snap() {  # snap <png>
  for i in 1 2 3 4 5 6; do
    osascript -e 'tell application "CADDY" to activate' 2>/dev/null || true
    id=$($WINID)
    [[ $id != 0 ]] && screencapture -x -o -l "$id" "$1" 2>/dev/null && { echo "$1"; return 0; }
    sleep 3
  done
}

# Caddy tour: TUTORIAL_STEPS="1 3 7 taller" takes one picture per step and text size, then puts the settings back.
# Layout lines from the app go to $OUT/tour.log. Unset, the script works as before.
if [[ -n ${TUTORIAL_STEPS:-} ]]; then
  # These runs change the text size, the intro flag and the window frame. Put each back, or remove it if it was not set.
  KEYS=(textSize seenIntro "NSWindow Frame main")
  typeset -A OLD
  for k in $KEYS; do OLD[$k]=$(defaults read com.nigel.caddy "$k" 2>/dev/null || echo __unset__); done
  restore() {
    quit_app
    for k in $KEYS; do
      if [[ ${OLD[$k]} == __unset__ ]]; then defaults delete com.nigel.caddy "$k" 2>/dev/null || true
      elif [[ $k == seenIntro ]]; then defaults write com.nigel.caddy "$k" -bool $( (( OLD[$k] )) && echo true || echo false )
      else defaults write com.nigel.caddy "$k" "${OLD[$k]}"; fi
    done
  }
  trap restore EXIT
  : > $OUT/tour.log
  for size in ${=TUTORIAL_SIZES:-large largest}; do
    for step in ${=TUTORIAL_STEPS}; do
      quit_app
      defaults write com.nigel.caddy textSize $size
      rm -f $OUT/tour_run.log
      open -n build/CADDY.app --stderr $OUT/tour_run.log --env CADDY_TUTORIAL=$step --env CADDY_TUTORIAL_DEBUG=${TOUR_DEBUG:-} ${TOUR_ASK:+--env} ${TOUR_ASK:+CADDY_TUTORIAL_ASK=1} --env CADDY_APPEARANCE=${APPEARANCE:-light}
      sleep ${WAIT:-16}
      snap "$OUT/tour_${step}_${size}.png" || echo "no window for step $step"
      grep '^tutorial ' $OUT/tour_run.log | sed "s/^/size=$size /" >> $OUT/tour.log || echo "size=$size step=$step no layout line" >> $OUT/tour.log
    done
  done
  exit 0
fi
for mode in light dark; do
  pkill -x CADDY 2>/dev/null || true; sleep 2
  CADDY_APPEARANCE=$mode CADDY_DEMO="$PWD/$MESH" open -n build/CADDY.app --env CADDY_APPEARANCE=$mode --env CADDY_DEMO="${MESH:A}" --env CADDY_YAW=${YAW:-0}
  sleep 20
  for i in 1 2 3 4 5 6; do
    osascript -e 'tell application "CADDY" to activate' 2>/dev/null || true
    id=$($WINID)
    [[ $id != 0 ]] && screencapture -x -o -l "$id" "$OUT/edit_${mode}${SUFFIX:-}.png" 2>/dev/null && { echo "$OUT/edit_${mode}${SUFFIX:-}.png"; break; }
    sleep 3
  done
done
pkill -x CADDY || true
