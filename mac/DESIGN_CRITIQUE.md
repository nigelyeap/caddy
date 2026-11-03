# CADDIY design critique

Written 2026-10-30. This is the adversarial review of `DESIGN_IDEAS.md` and `DESIGN_PLANS.md`. I read those two files, `DESIGN_NOTES.md`, `README.md`, every file in `Sources/CADApp`, `CADViewer`, `CADScan` and `CADShared/Theme.swift`, plus the helper code they depend on (`webapp/app.py`, `webapp/processing.py`, `guidance/guidance.py`, `guidance/QUALITY_NOTES.md`). No source file was edited.

I built one throwaway SwiftPM test in the session scratchpad (`scratchpad/critique`). It renders the real 49,834-triangle bench scan `bench/out/mug_heavy_clean.stl` with SceneKit off screen on this Mac (Apple M4, macOS 27). Results are quoted below as **[tested]**. Everything else is from reading the code.

Verdicts: **KEEP** as written, **CHANGE** with a required change, **CUT**.

## Five problems that cut across the whole plan

1. **There is no reconstruction yet.** `webapp/processing.py` says "Video to mesh reconstruction does not exist yet, so a video input still gets the sample cup". The video path is `time.sleep(3)` and then a 48-segment procedural cup. So the processing screen lasts about 3 seconds, not "up to a minute" as the diagnosis says. Any design that dramatises reconstruction (P6, the Scan to Process hand-off) dresses up a step that does not happen. In a venture-course demo that is a credibility risk, not polish.
2. **The scan screen has no data for half of its proposed visuals.** The Mac sends JPEG only (`OtherSources.swift` line 177: "takes a JPEG only. Depth and pose need a new endpoint"). The Swift `GuidanceResult` has no `rings`, no pose and no "object centred" field. Sector 0 is wherever the student started, not a side of the object. Camera-only orbit error on real Objectron clips is 98° (cup) and -75° (shoe) in `QUALITY_NOTES.md`. Brackets bound to "centred", a ring that lies on the real floor, a comet dot and direction chevrons all claim spatial knowledge the app does not have. The screen has also never run on a real camera.
3. **The metrics are mostly people tests the plan cannot afford, and the rest can be gamed.** I count about 20 separate blind tests, each with 5 people, each against a baseline. None of that time is in the 18.5 day total. Several pass marks are noise at n=5. "Correct answers rise by 2 of 30" is within chance. The cheap code metrics reward refactors that users never see: `borderLines` and `motionLiterals` are grep counts. `edgeContrast` and `formRange` go up if you crank one hard key light, which looks cheaper, not more professional. `surfaceDeltaL` is true by construction once you pick the hex values. `frameMs` on an M4 always passes and says nothing about the classroom Macs, which nobody has identified.
4. **The plan refuses to use the real judge.** The user's three rounds of feedback ("cluttered and childish", "too empty and plain", now "impressive and professional") are taste calls. The plan says "never it looks nicer to me". That stance is right for a lab study and wrong here. The user is the person who must sign off on the demo. A before and after contact sheet reviewed by the user, plus hard gates (WCAG, frame time, Reduce Motion, 1.4x text, light mode), is cheaper and closer to the goal.
5. **Edit feedback stacks into clutter.** On one edit the plans would run the reveal sweep, the wireframe ghost, the scale stretch, the delta chip, the size count-up and (while waiting) a looping 3D beam. Add the view cube, bed outline, material menu, history thumbnails and hover ghosts, and the Edit screen is busier than version 1. Pick one motion per event.

## Plan 0. Verification harness

