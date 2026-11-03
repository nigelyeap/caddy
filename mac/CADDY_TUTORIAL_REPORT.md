# Caddy tutorial: report

Written 2026-10-31. Nothing was committed or pushed.

## What was built

- Caddy art in the app. The 11 poses are now transparent 400 px cutouts made from the 200 px source PNGs. Point left is point right mirrored in code.
- `CaddyView`, a SwiftUI view with a pose, a size that follows the text size, hidden from VoiceOver unless it is given a label. An optional idle bob is off by default and always off with Reduce Motion.
- An About window with the logo pose (CADDY menu, About CADDY).
- A new app icon: the neutral logo on a plain white rounded square. The soft blue tile is still there behind one switch (see Icon).
- An in-app tour with 12 steps. The screen dims and a hole shows the real control. Caddy talks in a bubble with Back, Next, Skip tour, Skip this step and a progress bar ("5 of 12").
- Skip tour and Escape ask first. Caddy says "Leave the tour?" with Keep going and Leave. Escape on that question keeps going. No thanks on the welcome step ends it at once, since the tour has not started.
- Do-it-yourself steps move on when the app state changes, so menu items and shortcuts count too. Look-only steps use Next.
- The scan step uses the practice clip (`PreviewScanSource`). No camera and no scanner are needed.
- If contact with the helper is lost, the tour pauses with the sleepy pose. It comes back on reconnect.
- A failed edit or a failed process shows a sad line with a way forward.

## Steps

Cut from 25 to 12 on 2026-10-31. The old steps and their tests were deleted.

| # | Screen | What |
|---|---|---|
| 1 | First run | Welcome offer, Yes please or No thanks |
| 2 | First run | Start scanning (do it) |
| 3 | Scan | Use the sample model (do it). Caddy says the scanner is not here yet. |
| 4 | Process | Status, moves on by itself |
| 5 | Edit | Drag to turn the model (do it) |
| 6 | Edit | The viewer buttons: spin, grid, triangles, reset, picture. One hole, try any, then Next. |
| 7 | Edit | Tap Taller (do it). The line says you can type ideas too. |
| 8 | Edit | History list with Undo (do it) |
| 9 | Edit | Save STL (look only, Next) |
| 10 | Edit | Open in Tinkercad or FreeCAD (look only, Next) |
| 11 | Edit | More tips: Command Z, text size in the View menu, Command comma for Settings |
| 12 | Edit | Cheer, Done |

Steps 9 and 10 show the hole and ring, but clicks in the hole do not reach the button. So the tour never opens a save panel or a browser. Command S still works if the kid presses it.

## Files

New:
- `Sources/CADApp/CaddyView.swift`
- `Sources/CADApp/AboutView.swift`
- `Sources/CADApp/Tutorial.swift`
- `Sources/CADApp/TutorialOverlay.swift`
- `Sources/CADShared/TutorialTarget.swift`
- `Sources/CADApp/Resources/Caddy/*.png`
- `Resources/caddy_logo_1024.png`
- `Tests/CADAppTests/TutorialTests.swift`

Changed:
- `Package.swift`: the Caddy resources and the test target.
- `Resources/make_icon.swift`
- `build_app.sh`: the icon cache now also checks `caddy_logo_1024.png`, `mascot/poses_ai/logo_neutral.png` and `mascot/poses_ai/logo_neutral_1024.png`.
- `Sources/CADApp`: `CADApp.swift`, `RootView.swift`, `Screens.swift`, `EditScreen.swift`, `Integration.swift`. `AppModel.swift` is back to its old save code (the save counter went with the old Save step).
- `Sources/CADViewer`: `ModelViewer.swift`, `ViewerUI.swift`
- `Sources/CADScan/ScanView.swift`
- `scripts/shots.sh`

No webapp change.

## How to launch it

