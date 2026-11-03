# Caddy tutorial: plan

Written 2026-10-31. Plan only. No source file was edited.

Caddy is a mascot who walks a kid through the app once. The screen dims and a bright hole shows the real button. Caddy talks in a speech bubble next to it.

## 1. Goals and non-goals

### Goals
- A kid aged 8 to 14 finishes the tutorial able to open a model, make one change, undo it, and save an STL.
- The tutorial points at the real UI, not pictures of it. The kid presses the real buttons.
- It works today with no probe. It uses the sample model and a practice clip.
- It runs once by itself, and again from the Help menu.
- It never traps the kid. Skip is always visible, and Escape always skips.

### Non-goals
- No teaching of scan technique. The scan tips on the scan screen already do that.
- No branching lessons, quizzes, scores, badges or confetti. The design ruling bans confetti and added sounds.
- No voice for Caddy in this version.
- No tutorial in Settings, the save panel or the Tinkercad and FreeCAD sheets.
- No final mascot art. Caddy is a placeholder view with three faces until a design is picked.
- No real scan in the tutorial until the probe exists.

## 2. The step script

12 steps. "Next" means the bubble has a Next button and Return presses it. "Action" means there is no Next. The step moves on when the app state changes, so a menu item or shortcut counts too.

The first two steps sit on the first-run screen, which is part of Scan.

| # | Screen | Target (real view) | Caddy says | Face | To move on |
|---|---|---|---|---|---|
| 1 | Scan (first run) | None. Bubble in the centre. | "Hi! I am Caddy. Let us make something cool." | happy | Next |
| 2 | Scan (first run) | `FirstRunView` "Start scanning" button | "Tap Start scanning to see how scans work." | pointing | Action: the first-run screen closes (`seenIntro` becomes true) |
| 3 | Scan | The camera area in `ScanView` (`cameraArea`), showing the practice clip | "This box shows what the probe sees." | pointing | Next |
| 4 | Scan | "Start scan" button in `ScanView.controlBar`, dimmed for now | "Later, press this and walk around your object." | pointing | Next |
| 5 | Scan | "Use the sample model" chip in `ScanSidePanel` | "No probe today. Tap here to use a sample." | pointing | Action: `model.step` becomes `.cleanUp`. Shortcut hint: Shift Command S. |
| 6 | Process | The Status list in `ProcessingView.working` | "I am building the model. This takes a few seconds." | thinking | Auto: `model.step` becomes `.edit` |
| 7 | Edit | The 3D viewer (`EditScreen.viewer`) | "Here is your model! Drag it to spin it." | happy | Next |
| 8 | Edit | The "Taller" quick-change chip | "Tap Taller to make it grow." | pointing | Action: an edit lands (`revision` goes up and `lastChangeWasEdit` is true). Hint: Change menu, Make 20% taller. |
| 9 | Edit | The 3D viewer | "Look! Your model changed." | happy | Next |
| 10 | Edit | The Undo chip in the History header | "Oops? Tap Undo to go back one step." | pointing | Action: the redo list grows by one. Hint: Command Z. |
| 11 | Edit | The "Save STL…" button | "Tap Save STL to keep it for printing." | pointing | Action: a save finishes (new `saveCount` goes up). Hint: Command S. |
| 12 | Edit | The "Describe a change" text field | "You did it! Type your own idea here next." | happy | Done button. Marks the tutorial as seen. |

Extra lines inside a step. Each one replaces the main line for a moment.

| When | Caddy says | Face |
|---|---|---|
| Step 6 still showing after 20 s | "Still building. Thanks for waiting!" | thinking |
| Step 8 while the edit runs | "I am working on it. Hold on!" | thinking |
| Step 8 after 15 s of edit | "This one takes a while. I am still going." | thinking |
| Step 8 if the edit fails | "That did not work. Tap Taller again." | thinking |
| The kid clicks the dim area | "Tap the bright spot." (2 s, then back) | pointing |
| Lost contact with the helper | "I lost my helper. Wait a moment." | thinking |