**CHANGE.** Objection: most of it serves the people-test programme (see problem 3), and the window capture needs Screen Recording permission for whatever runs `screencapture -l`.
Evidence: `ImageRenderer` cannot capture `NSViewRepresentable` content, as the plan says, and `Tests/CADScanTests` already uses `ImageRenderer` for `OverlayGallery`, so overlay shots exist today. `scripts/viewer_check.sh --pictures` already renders the stage headless.
Required change: keep `CADDIY_DEMO`, `CADDIY_APPEARANCE`, the window-only capture and a fixed window size. Keep two metrics that cannot be gamed: worst-pixel WCAG for text over video or the stage, and `frameMs` measured on the oldest Mac you can borrow. Drop `design_metrics.swift` beyond that, drop `borderLines` and `motionLiterals`, and drop `CADDIY_SLOWMO` unless P3 survives. Cost 1 day.

## P1. Studio stage

**CHANGE.** This is the strongest idea in the set. The model is the product, and the current stage is a flat `Theme.viewer` fill with a hard-edged grid. Strongest objection: the lighting environment is fixed in world space, while today's key, fill and rim lights ride on `yawNode` (`ViewerScene.init`), so "the side you look at is always lit well". Swap to image-based light and orbiting will turn the dark half of the environment toward the camera. The model goes murky from some angles.

Evidence **[tested]**:
- Frame cost is not the problem on Apple silicon. Median per frame, 1200×750, 4x MSAA, including readback: current lights 4.3 to 4.6 ms. Environment light plus HDR 1.9 ms. Plus floor reflection 1.9 to 2.1 ms. Plus SSAO 2.9 to 3.0 ms. The current rig is slower because it has three directional lights and an ambient light.
- `screenSpaceAmbientOcclusionIntensity` exists and compiles on the macOS 14 target. The "unverified" mark can go.
- Floor reflection does show on the existing `.shadowOnly` floor material (3.1% of pixels change at reflectivity 0.6). The half day of floor experiments is still wise, because the reflection shows the scan's underside.
- A flat `scene.background` colour passes through HDR unchanged (token 2A2D33 rendered as 42 45 51). Vignetting works (corner 0, top centre 44 at intensity 1).

Required change:
- Rotate the environment with the yaw, using `lightingEnvironment.contentsTransform`, or keep a weak key light on `yawNode`.
- Keep: environment light, gradient backdrop, fading grid, tone mapping, stage tokens in both modes.
- Cut SSAO for now. It is measurable cost with no shown gain on lumpy scans, where it will mostly darken noise.
- Floor reflection is optional at 0.05 or below.
- Tune on `mug_heavy_clean.stl`. It is lumpy, so a soft environment flatters it more than hard lights do.
- Cost: 2.5 days is honest.

Sub-ideas from section 3 of the ideas file:
- **Material presets: CUT.** It adds a menu and three looks to a screen that was just rebalanced. The PLA stripe normal map risks moiré, and the plan's own metric for it is an FFT. That is taste.
- **Fresnel rim: CUT for now.** The plan says it "makes holes in scans glow", and the scans have holes (`isDoubleSided = true` exists for that reason). Revisit only if the dark stage loses the silhouette after the environment change.
- **View cube: CUT.** It duplicates Reset view, double-click and the arrow keys (`OrbitSCNView.keyDown`). It is clutter in the corner that v1 was criticised for.
- **Bed outline: CHANGE.** The plan says the bed size is unknown. The edit code already refuses "make it 2 metres tall" with "The biggest it can be is 250 mm" (`bench/out/bench.log`). Use that same constant so the outline and the refusal agree. 0.5 day.

## P2. Graphite and signal palette

**CHANGE.** Strongest objection: on a default Mac the system accent is blue, and signal cyan 3CCFDD sits a short hue step away from it. Both would be on the Edit screen at once (the Apply button and the viewer toggles in accent, the delta chip and sweep in signal). Two near-blues read as a mismatch, not a system. Second objection: dropping card borders in light mode moves back toward "too empty and plain", the v2 complaint.

Evidence: `Theme.accent = Color(nsColor: .controlAccentColor)`. `ViewerToolbar.icon` fills active toggles with `Theme.accent` inside the viewport, which the plan reserves for signal. `card()` and the chips use hairlines today (5 `strokeBorder(Theme.line` lines in 4 files, as the plan says).

