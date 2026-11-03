# CADDY design: final ruling

Written 2026-10-30. This rules on `DESIGN_REBUTTAL.md`, the author's answer to `DESIGN_CRITIQUE.md`. No source file was edited. New test results come from the same scratchpad harness (`scratchpad/critique`, run with `SWEEP=1`) on the 49,834-triangle `bench/out/mug_heavy_clean.stl`. They are marked **[tested]**.

## 1. The two REVISE items

### Plan 0 harness: ACCEPTED

The slim harness is right. Keeping `CADDY_SLOWMO` is fine because P3 survives. It needs one detail the rebuttal leaves out. The SceneKit durations are literals spread through `ViewerScene.swift`, so slow motion needs one multiplier that every `SCNTransaction.animationDuration` there goes through. That is a few lines.

The `frameMs` gate on "the oldest Mac available" only means something if that Mac is older than the M4. If nobody can borrow one, the report should say "M4 only" and stop there. It should not claim the gate passed.

### P3 opaque old mesh above the plane: ACCEPTED. My critique was wrong here.

The author is right, and the new test backs them. I set up the old mesh to discard below the plane and the new mesh to discard above it, both opaque, each with its own material.

**[tested]** results:
- **No vanish.** With the same mesh as old and new, the visible pixel count stays at 325,963 at every plane height, from u = -1 to u = 1000. Without the old mesh, the earlier test showed the model gone at the start, with only its shadow left.
- **No seam.** For a no-op edit, the composite at mid-sweep differs from a plain render in 0.000% of pixels. There is no z-fighting and no gap at the cut.
- **A real shape change shows a thin ledge at the cut.** See `out/sweep_opaque_taller.png`, for a 25% taller mesh. That ledge reads as the sweep line, which is what the effect is for.
- **Cost is fine.** With two meshes, the median frame is 3.9 ms and p95 is 10.4 ms, under 16.7 ms.

**I also have to correct my own shadow fix, which the rebuttal accepted.** I said to turn `castsShadow` off on the sweeping node. The test shows this also removes the model's shadow on itself, not just on the floor. With the new mesh's shadow off, the end frame differs from a normal render in 22% of pixels for the taller edit and 15% for the shorter one. Most of that is the dark self-shadowed side of the mug lighting up.

The working recipe is this:
- Keep the **old** mesh casting shadows during the sweep. Its shadow falls on the new mesh too, and it matches exactly for small edits (0.00% difference for the no-op case).
- Leave the **new** mesh with `castsShadow` off.
- Swap the two flags when the sweep ends, then remove the old node.

The only pop left is old shadow to new shadow, and its size is the size of the edit. For a big resize it will show. Live with it, or fade the old node's shadow over 0.15 s at the end. Effort stays at 2.75 days.

## 2. Over-concession check and my weakest verdicts

The author conceded 40 of 42 items and defended none. I went back over the verdicts I was least sure of. Four change.

| Item | Was | Now | Why |
|---|---|---|---|
| P3 old mesh above the plane | dropped | **kept, opaque** | Tested above. The author was right and conceded too little. |
| P3 shadow fix | new mesh `castsShadow` off | **old mesh casts, swap at the end** | Tested above. My fix caused a 15 to 22% shading pop on the model. The author accepted it without checking. |
| Bed outline | CHANGE | **CUT** | `rebuildGrid` makes the grid 1.6 times the model footprint, about 144 mm for this mug. A 250 mm outline lands outside the grid and mostly outside the default frame. It would show as stray lines cutting across the stage, which is clutter. The 250 mm limit already reaches the student through the edit refusal. |
| Camera states | KEEP | **CUT** (already built) | `ScanLogic.swift` line 71 already has `notDetermined`, `denied`, `restricted`, `noCamera`, `inUse` and `disconnected`. `CameraStateCard` already renders them. There is nothing left to build. The rebuttal's rank 9 keeps it as work, which double-counts. |
| P8 spatial spring | CHANGE | **CUT** | Its only users were P3 and P4. P3 animates through SceneKit, not SwiftUI, and P4 is blocked. Nothing on the final list uses it. |

One rebuttal suggestion is a step backwards. On P2 the author offers to "move signal greener" to get away from the default blue. Greener cyan is teal, and teal was the v1 accent the user called childish (`DESIGN_NOTES.md`). Both ways out of the blue clash (cyan beside blue, or teal) carry a risk.

**Ruling: drop the custom signal colour and use the system accent as the single highlight.** That means one blue on a default Mac, no clash, nothing kiddy, and less work. Status green stays separate. Covered and missing arcs already differ in shape, so colour-blind users are still covered.

Everything else conceded was conceded for the right reason. I checked the cuts most likely to be over-conceded. Display numerals and the delta chip survive. Press scale was a web idiom (`Theme.swift` lines 161 and 196 already darken on press). The wordmark, splash and history thumbnails are taste or duplication. Quiet headers and concentric radii sit correctly below the line. They are cheap, but none moves the user's verdict.

## 3. Final list checked against the original flaws