Notes on the script:
- Step 8 accepts any quick change or typed change. Step 9 says "changed" for that reason.
- After step 10 the model is back to the original. Step 11 saves that. This matches the goal and keeps the steps simple.
- Step 12 points at the text field so the kid learns typing exists without a separate step.
- Every bubble also shows "3 of 12" in caption text and a Skip link.

## 3. Technical design

### Files
- New `Sources/CADApp/Tutorial.swift`. Holds the step table, the `Tutorial` model, the spotlight overlay, the bubble and the placement function.
- New `Sources/CADApp/CaddyView.swift`. The character view. Swapping the mascot design touches only this file.
- `Sources/CADShared/Theme.swift` (or a new small file in CADShared). The `TutorialTarget` enum and the `.tutorialTarget(_:)` modifier. It must live in CADShared because the Start scan button is inside CADScan, which cannot see CADApp.
- Small edits in `RootView.swift`, `CADApp.swift`, `AppModel.swift`, `Screens.swift`, `EditScreen.swift`, `ScanView.swift`, `Integration.swift`.
- New `Tests/CADAppTests/TutorialTests.swift` and one `testTarget` line in `Package.swift`.

### Highlighting real views
- `TutorialTarget` is an enum: `startScanning`, `cameraArea`, `startScan`, `sampleChip`, `processStatus`, `viewer`, `tallerChip`, `undo`, `save`, `changeField`.
- `.tutorialTarget(.undo)` adds an `anchorPreference` with key `TutorialAnchors: [TutorialTarget: Anchor<CGRect>]`. Values merge by dictionary union.
- `RootView` adds `.overlayPreferenceValue(TutorialAnchors.self)` on the content area. Inside, a `GeometryReader` turns the current step's anchor into a rect with `proxy[anchor]`.
- The spotlight is one `Path`: the full rect plus a rounded rect hole (target rect plus 6 pt, corner `Theme.corner`). It is filled with `FillStyle(eoFill: true)`. A 3 pt `Theme.accent` ring strokes the hole.
- Hit testing uses `.contentShape(spotlightPath, eoFill: true)`. Clicks in the dim area hit the overlay and trigger the nudge. On action steps, clicks in the hole fall through to the real button. On Next steps the overlay also covers the hole, so the highlighted view is look-only.
- The overlay sits on the content, not the toolbar. Toolbar items are hosted outside the content tree, so they cannot be targets. The script avoids them.

**Risk to check first.** `HSplitView` and `ScrollView` are backed by AppKit views. Anchor preferences may not cross them. If the spike shows they do not, fall back to `onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }` on each target, written into `tutorial.frames`. The overlay subtracts its own global origin. `onGeometryChange` is back-deployed to macOS 13 with the Xcode 16 SDK. Confirm that in the spike too.

### Where state lives
- `@MainActor final class Tutorial: ObservableObject`, owned by `CADDYApp` as a `@StateObject` and passed to `RootView` and `AppCommands`. Same pattern as `AppModel`.
- It holds `index: Int?` (nil means off), `entry: Snapshot` (the app state when the step began), `nudgeUntil: Date?` and `paused: Bool`.
- The step table is a static array of `Step(screen, target, line, face, advance)`. `advance` is `nil` for Next steps, or a closure `(entry, now) -> Bool`.
- Seen state is `@AppStorage("tutorialDone")`. Nothing else is stored.