Required change:
- Put the default-blue accent and signal side by side in one shot before committing. If they clash, move signal further from blue or tint the viewer toggles with signal.
- Keep hairlines on light-mode cards. Use lightness steps for elevation in dark mode only.
- Keep the deuteranopia check and the shape difference between covered and missing arcs.
- Drop the `borderLines` metric.
- Cost: 1.5 days is fair.

## P3. Reveal sweep

**CHANGE.** It works technically, but it has two bugs the plan does not mention.

Evidence **[tested]**:
- A `.surface` modifier with `#pragma arguments float u_reveal`, `scn_frame.inverseViewTransform` and `discard_fragment()` compiles and cuts the mesh by world height. Visible pixels at u = 0, 20, 40 and 1000 mm were 29,636, 37,923, 49,391 and 81,314.
- `CABasicAnimation(keyPath: "u_reveal")` on the material animates it (31k to 81k pixels over the run). An implicit `SCNTransaction` on `setValue(_:forKey: "u_reveal")` also animates it. The "unverified" mark can go, and no render-delegate fallback is needed.
- **Bug 1:** the shadow pass ignores the discard. With the whole model discarded, the full mug shadow stays on the floor (`out/reveal_hidden.png`, the 29,636 pixels above are all shadow). The new mesh's full shadow appears before the mesh does. The fix is to turn `castsShadow` off on the sweeping node and back on at the end, or fade the shadow colour.
- **Bug 2:** `setModel` gives every node the same `material` instance (`geometry.materials = [material]`). A uniform set for the new node also hits the old one. Each node needs its own material copy, and the wireframe toggle must then update both.
- Undo and redo arrive as `refreshModel(afterEdit: false)`, and `ViewerController.load` treats any reload as an edit. A direction flag must cross from `CADApp` into `CADViewer`, which have different owners per the README.
- Two meshes during the sweep cost 2.4 to 2.7 ms per frame. That is fine.

Required change: fix the two bugs, add the direction flag, and remove `pulse()`. Use the sweep for first appearance and edits only, at 0.6 s or less. Drop the ghost of the old mesh above the plane. One moving plane is enough. Replace the "10 clips, +20 points" study with the user watching three edits. Cost 2.5 days still holds.

## P4. Full-bleed scan viewfinder

**CHANGE**, scoped down hard. See problem 2.

Evidence:
- The preview layer is already `.resizeAspectFill` (`CameraScanSource.swift` line 34). The letterbox comes from `.aspectRatio(16 / 9, contentMode: .fit)` on `cameraArea`. Step 1 of the plan targets the wrong line.
- Real-camera risk: Continuity Camera is supported ("A nearby iPhone appears here"). An iPhone held upright gives a 9:16 picture. Aspect fill into a landscape area then crops about two thirds of the frame. The object can be off screen while the guidance service, which sees the full JPEG, says all is well.
- There is no "object centred" signal for the brackets to bind to.
- The perspective ring at 68° implies it is tied to the table. Sector 0 is the start heading, and camera-only error reaches 98° on real clips.

Required change:
- Keep full bleed, but use aspect fit with a blurred copy of the frame behind it, or switch to fill only when the source and view aspects are within 15%.
- Keep hiding the side panel while recording.
- Keep the shutter button and the Space shortcut.
- Keep a flat coverage ring, bigger, bottom centre, in signal.
- Cut the brackets, the tilted ring and the comet dot.
- Do none of it until one real scan has been run on the built app with the Mac camera and with an iPhone.
- Cost: 2 days after the trimming.

## P5. First run on the real stage

**CHANGE.** It is high value for the demo, because it is the first frame the audience sees. Strongest objection: there is no sample worth showing. `useSample()` uploads an empty `sample.mov` and the helper returns `_cup()`, a 48-segment cylinder with flat faces and an open top. A plain tube slowly turning on a studio stage will look like a placeholder.

