# CADDIY design rebuttal

Written 2026-10-30. This answers `DESIGN_CRITIQUE.md` item by item. No source file was edited.

I re-checked the code claims I could have disputed. All held:
- `ViewerScene.swift` lines 63 and 69 add the key, fill and rim lights to `yawNode`. Image-based light fixed in world space would lose that.
- `ViewerScene.swift` line 129 assigns one shared `material` to every node.
- `ScanView.swift` line 302 has `.aspectRatio(16 / 9, contentMode: .fit)`. My P4 step 1 targeted the wrong line.
- `webapp/processing.py` line 4 says video to mesh does not exist yet, and line 31 is `time.sleep(3)`.
- `Theme.swift` lines 161 and 196 already darken buttons on press.

The cross-cutting points are right. I concede all five:
1. P6 and the hand-off dress up a step that does not happen. Dramatising a 3 second fake step in a venture demo is a credibility risk.
2. The scan screen has no pose, no "centred" field and a 98° orbit error on real clips. Visuals that imply spatial knowledge would lie.
3. About 20 blind tests at n=5 were not budgeted, and several pass marks were noise. Grep counts reward refactors nobody sees.
4. The user is the judge. A before and after contact sheet plus hard gates is the right method.
5. Stacking sweep, ghost, stretch, chip and beam on one edit rebuilds the v1 clutter. One motion per event.

Tally: CONCEDE 40, REVISE 2, DEFEND 0. One sub-point inside P3 is defended with the critique's own test data.

## CHANGE verdicts (18)

| Item | Answer | Notes |
|---|---|---|
| Plan 0 harness | REVISE | Accept the slim version: demo states, appearance switch, window-only capture, fixed size, worst-pixel WCAG, `frameMs` on the oldest Mac available. Drop `design_metrics.swift` extras, `borderLines`, `motionLiterals` and all people tests. Keep `CADDIY_SLOWMO`, since P3 survives and the critique made it conditional on that. Output is one contact sheet per change for the user. 1 day. |
| P1 studio stage | CONCEDE | Rotate the environment with yaw via `lightingEnvironment.contentsTransform`, or keep a weak key light on `yawNode`. Cut SSAO. Floor reflection at 0.05 or off. Tune on `mug_heavy_clean.stl`. 2.5 days. |
| P2 palette | CONCEDE | Shoot default blue accent beside signal before committing. Default blue (hue about 211°) and 3CCFDD (about 185°) are only about 26° apart, so a clash is likely. Tint the viewer toggles with signal, or move signal greener. Keep hairlines in light mode. Use elevation steps in dark only. 1.5 days. |
| P3 reveal sweep | REVISE | Accept both bugs and the fixes: `castsShadow` off during the sweep, a material copy per node, and a direction flag from `CADApp` into `CADViewer`. Cap at 0.6 s and remove `pulse()`. **Defended point:** keep the old mesh above the plane, opaque and not a translucent ghost. The critique's own test shows 29,636 visible pixels at u = 0, all of them shadow, so without the old mesh the model vanishes at the start of every edit. For a small edit like "add a hole" that reads as the model disappearing. An opaque old mesh with the inverse discard has no sort problem, since it is not translucent. It needs the per-node material copy the critique already requires. Two meshes cost 2.4 to 2.7 ms per frame [critique, tested]. The look itself is unverified until rendered. +0.25 day, 2.75 days. |
| P4 viewfinder | CONCEDE | Use aspect fit with a blurred fill behind it, or fill only when aspects are within 15%. Hide the panel while recording. Keep the shutter and Space. Use a flat, larger ring in signal. Cut the brackets, tilted ring and comet. Gate: one real scan with the Mac camera and one with an upright iPhone first. 2 days. |
| P5 first run | CONCEDE | Bundle one real scan, chosen with the user, from a rendered still. Put the text on a solid panel beside the stage. Tips one click away. Reduce Motion stops the spin via `applySpin`. 2 days plus the sample choice. |
| P7 ghost and deltas | CONCEDE | Keep the delta chip and count-up only. 0.5 day. |
| P8 motion and rail | CONCEDE | The grep baseline measured a refactor. Add only the `spatial` spring. Cut the step rail. 0.25 day. |
| Bed outline | CONCEDE | Use the same 250 mm constant the edit refusal uses. 0.5 day. |
| Segment completion pulse | CONCEDE | Scale only, no glow, off with Reduce Motion. |
| Complete moment | CONCEDE | Ring colour change and Finish button only. |
| Dark glass HUD | CONCEDE | Material over at least a 40% black underlay, solid with Reduce Transparency, gated on a white-table frame. |
| Applying state | CONCEDE | Model visible and dimmed, capsule and timer, no beam. 0.5 day. |
| App icon | CONCEDE | Flat redraw in `make_icon.swift`. 0.5 day. |
| Dark as hero | CONCEDE | Test both modes on the real projector, then pick. |
| Shadows over borders | CONCEDE | Dark mode only. |
| Save confirmation | CONCEDE | `.contentTransition(.symbolEffect(.replace))` to a checkmark. 0.25 day. |
| Symbol effects | CONCEDE | `.bounce` on a completed step only. |