### Advancing on real actions
- `AppModel` gets two small additions. One is `@Published private(set) var saveCount = 0`, bumped in `save()` after the copy succeeds. The other is a computed `var snapshot: Snapshot` (Equatable) built from fields that already exist: `step`, `revision`, `lastChangeWasEdit`, `state?.versions.count`, `state?.redo.count`, `isEditing`, `connected`, `note?.kind`, plus `saveCount`.
- `RootView` adds one `.onChange(of: model.snapshot) { tutorial.check($1, screen: screen) }`. `screen` is derived from `model.step` and `seenIntro` (first run, scan, process, edit).
- `check` does three things in order. If the screen is not the step's screen, it jumps to the first step for the current screen. If the step has an `advance` rule and it returns true, it moves on. Otherwise it updates the extra line, for example "working on it" when `isEditing` turns true.
- Because the rules read state, the menu items and shortcuts (Shift Command S, Command Z, Command S, the Change menu) advance the tutorial too. No click tracking is needed.

### Scan screen with no probe
- While the tutorial is on a Scan step, `ScanStep` passes a `PreviewScanSource()` instead of `sharedCamera`, keyed with `.id(tutorialOnScan)` so the `StateObject` is rebuilt. This shows the "Practice clip" of a turning box. It needs no camera and no permission prompt, and every run looks the same.
- While on steps 3 and 4, `ScanStep` gets `.disabled(true)`. This stops Space from starting a recording. The side panel stays enabled, so step 5 works.
- When the probe source exists, it replaces the practice clip only outside the tutorial. The tutorial keeps the practice clip until we decide otherwise (open question 6).

### Keyboard focus conflicts
- `RootView` sets `editFocused = true` when the Edit screen opens. While the tutorial is on a Next step, skip that, or Return would go into the text field and send an empty change.
- `FirstRunView` uses `.keyboardShortcut(tutorialOnStep1 ? nil : .defaultAction)` on Start scanning, so Return presses Next on step 1.

### Bubble placement and window resize
- Anchors resolve on every layout pass, so the hole follows a live resize, a split view drag, a banner appearing and a text size change with no extra code.
- `placeBubble(target: CGRect?, bubble: CGSize, in bounds: CGRect) -> CGRect` is a pure function. It tries right of the target, then left, below, above. It takes the first side where the whole bubble fits inside `bounds` with a 16 pt margin. If none fits, it uses the corner farthest from the target. With no target it centres.
- The bubble is `card()` style, max width `320 * textScale`, capped at the window width minus 32. The line uses `.themeFont(.title)`.
- Caddy sits on the bubble edge nearest the target. The pointing face is mirrored when the target is on the left.

### Targets inside scroll views
- The Inspector `ScrollView` gets a `ScrollViewReader`. Each target there also gets `.id(target)`. On step change, `proxy.scrollTo(target)` runs once. Save is in the bottom inset, so it is always on screen.

### Help menu replay
- Add "Show Me Around" to the Help group in `AppCommands`. It sets `tutorial.start(at: screen)`, which picks the first step for the current screen. Disabled while `model.isEditing`. "Show the Intro Again" stays as it is.

### Harness env var
- `CADDY_TUTORIAL=<1..12>` starts at that step and shows the overlay. `CADDY_TUTORIAL=off` never starts it.
- If `CADDY_DEMO` is set and `CADDY_TUTORIAL` is not, the tutorial stays off. The existing `scripts/shots.sh` output does not change.
- Steps 1 and 2 also set `seenIntro = false`. Steps 3 to 5 set it to true.
- In harness mode the overlay prints one line per layout to stderr: `tutorial step=8 hole=... bubble=... overlap=false inBounds=true`. The shots script greps it.
- Text size for a shot run comes from `defaults write com.nigel.caddy textSize largest` before launch. No new env var.
- `shots.sh` gains a loop over `CADDY_TUTORIAL` values, using the existing `SUFFIX` variable for file names.

## 4. Accessibility