Evidence: `AppModel.useSample`, `processing.py _cup`. No target in `Package.swift` declares resources. Bundling a file is feasible **[tested]**: the generated SwiftPM accessor looks in `Bundle.main.resourceURL` first, and `build_app.sh` line 29 already copies `*.bundle` into `Contents/Resources`.

Required change:
- Bundle one good real scan as `CADViewer` resources, chosen with the user. Show the rendered still to the user before writing layout code.
- Put the text column on a solid panel beside the stage, not on a scrim over a moving model. Text over 3D motion is the hardest case for contrast at 1.4x text.
- Keep the "For a good scan" tips one click away.
- With Reduce Motion, show the still view, as planned.
- Cost: 2 days plus the sample choice.

## P6. Processing that shows work

**CUT.** Strongest objection: it fans the student's own video frames into a point cloud, then shows a canned cup unrelated to the video (see problem 1). The plan admits "a viewer may read it as real data". In a venture demo someone will ask, and the answer is bad. The screen lasts 3 seconds on the video path today, so 2.5 days buys 3 seconds.
Evidence: `processing.py` `clean_scan`, the `time.sleep(3)` line. Mesh files go through `bench/clean.py` and take a few seconds as well.
What to do instead: put the stage backdrop gradient behind the existing spinner and stage text. 0.25 day. Revisit when real reconstruction exists.

## P7. Edit ghost and size deltas

**CHANGE.** Split it.
- **Wireframe ghost: CUT.** **[tested]** `fillMode = .lines` on the 50k-triangle scan renders as a grey haze (`out/ghost_lines.png`). Real scans are this dense, so the plan's fallback (translucent solid with fresnel) would be the main path. Translucent double-sided meshes bring sort problems in SceneKit. It also stacks a second effect on the sweep (problem 5).
- **Scale stretch: CUT.** The plan says the helper may move the model. `setModel` re-centres every mesh on its bounds, so the stretch would often be wrong.
- **Delta chip and count-up: KEEP.** It is cheap and it teaches dimensions, which suits a CAD class. Hide it under 0.5 mm, as planned.

Cost: 0.5 day for what survives.

## P8. Motion tokens and step rail

**CHANGE.** Strongest objection: the diagnosis is wrong. SceneKit already uses six different durations (0.2, 0.25, 0.3, 0.5, 0.6 and 0.9 s, plus the 18 s spin). SwiftUI uses one token, `Theme.motion`, which is already a token. Moving numbers into an enum changes nothing a student sees, and `motionLiterals = 0` is a refactor score.
Evidence: grep of `ViewerScene.swift`. `StepIndicator` already marks the current step with weight and colour, and the plan says the baseline "may already pass" its own test.
Required change: add only the `spatial` spring and use it where P3 and P4 need it. **Cut the step rail.** Cost 0.25 day.

## Other ideas