- **Cost.** The rebuttal adds up to 13.75 days. After removing the bed outline (0.5 day) and replacing the custom signal colour with the accent (about 0.5 day saved inside P2), the main line is 10.75 days, plus 2 days for P4 once it is unblocked.
- **Clutter.** On an edit, the student sees one sweep plus the delta chip's number ticking. That is one motion and one number. `pulse()` goes. While waiting, the model stays dimmed with a timer and nothing loops. The stage gets richer because of light, not added objects. That answers "too empty" without bringing back v1's clutter.
- **Clash.** P1 needs stage tokens that P2 also defines. Define the stage tokens inside P1 and have P2 adopt them, so the colours are tuned once. Do P1 before P2. P1 is also the biggest visible change, so the stop rule tests the right thing first.
- **Earlier feedback.**
  - Professional: SF type, one accent, a lit stage.
  - Not cluttered: one motion per event, no view cube, no outline.
  - Not kiddy: no teal, no sounds added, no confetti.
  - Not empty: a stage with depth, a real model on the first-run screen.
- **Remaining risk.** P5 cannot start until the user picks a sample scan. Ask for it now, in parallel with the harness.
- **Projector.** Dark versus light for the demo is still a test on the real projector, not a build item.

## 4. Final ranked list and build order

The judge is the user. After each item, send one light and dark contact sheet. **Stop rule:** if the user sees no clear gain after items 2 and 3, stop polishing and go back to reconstruction and real-camera work.

| Order | Item | Effort | Check that decides success |
|---|---|---|---|
| 1 | Slim harness: `CADDY_DEMO` states, `CADDY_APPEARANCE`, `CADDY_SLOWMO` through one multiplier, window-only capture at a fixed size | 1 d | One command writes light and dark PNGs of every screen state. A second run differs from the first by under 0.5% of pixels per image. Worst-pixel WCAG is printed for every text block over the stage or video. |
| 2 | P1 studio stage: environment light rotated with yaw (or a weak key light on `yawNode`), gradient backdrop, fading grid edge, stage tokens for both modes. No SSAO. Reflection off or at 0.05 or below. | 2.5 d | Mean model luminance at yaw 180° is within 15% of yaw 0°, so the back is not murky. Frame p95 is 16.7 ms or less on the oldest Mac available, labelled with that Mac's model. The user picks the new stage over the old on the sheet. |
| 3 | P2 palette: stage tokens adopted, dark elevation by lightness steps, light mode keeps hairlines, **system accent as the only highlight**, status green kept separate | 1 d | Every text block is 4.5:1 or better at its worst pixel in both modes. Covered and missing arcs stay distinguishable in a deuteranopia simulation. The user approves the sheet. |
| 4 | P5 first run on the stage, using one real scan the user picked from rendered stills, bundled as `CADViewer` resources. Text on a solid panel beside the stage. | 2 d + sample | The bundled STL loads from the built `.app` (not only `swift run`). At 1.4x text the column does not overlap the model. With Reduce Motion on, two frames 1 s apart are identical. The user approves the opening frame. |
| 5 | P3 reveal sweep: per-node material copies, opaque old mesh above the plane, old mesh casts the shadow until the end swap, direction flag for undo, 0.6 s or less, `pulse()` removed | 2.75 d | Scratchpad checks rerun on the app's own `ViewerScene`. The no-op edit composite differs from plain by under 0.1% (no seam). Model pixels never drop below 95% of the start frame (no vanish). Undo sweeps downward. With Reduce Motion the swap is instant. Frame p95 is 16.7 ms or less. |
| 6 | Delta chip with `numericText`, plus display numerals on the ring and size | 1 d | For the bench edit "make it 20 percent taller", the chip shows the same mm change as the new bounds minus the old. It is hidden under 0.5 mm. It fits at 1.4x text. |
| 7 | Applying state keeps the model visible: dim, capsule, timer, no looping motion. Solid fallback with Reduce Transparency. | 0.5 d | During a Claude edit (5 to 40 s), model pixels under the dim stay above zero and the timer advances. Nothing else moves. |
| | **Cut line** (main line about 10.75 d) | | |
| 8 | P4 trimmed viewfinder. **Blocked** until one real scan runs in the built app with the Mac camera and with an upright iPhone. | 2 d | The object stays fully inside the visible area for both sources. The HUD text is 4.5:1 or better at its worst pixel over a white-table frame. |
| 9 | Quiet headers, concentric radii, one icon weight, save checkmark, scale-only segment pulse | 1 d | Done only if time is left. Gate: the user's sheet, and no change to the 1.4x layout. |
| 10 | Flat app icon redraw in `make_icon.swift` | 0.5 d | Readable at 16 and 32 px. |
| 11 | Processing backdrop gradient | 0.25 d | The stage gradient shows behind the spinner. Nothing implies reconstruction. |

## Counts

The same 53 items as the critique.

| Verdict | Critique | Final | What moved |
|---|---|---|---|
| KEEP | 11 | 10 | Camera states became CUT |
| CHANGE | 18 | 16 | Bed outline and P8 became CUT |
| CUT | 24 | 27 | Those three added |

P3 stays CHANGE, with its required change replaced as described in section 1.