- **Reduce Motion.** The hole jumps to the next target with no slide. Faces swap with no crossfade. The nudge only changes the text. Use `Theme.motion(reduceMotion)` everywhere, which already returns nil. Nothing in the overlay loops, with or without the setting.
- **Reduce Transparency.** The dim goes from 0.5 (light) and 0.6 (dark) black to 0.85, so the content behind is barely visible. The bubble is already a solid `Theme.panel`. No materials or blur anywhere.
- **VoiceOver order.** The dim layer is `accessibilityHidden`. The bubble is one container: line, "Step 3 of 12", then Next or Done, then Skip. On step change, focus moves to the bubble with `@AccessibilityFocusState` and the line is posted with `AccessibilityNotification.Announcement`. On Next steps the bubble gets `.isModal`. On action steps it does not, so VoiceOver can reach the real target.
- **VoiceOver on action steps.** The bubble adds `.accessibilityAction(named: "Do it")`. It runs the same call as the target: `useSample()`, `send` with the Taller text, `undo()`, or the save action. The announcement ends with the shortcut, for example "Or press Command Z".
- **Keyboard.** Escape skips (`.keyboardShortcut(.cancelAction)` on Skip). Return presses Next or Done (`.defaultAction`). Action steps show the menu shortcut in the bubble. Full keyboard access is off by default on a Mac, so the shortcuts are the keyboard path.
- **1.4x text.** The bubble grows with `textScale` and wraps. Placement re-runs with the new size. At the smallest window (1024 by 700) and Extra large text, no bubble may overlap its hole or leave the window. The harness line checks this for every step.
- **Light and dark.** Bubble text is `Theme.ink` on `Theme.panel`, which already passes 4.5:1. The ring is `Theme.accent`. The dim is black in both modes. Shots run in both appearances with `CADDY_APPEARANCE`.

## 5. Failure cases

| Case | What happens |
|---|---|
| Target not on screen | Scroll to it first. If the anchor is still missing or outside the bounds after 0.5 s, show the bubble centred with no hole and add a Next button. The kid is never stuck. |
| Kid clicks elsewhere | The dim area eats the click. The bubble shows "Tap the bright spot." for 2 s and the ring pulses once (no pulse with Reduce Motion). Toolbar and menus still work, and a menu action that does the step still counts. |
| Kid does a different action | The rules read state, not clicks. Any change passes step 8. Opening a file instead of the sample passes step 5. Going back to Scan jumps to step 3. |
| Quit mid-tutorial | Only `tutorialDone` is stored, and it is still false. Next launch starts at the first step for the screen the app opens on. The helper often restores the model, so that is usually step 7. |
| No backend at launch | The tutorial waits until the helper first answers. It never shows over `LaunchView`. If the helper fails for good, the tutorial never starts and stays unseen. |
| Lost contact mid-tutorial | `connected` turns false. The tutorial pauses: no hole, thinking face, "I lost my helper. Wait a moment." Skip still works. It resumes when contact returns. If the model was lost, the app goes to Scan and the tutorial goes to step 3. |
| Claude edit takes 40 s | With an API key, the Taller chip goes to Claude and can take 5 to 40 s. Step 8 switches to the thinking face and "I am working on it. Hold on!". At 15 s it says "This one takes a while. I am still going." The existing dim and timer on the viewer stay visible. No Next appears, so the kid cannot skip past a running edit. |
| Edit fails | `note.kind` is `.bad` and no new revision appears. Step 8 says "That did not work. Tap Taller again." The app's own error note stays visible. |
| Save panel cancelled | `saveCount` does not change. Step 11 stays. The save panel is its own window, so the overlay does not cover it. |
| Escape pressed by accident | The tutorial ends and is marked seen. Help, Show Me Around brings it back. |

## 6. Build order