| Idea | Verdict | Strongest objection and evidence | Required change |
|---|---|---|---|
| Lightness-stepped neutrals | KEEP | Folded into P2. Cheap and objective. | |
| Separate status green from signal | KEEP | Needed once coverage turns signal. 0.25 day. | |
| Display numerals | KEEP | Coverage percent and size are the most read numbers. Check that `.fontWidth(.expanded)` still fits inside the ring at 1.4x. `minimumScaleFactor(0.5)` is already there. | |
| SF Mono dimensions | CUT | `SizeBadge` already uses `.monospacedDigit()`. A switch to SF Mono is taste, and 12 pt mono next to 13 pt SF Pro looks smaller. | |
| Quiet section headers | KEEP | 0.1 day. Gives the inspector a hierarchy without adding anything. | |
| Wordmark | CUT | The author calls it "mostly taste". A styled name in the toolbar next to the system title area adds nothing for students. | |
| numericText everywhere | KEEP | Already on the ring. Cheap and consistent. | |
| Segment completion pulse | CHANGE | Fires up to 12 times per scan, on top of the Tink sound that already plays (`ScanModel.apply`). | Scale only, no glow, off with Reduce Motion. |
| Complete moment | CHANGE | A once-only sweep on a screen used many times per lesson. | Keep the ring colour change and the button changing to Finish. Cut the light sweep. |
| Scan beam | CUT | Pure decoration that loops for the whole recording. The plan's own test says to cut it if the REC badge already answers "is it recording". It does. A moving line over live video can also read as a glitch on the projector. | |
| Directional chevrons | CUT | No data. The Mac API has no pose and no direction field. They would never show, or would show wrong. | |
| Dark glass HUD | CHANGE | `.ultraThinMaterial` over a bright white table goes light grey, and white text fails contrast. The current 72% black backing is ugly but safe. | Use a material plus a black underlay of at least 40%. Solid fallback with Reduce Transparency. Gate on worst-pixel WCAG over a white-table frame, not the gallery backdrop. |
| Scan to Process hand-off | CUT | `matchedGeometryEffect` across the `switch` in `RootView.content`, with an `NSViewRepresentable` camera layer inside. Fragile for a 3 second screen. | |
| Process to Edit shared stage | CUT | Shares one `SCNView` across steps, which changes view lifetimes. That is refactor risk the week before a demo. | |
| Staggered first entrance | CUT | Taste, and seen once. It also needs a stored first-time flag. | |
| Applying state keeps model visible | CHANGE | Right goal. Canned edits return in 0.02 s and Claude edits take 5 to 40 s (`BackendAPI.edit` doc). A 3D beam looping for 40 s is the "motion on high frequency" the ideas file warns against. | Keep the model visible and lightly dimmed, with the capsule and timer. No beam. 0.5 day. |
| History thumbnails | CUT | 1.5 days. Each row already says what changed in words ("make it 20 percent taller"). 36 pt renders of near-identical shapes add clutter, not information. | |
| Empty plinth | CUT | Edit only opens after a model is ready, so `.empty` is rarely seen. Drag and drop already has `dropHint`. | |
| History before first change | CUT | The quick-change chips sit right above it. Suggesting them again duplicates them. | |
| Camera states | KEEP | These will happen in a real classroom (denied, busy, no camera). 0.25 day. | |
| App icon | CHANGE | A rendered 3D object turns to mush at 16 to 32 px, as the plan admits. | Redraw the glyph in `make_icon.swift` as flat shapes in the new palette with the signal ring. 0.5 day, no render pipeline. |
| Splash | CUT | The helper start time via `uv` is unknown. Animated rings during a failure-prone start add risk. The existing failure path with details works. | |
| Dark as hero look | CHANGE | Dark UI on a projector in a lit room often washes out. Nobody has tested the demo room. | Test both modes on the actual projector. Pick the demo mode from that. |
| Native inspector | CUT | Changes width rules on a layout just tuned for 1.4x text, for a look that is "subtle on 14". | |
| Press scale 0.96 | CUT | That is an iOS and web idiom. Mac push buttons darken on press, which `BigButtonStyle` already does. It would make the app feel less native. | |
| Shadows over borders | CHANGE | Folded into P2. | Dark mode only. Light keeps hairlines. |
| Concentric radii | KEEP | 0.25 day, objective, invisible risk. | |
| Toggle icon cross-fade | CUT | The sound button already uses `.symbolEffect(.replace)`. The viewer toggles change fill, which is clear. | |
| Hover preview for quick changes | CUT | 1.5 days. Works for only some chips, so behaviour differs chip to chip. Hidden behaviour for kids. | |
| Orbit snapping with haptics | CUT | Snapping fights free orbit. Classroom mice have no haptics. Front, side and top views are one arrow key away. | |
| Sound set | CUT | System Tink and Glass already play. A day of making or licensing sounds a classroom will mute. | |
| Save confirmation | CHANGE | `.drawOn` is macOS 26 only and unverified. | `.contentTransition(.symbolEffect(.replace))` to a checkmark on macOS 14. 0.25 day. |
| One icon weight, outline by default | KEEP | Cheap consistency. | |
| Three custom symbols | CUT | 1.5 days, and loading custom symbols from a SwiftPM bundle is unverified. SF Symbols covers Scan and Edit well enough. | |
| No outside icon sets | KEEP | A rule, no cost. | |
| Symbol effects with purpose | CHANGE | `.breathe` is macOS 15+. `.pulse` on REC duplicates the blink that `RecBadge` already does with `TimelineView`. | Only `.bounce` on a completed step. Skip the rest. |
| Avoid list | KEEP | Every item matches the user's history. | |