## CUT verdicts (24)

All 24 conceded. One line each on why the objection holds.

| Item | Answer | Why the cut is right |
|---|---|---|
| P6 processing | CONCEDE | It shows the student's frames, then a canned cup. Replace it with the stage gradient behind the existing spinner, 0.25 day. |
| Material presets | CONCEDE | It adds a menu, and the PLA map carries a moiré risk. |
| Fresnel rim | CONCEDE | Scans have holes, and the rim makes them glow. |
| View cube | CONCEDE | It duplicates Reset view and the arrow keys. |
| Wireframe ghost | CONCEDE | `ghost_lines.png` shows haze at 50k triangles. |
| Scale stretch | CONCEDE | `setModel` re-centres every mesh, so the stretch would be wrong. |
| SF Mono dimensions | CONCEDE | `.monospacedDigit()` already exists. |
| Wordmark | CONCEDE | I called it taste myself. |
| Scan beam | CONCEDE | REC already answers "is it recording". |
| Directional chevrons | CONCEDE | No pose data reaches the Mac. |
| Scan to Process hand-off | CONCEDE | A fragile transition into a 3 second screen. |
| Process to Edit shared stage | CONCEDE | View lifetime refactor before a demo. |
| Staggered first entrance | CONCEDE | Seen once, taste. |
| History thumbnails | CONCEDE | Rows already say what changed. |
| Empty plinth | CONCEDE | Rarely seen, and `dropHint` exists. |
| History before first change | CONCEDE | It duplicates the chips. |
| Splash | CONCEDE | Animation on a start path that can fail. |
| Native inspector | CONCEDE | It risks the 1.4x layout for a subtle look. |
| Press scale 0.96 | CONCEDE | Mac buttons darken on press, and `Theme.swift` lines 161 and 196 already do. I applied a web rule to a Mac app. |
| Toggle icon cross-fade | CONCEDE | `.symbolEffect(.replace)` already exists. |
| Hover preview | CONCEDE | Inconsistent across chips, 1.5 days. |
| Orbit snapping | CONCEDE | Fights free orbit, no haptics on mice. |
| Sound set | CONCEDE | System sounds already play. |
| Three custom symbols | CONCEDE | SwiftPM symbol loading is unverified, and it costs 1.5 days. |

## Final list, ranked

The judge is the user, using one light and dark contact sheet after each rank. The stop rule stays: if ranks 2 and 3 show no clear gain to the user, stop polishing and go back to reconstruction and real-camera work.

| Rank | Item | Effort |
|---|---|---|
| 1 | Slim harness: demo states, window capture, slow-mo, WCAG and `frameMs` gates (do first) | 1 d |
| 2 | P1 core: environment light rotated with yaw, gradient backdrop, fading grid, 250 mm bed outline | 3 d |
| 3 | P2 core: tokens, dark elevation steps, signal checked against default blue, green split from signal, light hairlines kept | 1.5 d |
| 4 | P5: first run on the stage with a chosen, bundled real scan | 2 d + sample |
| 5 | P3: reveal sweep with the shadow fix, per-node materials, direction flag, opaque old mesh above the plane | 2.75 d |
| 6 | Delta chip, numericText, display numerals | 1 d |
| 7 | Applying state keeps the model visible | 0.5 d |
| 8 | P4 trimmed, only after a real camera run with a Mac camera and an iPhone | 2 d |
| | **Cut line** | **about 13.75 d** |
| 9 | Quiet headers, concentric radii, one icon weight, save checkmark, scale-only segment pulse, camera state cards | 1.25 d |
| 10 | Flat app icon redraw | 0.5 d |
| 11 | Processing backdrop gradient | 0.25 d |

Changes from the critique's list: the harness moves to rank 1 because it comes first in time. P3 gains 0.25 day for the opaque old mesh. P3 goes below P5 because P5 is the demo's opening frame. P4 drops to rank 8 because it is blocked until the real camera test runs.