| Order | Work | Effort | Check that proves it |
|---|---|---|---|
| 0 | Spike: anchors through `HSplitView`, the Inspector `ScrollView` and its bottom inset, and `ScanView`. Debug overlay draws a red box on each target. Also confirm `@testable import` of the CADApp executable target works. | 0.25 d | Screenshot at 1280 by 800 and 1024 by 700 shows red boxes exactly on Taller, Undo, Save, the viewer and the sample chip. Decides anchors or `onGeometryChange`. |
| 1 | `TutorialTarget` and modifier in CADShared. Tags on all 10 targets. `.id` and `ScrollViewReader` in the Inspector. | 0.5 d | Same debug shot with all 10 boxes, in light and dark. |
| 2 | Spotlight path, ring, hit testing, bubble, `placeBubble`. | 1 d | Unit test: `placeBubble` keeps the bubble inside bounds and off the hole for every target rect from the spike, at scale 1 and 1.4, at 1024 by 700. Manual: clicking the hole on an action step presses the real button. Clicking the dim does not. |
| 3 | `CaddyView` placeholder with happy, thinking and pointing faces. Mirror for left targets. | 0.25 d | One shot per face in light and dark. |
| 4 | Step table, `Tutorial` model, `Snapshot`, `saveCount`, the `onChange` hook, extra lines and timers. | 1 d | Unit tests: 12 steps, every line 12 words or fewer, each advance rule passes and fails on hand-built snapshots, screen change jumps to the right step. Manual run from step 1 to 12 with no API key. |
| 5 | Practice clip on Scan steps, disabled scan controls on steps 3 and 4, focus and default-action fixes. | 0.25 d | Shot of step 3 shows the turning box and no camera prompt on a Mac with camera access never granted. Pressing Space on step 4 does not start a recording. Return on step 7 presses Next and sends no change. |
| 6 | Persistence, Help menu replay, `CADDY_TUTORIAL`, stderr line, `shots.sh` loop. | 0.5 d | `shots.sh` writes 12 steps by 2 modes by 2 text sizes, 48 PNGs. Every stderr line says `overlap=false inBounds=true`. A second run differs by under 0.5% per image. Existing shots without `CADDY_TUTORIAL` are unchanged. |
| 7 | Accessibility pass: VoiceOver focus and announcements, Do it action, Reduce Motion, Reduce Transparency. | 0.75 d | With VoiceOver on, steps 1 to 12 complete using only VO keys and the Do it action. With Reduce Motion on, two frames 0.5 s apart during a step change are identical. With Reduce Transparency, the dim measures 0.85 opacity in the shot. |
| 8 | Failure cases: lost contact pause, edit failure line, missing target fallback, 15 s and 20 s lines. | 0.5 d | Kill the helper on step 8: the pause bubble shows, then resumes on restart. Run with an API key and time the Taller edit: the 15 s line appears and no Next shows. Shrink the window until Undo scrolls away: the tutorial scrolls to it. |
| 9 | Copy check with two or three kids aged 8 to 10. Fix any line they stumble on. | 0.5 d plus scheduling | Each kid finishes all 12 steps without adult help and then saves a second change on their own. |
| | **Main line total** | **5.5 d** | |
| 10 | **Blocked on hardware.** Probe wording for steps 3 and 4, a target for the probe status if the probe UI adds one, and an optional real-scan path instead of the sample. | 0.5 d after the probe works | One scan with the real probe goes through steps 3 to 6 and lands on Edit. |
| 11 | **Blocked on the mascot pick.** Real Caddy art in `CaddyView`. | 0.5 d after the pick | The face shots from step 3 rerun with the real art, readable at 1.4x in light and dark. |

## 7. Open questions

1. Which mascot design? Candidates are in `mac/mascot/candidates`. The placeholder ships until then.
2. With an API key, the Taller chip goes to Claude and can take 40 s. Should the tutorial force the canned fast path instead? That needs a small flag in the webapp edit endpoint.
3. On a shared classroom Mac, should every new account see the tutorial, or should a teacher turn it on and off in Settings?
4. Should Escape skip at once, or ask "Stop the tour?" first?
5. Step 11 opens a real save panel. Is that fine for kids, or should the tutorial accept the click without a real save?
6. Once the probe works, should the tutorial use a real scan, or keep the sample so it always takes under a minute?
7. Is "Show Me Around" the right Help menu name?