- On a fresh install, Caddy offers the tour on the first-run screen.
- Help, Show Me Around starts it again at the right step for the current screen.
- Escape and Skip tour ask "Leave the tour?". Return presses Next.
- Harness: `CADDY_TUTORIAL=<step number, id or off>`. Add `CADDY_TUTORIAL_DEBUG=1` to log the hole and bubble rects, or `CADDY_TUTORIAL_ASK=1` to open on the leave question.
- Shots: `TUTORIAL_STEPS="1 3 7" TUTORIAL_SIZES="large largest" scripts/shots.sh ../samples/mug.stl <outdir>`. Add `TOUR_ASK=1` for the leave question, `APPEARANCE=dark` for dark mode.

## What was verified by running it

Second pass (12 steps), 2026-10-31:
- `./build_app.sh debug` builds. `swift test` passes: 16 tutorial tests plus the existing suites. New tests check the step count and order, that Save STL and Open in are look-only, and that no welcome shows before a saved model has loaded.
- All 12 steps captured in light mode at Large and Extra large text. Steps 1, 5, 7, 9 and 12 in dark mode. The leave question at both sizes. No overlap and nothing out of bounds in any layout log. I looked at steps 1, 2, 6, 8, 9 and 10, the leave question and dark step 9.
  - Shots are in `/private/tmp/claude-501/-Users-nigelyeap/16bf9df3-205a-49d4-a3cf-165fc42d9277/scratchpad/qa2/light`, `/private/tmp/claude-501/-Users-nigelyeap/16bf9df3-205a-49d4-a3cf-165fc42d9277/scratchpad/qa2/dark` and `/private/tmp/claude-501/-Users-nigelyeap/16bf9df3-205a-49d4-a3cf-165fc42d9277/scratchpad/qa2/ask`.
- The app and helper were stopped and the settings put back after the runs.

First pass (25 steps):
- Helper down: the helper was killed mid-tour. The tour paused and came back. Shots are in `/private/tmp/claude-501/-Users-nigelyeap/16bf9df3-205a-49d4-a3cf-165fc42d9277/scratchpad/tutorial/down`.
- The tour never shows over the starting screen.
- Quick changes use the canned path, so they work with no Claude key.
- Bugs fixed during QA: a failed process said "building", a Return press could send an empty change, Back to scan could not be clicked during a failed process, and a timing race in the nudge line.

## Not verified

- Real clicks inside the hole, a click on the dim area, and Escape and Return as real key presses. No clicks were sent to the app. The leave question was checked by screenshot, and its buttons were not clicked.
- The welcome flash fix is checked by a unit test. A real launch with a saved model was not run.
- VoiceOver, Reduce Motion and Reduce Transparency were checked in code only.
- Step 4 moves on too fast to screenshot. Its layout log line is fine.
- A Claude edit that takes a long time with a key set was not run.

## Known gaps

- The toolbar and menus are not dimmed.
- If a target in the inspector is scrolled out of view, it gets no hole. Skip this step still works.
- At Extra large text the step 5 bubble sits inside the top of the big viewer hole. This is allowed for large targets.
- Fixed in this pass: the welcome flash with a saved model (the tour now waits for the first status reply), Escape with no question, and the real save panel in the Save step.

## Icon

- The default is no tile: the logo on a plain white rounded square with a faint edge, so it still shows on a white Finder window. The square takes the colour of the logo corner, so the logo's near-white backdrop has no seam.
- `Resources/make_icon.swift` has one switch at the top: `let blueTile = false`. Set it to `true` for the old soft blue tile (`#BFE0F7`), which uses the see-through `Resources/caddy_logo_1024.png`.
- Logo for the white square: `mascot/poses_ai/logo_neutral_1024.png` when it exists, else `mascot/poses_ai/logo_neutral.png`. `build_app.sh` redraws the icon when either file changes.
- With the 200 px logo the icon is soft at 1024 px. It should be sharp once the 1024 px logo lands.
- Side by side of both versions: `/private/tmp/claude-501/-Users-nigelyeap/16bf9df3-205a-49d4-a3cf-165fc42d9277/scratchpad/qa/icon/both.png` (the white one there is from before the logo was made larger).

## Questions for you

1. Do you want the missing poses (oops, point up, wink)?
2. Should step 11 (More tips) stay, or should the tour end at step 10?