## Reduce Motion, large text, light mode, slow Mac, real camera

- **Reduce Motion.** The plans handle it for the sweep, spin and pulse. The first-run stage must also stop `startSpin(forever:)`. `ViewerController.applySpin` already checks this, so reuse it.
- **Large text.** At 1.4x the flat ring and the shutter share the bottom edge. Test the scan shot at 1.4x before merging P4. The P5 text column must grow, not overlap the model.
- **Light mode.** The stage needs its own light tokens (P1). Signal in light mode needs the deeper teal for text contrast, as the plan says.
- **Slow Mac.** Every number above is from an M4. Before the demo, run `viewer_check.sh` on the oldest Mac you can borrow. Turn reflection off if p95 goes over 16.7 ms.
- **Real camera.** Nothing in P4 has met a real feed. The Continuity Camera portrait crop is the most likely failure.

## Surviving list, ranked

| Rank | Item | Cost | Why it survives |
|---|---|---|---|
| 1 | P1 core: environment light rotated with yaw, gradient backdrop, fading grid, 250 mm bed outline | 2.5 d | The model is the product and the demo's main visual. Cheap per frame **[tested]**. |
| 2 | P2 core: tokens, elevation steps, signal on coverage and edits, green split from signal, hairlines kept in light | 1.5 d | Fixes the three-grey problem everywhere at once. |
| 3 | P5: first run on the stage with a chosen, bundled real scan | 2 d + sample | The demo's opening frame. Bundling is proven feasible. |
| 4 | P3: reveal sweep with the shadow fix, per-node materials, direction flag, replaces `pulse()` | 2.5 d | Makes the core loop (type a change, see it) legible. Mechanism verified. |
| 5 | Delta chip, numericText, display numerals | 1 d | Teaches dimensions, cheap, no clutter. |
| 6 | Applying state keeps the model visible (no beam) | 0.5 d | Removes the moment the model vanishes during 5 to 40 s waits. |
| 7 | Slim harness: demo states, window capture, WCAG and frameMs gates | 1 d | Do it first in time, before rank 1. It makes the user review cheap. |
| 8 | P4 trimmed: aspect-safe full bleed, panel hidden while recording, shutter, flat ring, safer HUD, camera state cards | 2.5 d | Only after one real camera run. Then it is the hero screen. |
| **Cut line** | | **about 13.5 d** | |
| 9 | Quiet headers, concentric radii, one icon weight, save checkmark, segment pulse (scale only) | 1 d | Fine if time is left. Low risk, low impact. |
| 10 | Flat redraw of the app icon | 0.5 d | Nice for the demo slide, not the app. |
| 11 | Processing backdrop gradient only | 0.25 d | Tiny and honest. |

Below the cut line everything else is CUT for this demo. Ranks 1 to 4 should then go to the user as one contact sheet, light and dark. The plan's own stop rule still applies, with the user as the judge in place of the people tests. If the user does not see a clear gain after ranks 1 and 2, stop and go back to reconstruction and real-camera work. Those are the demo's actual risks.

## Tally

- KEEP: 11 (the 10 KEEP rows in the table, plus the P7 delta chip)
- CHANGE: 18 (8 plan sections, the bed outline, 9 table rows)
- CUT: 24 (P6, 3 P1 sub-ideas, 2 P7 sub-ideas, 18 table rows)

Counted once each: the 9 plan sections (Plan 0, P1 to P8), the 37 rows of the table above, the 4 P1 sub-ideas and the 3 P7 sub-ideas. Total 53.
