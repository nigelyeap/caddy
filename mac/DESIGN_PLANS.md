# CADDY design plans

Written 2026-10-30. Each plan matches one idea in `DESIGN_IDEAS.md`. Nothing here is built yet. Costs are working days for one person who knows SwiftUI and SceneKit. They include the verification run and leave no slack for review rounds.

Every plan has the same parts: goal, files and pieces, steps, screenshot check, cost, risks, and a metric. Metrics are measured on pixels, code or people, never "it looks nicer to me". Where a metric is a people test, it is a blind test with a fixed question, and the pass mark is set before the test.

**Honest framing.** Many of these ideas are polish on a three-screen app whose main risk is elsewhere (real reconstruction quality, live edit success rate, see `IDEAS.md`). A screenshot cannot fix a bad mesh. If the demo scan looks like a blob, a studio stage just lights the blob nicely.

---

## Plan 0. Verification harness (do this first)

Every later plan depends on repeatable screenshots and numbers. Without this, "looks better" is taste.

- **Goal.** Produce the same window, in the same state, at the same size, in light and dark, with one command, before and after each change.
- **Files and pieces.**
  - `Sources/CADApp/CADApp.swift`: read `CADDY_DEMO` (values `firstrun`, `scan`, `processing`, `edit`, `edit-applying`, `edit-changed`, `empty`) and `CADDY_APPEARANCE` (`light`, `dark`). Demo mode uses `MockBackendAPI` (already in `Integration.swift` as `previewAPI()`) and `PreviewScanSource` (already in `CADScan/OtherSources.swift`). It sets `NSApp.appearance` and a fixed 1440×900 content size. This changes the app's own appearance only, never the system setting.
  - `Theme.swift`: a `CADDY_SLOWMO` multiplier on every motion token, so a 0.4 s animation can be shot at 4 s.
  - New `scripts/shots.sh`: build debug, launch each state, find the window ID with CoreGraphics filtered to owner `CADDY`, run `screencapture -x -o -l <id>`, and write `shots/<state>-<appearance>.png`. Never capture the full screen.
  - New `scripts/design_metrics.swift` (stdlib, AppKit and CoreGraphics only): reads PNGs and token hex values, and prints the numbers below as JSON.
  - `scripts/viewer_check.sh --pictures` already renders the SceneKit stage headless to PNG. Reuse it for every stage plan. Add a second render with the model hidden so the metric script can build a model mask by difference.
- **Steps.** 1) Add the env reads. 2) Write `shots.sh`. 3) Write `design_metrics.swift`. 4) Capture and commit the **baseline** set from today's build to `shots/baseline/`. 5) Check that two runs of the same state differ by under 0.5% of pixels (blinking REC dot and the spinner aside, which get masked).
- **Metrics the script prints.**
  - `surfaceDeltaL`: CIELAB L* gap between adjacent surface tokens (`window`, `surface`, `raised`, stage).
  - `wcag`: contrast ratio for each text token on each surface it sits on.
  - `edgeContrast`: mean |ΔL*| across the model silhouette, from the stage render and its mask.
  - `formRange`: L* spread (95th minus 5th percentile) inside the model mask. A proxy for how readable the shape is.
  - `frameMs`: median and 95th-percentile render time over 120 frames of `SCNRenderer` at 1200×750 for each bench STL.
  - `borderLines`: count of `strokeBorder(Theme.line` and `card()` uses in `Sources/` (baseline: 5 direct `strokeBorder(Theme.line` lines across 4 files, plus `card()` call sites).
  - `motionLiterals`: count of hard-coded `duration:` and `.easeOut(` and `easeInEaseOut` outside `Theme.swift` (baseline: 6).
- **Shared people test (used by several plans).** Five people who have not seen the app (classmates or teachers are fine). Each test question is fixed in advance, run blind on baseline and new shots shown in random order. This is not a taste vote. Each question has a right answer.
- **Cost.** 1.5 days.
- **What could go wrong.** Demo mode drifts from the real app and shots stop showing the truth. Mitigation: demo mode only swaps the backend and the camera, and every screen is the real view. Window shadows and the Retina scale change pixel sizes. `-o` drops the shadow, and the script normalises to points. `ImageRenderer` cannot capture `NSViewRepresentable` content (the camera layer, the `SCNView`), so stage shots must come from `SCNRenderer` or a real window, never from `ImageRenderer`.

---

## Top 8 plans

### P1. Studio stage

- **Goal.** The model reads as a real object on a studio plinth. The shape is easier to read from any angle.
- **Files and pieces.** `Sources/CADViewer/ViewerScene.swift` (`init`, `setAppearance`, `rebuildGrid`, `makeMaterial`), `Sources/CADShared/Theme.swift` (new `Stage` tokens), and `Sources/CADViewer/ModelViewer.swift` (the `SCNView` antialiasing mode).
- **Steps.**
  1. Add `Theme.Stage.top`, `bottom` and `grid` tokens for light and dark.
  2. Write `StudioEnvironment.image(dark:) -> NSImage`. It draws a 1024×512 equirect in Core Graphics: a vertical gradient, two large soft white rectangles at about 30° elevation front-left and back-right, and one thin strip overhead. Set `scene.lightingEnvironment.contents` and `intensity` ≈ 1.0 to 1.4.
  3. Lower the key light to about 500 and the fill to 0. Keep the rim at about 300. Drop the ambient light, since the environment now does that job. Tune by metric, not by eye (step 9).
  4. Backdrop: `scene.background.contents` gets a gradient `NSImage` drawn from the stage tokens, regenerated in `setAppearance`.
  5. Grid: split into minor (every step) and major (every 5 steps) geometry. Add a `.fragment` shader modifier that fades alpha with distance from the centre: `_output.color.a *= 1.0 - smoothstep(u_r0, u_r1, length(worldXZ))`. Set `blendMode = .alpha` and `transparencyMode = .dualLayer` if sorting artefacts show.
  6. Floor: `reflectivity` 0.08, `reflectionFalloffEnd` = radius × 0.5, `reflectionResolutionScaleFactor` 0.5.
  7. Try `camera.screenSpaceAmbientOcclusionIntensity` 0.8 **(unverified property)**. If it does not exist or looks noisy, skip it and rely on the environment.
  8. `camera.wantsHDR = true`, fixed `exposureOffset`, `wantsExposureAdaptation = false`, `vignettingIntensity` ≈ 0.3.
  9. Run `viewer_check.sh --pictures` on all samples and bench STLs, light and dark. Compare with the baseline.
- **Screenshot check.** Headless stage PNGs for every sample plus `shots/edit-*.png`. Put baseline and new side by side in one contact sheet per file.
- **Cost.** 3 days (1 to build, 1 to tune lights against the metrics, 1 for performance and edge cases).
- **What could go wrong.**
  - Performance. Floor reflection renders the scene twice. HDR, SSAO and a 2048 shadow map add up. Classroom Macs may be older Intel machines **(hardware unknown, ask)**. Mitigation: a "quality" switch that drops reflection and SSAO when `frameMs` p95 goes over budget.
  - Shiny surprises. Environment light can make dark scans look grey and washed out. Tune on the darkest real scan, not on the sample.
  - SceneKit's future. Apple has signalled that new 3D work should go to RealityKit **(unverified how strongly for macOS)**. This plan adds a few hundred lines to SceneKit, which is fine for now but is not a long-term asset.
  - The shadow-only floor material and floor reflections may not combine as expected. Plan a half day for floor experiments.
- **Metric.**
  - `edgeContrast` ≥ 15 in both appearances, and ≥ baseline + 5.
  - `formRange` ≥ 1.3 × baseline on at least 4 of 5 bench meshes.
  - `frameMs` p95 ≤ 16.7 ms at 1200×750 for the largest bench mesh on the development Mac, and ≤ 1.3 × baseline.
  - People test: show a 3 s still of 6 meshes and ask "which of these two parts is closer to you?" on a fixed pair of features per mesh. Pass if correct answers rise from baseline by at least 2 of 30. This tests depth reading, not liking.

### P2. Graphite and signal palette

- **Goal.** A clear surface hierarchy and one brand colour that marks spatial information, with no loss of contrast.
- **Files and pieces.** `Sources/CADShared/Theme.swift` (tokens, `card()`, button styles), plus every `strokeBorder(Theme.line` call site (`Screens.swift`, `Components.swift`, `EditScreen.swift`). `CADScan/Overlay.swift` gets `signal` for the coverage fill in place of `Overlay.good`.
- **Steps.**
  1. Pick neutral values by equal L* steps (target 4 to 6 L* between `window`, `surface` and `raised` in dark, and 3 to 4 in light), at hue about 250 and chroma ≤ 3. Use the metric script to check this, not a colour picker.
  2. Add `window`, `surface`, `raised`, `hairline`, `signal` and `signalSoft`. Map the old names (`background`, `panel`, `line`, `viewer`) to the new ones so other targets keep compiling.
  3. Make `hairline` `ink.opacity(0.08)`. Respect `accessibilityDisplayShouldIncreaseContrast` by raising it to 0.2.
  4. Change `card()` to no border, plus a two-layer shadow on the light theme and a lightness step on dark. Keep borders only on dividers and focused fields.
  5. Replace `Overlay.good` with `signal` on coverage arcs only. Status green stays for status.
  6. Run `shots.sh` for all states.
- **Screenshot check.** All 14 shots (7 states × 2 appearances) against baseline, as a contact sheet.
- **Cost.** 1.5 days.
- **What could go wrong.**
  - Signal cyan sits near `good` green for some forms of colour blindness. Check with a deuteranopia simulation of the scan shot (Core Image colour matrix in the metric script). The coverage ring must also differ by shape (filled versus dashed), never by colour alone.
  - Dropping borders in light mode can make white on near-white disappear on low-quality projectors. Test on the classroom projector if one is reachable, or simulate with a contrast-reduced shot (multiply contrast by 0.6).
  - Other targets may hard-code `Theme.line` semantics. Aliases keep them compiling, but check them by eye.
- **Metric.**
  - `surfaceDeltaL` between each adjacent pair: ≥ 4 in dark and ≥ 3 in light (baseline is about 2 to 3 **(to measure)**).
  - `wcag`: `ink` ≥ 7, `muted` ≥ 4.5 and `signal` text ≥ 4.5 on every surface it appears on. No regressions from baseline.
  - `borderLines` down by ≥ 50%.
  - The ring still separates covered from missing under deuteranopia simulation: ΔE2000 ≥ 20 between the two arc states.
  - People test: show the Edit shot for 3 s, hide it, then ask "point to where the model information was". Pass if ≥ 4 of 5 point to the right panel region, against baseline. This tests whether the layout reads as zones.

### P3. Reveal sweep

- **Goal.** A change to the model is visible as a change, in one consistent motion, in under a second.
- **Files and pieces.** `ViewerScene.swift` (`setModel`, `pulse`, the material), and `ModelViewer.swift` to pass "edit", "undo" or "first" into `setModel`. `AppModel.swift` already knows the cause (`lastChangeWasEdit`). Undo needs a direction flag.
- **Steps.**
  1. Add a `.fragment` shader modifier to the model material with `#pragma arguments float u_reveal, float u_band, float3 u_signal`. Compute world y from `_surface.position` via `scn_frame.inverseViewTransform`. Discard above `u_reveal`. Add emission inside the band.
  2. Give the old node a ghost material with the inverse test (discard below `u_reveal`, 25% alpha).
  3. Animate `u_reveal` from floor to top over 0.7 s with `CABasicAnimation(keyPath: "u_reveal")` on the material. If key-path animation of custom arguments fails **(unverified)**, drive it from `SCNSceneRendererDelegate.renderer(_:updateAtTime:)` with a manual ease.
  4. Undo runs top to bottom. Reduce Motion skips straight to the end state with a 0.15 s crossfade.
  5. Remove `pulse()`.
  6. Add a debug hook that renders frames at t = 0, 0.15, 0.35, 0.55 and 0.7 s through `SCNRenderer.snapshot(atTime:)` into a filmstrip PNG.
- **Screenshot check.** The filmstrip for 3 edit types (taller, add hole, cut). Also a `CADDY_SLOWMO=10` window capture at 5 timestamps to confirm the live view matches the headless one.
- **Cost.** 2.5 days.
- **What could go wrong.**
  - Bad normals or open scans give holes in the band, and the band looks like flicker. Test on the worst bench mesh.
  - Double-sided material (needed for holed scans) shows back faces in the band. May need `cullMode` tweaks inside the effect.
  - Both meshes render at once during the sweep, which doubles triangles for 0.7 s. Measure `frameMs` during the sweep on the largest mesh.
  - For a change high on the model (a hole in the top), most of the sweep shows no change, so the motion carries little information. If so, start the sweep at the bottom of the changed region (needs a bounding-box diff, adds 1 day).
  - It may get tiresome by the 20th edit. Hold the duration at ≤ 0.7 s and test with a 20-edit session.
- **Metric.**
  - People test, the main one: 10 short clips of edits (old to new, about 2 s each), random order, baseline crossfade-and-glow versus sweep. Question: "what changed?", with free answer, scored against the edit text. Pass if correct answers rise from baseline by ≥ 20 points (for example 55% to 75%).
  - Time to answer, median, must not get worse.
  - `frameMs` p95 during the sweep ≤ 16.7 ms.
  - The sweep never runs longer than 0.7 s (assert in the self-check).

### P4. Full-bleed scan viewfinder

- **Goal.** The scan screen reads as a camera, not a form. "Where do I move next" is answerable at a glance.
- **Files and pieces.** `Sources/CADScan/ScanView.swift` (`cameraArea`, `overlay`, `controlBar`), `Sources/CADScan/Overlay.swift` (`CoverageRing`, `RecBadge`, `CoachCard`), `Sources/CADApp/RootView.swift` (`scanStep` hides `ScanSidePanel` while recording), and `CameraPreview` (`videoGravity = .resizeAspectFill` on the preview layer).
- **Steps.**
  1. Fill mode and corners: `.resizeAspectFill`, 12 pt continuous radius, an inner 1 pt white outline at 10%.
  2. Hide the side panel while recording. Animate it with the `spatial` token. Before recording, it stays.
  3. New `ViewfinderBrackets` shape: four L paths with a bindable inset. The inset and colour are bound to "object centred" from guidance chips.
  4. New `OrbitRing`: reuse `SegmentArc` and `Track`, wrap in `.rotation3DEffect(.degrees(68), axis: (1, 0, 0), perspective: 0.4)`, anchor at bottom centre of the frame. Filled arcs get signal colour and a soft shadow. Missing arcs get a dashed white stroke. Put the percent in a display-size label under the ring.
  5. New `ShutterButton`: one `RoundedRectangle` whose size and radius animate from a 44 pt disc to a 22 pt rounded square. Keep `.keyboardShortcut(.space)` and the same accessibility label as today.
  6. Add the `OrbitRing` and `ShutterButton` to `OverlayGallery`, so the existing test renders them to PNG over the busy backdrop.
- **Screenshot check.** `shots/scan-*.png` with `PreviewScanSource` at 0%, 40% and 100% coverage. The `overlay.png` from the test target.
- **Cost.** 3 days.
- **What could go wrong.**
  - Aspect fill crops the frame edges, so the object can look framed when it is not. The guidance service sees the full frame. Brackets must show the safe area the service actually uses, or they will mislead.
  - A perspective ring on the floor implies it is tied to the real table. It is not tracked to the scene. If the camera tilts, the ring stays put and may look wrong. Mitigation: keep it clearly a HUD element (bottom-anchored, with its own dark backing), or skip the tilt and keep a flat ring in a better place. Test both.
  - At "Extra large" text size the ring and the shutter compete for the bottom edge. Test at 1.4×.
  - On a projector, 30% white dashes may vanish. Check under the contrast-reduced simulation.
- **Metric.**
  - People test: show a scan shot with a known gap in coverage for 3 s. Ask "which side of the object still needs filming?" (pick from 4 arrows). Pass if correct answers reach ≥ 4 of 5 and beat baseline.
  - The share of window pixels showing camera image rises from baseline (measured from the shot, by masking the camera layer) by ≥ 25%.
  - Text on the HUD keeps WCAG ≥ 4.5 over the busy backdrop at its worst pixel (sampled behind each label in `overlay.png`).

### P5. First run on the real stage

- **Goal.** The first screen shows what the app makes, not a description of it.
- **Files and pieces.** `Sources/CADApp/Screens.swift` (`FirstRunView`), `Sources/CADApp/RootView.swift` (pass a viewer controller in), and `Sources/CADViewer/ModelViewer.swift` (a read-only "showcase" mode: no gestures, spin on).
- **Steps.**
  1. Load the bundled sample STL into a dedicated `ViewerController` when the first-run screen appears. No backend call is needed for a local file **(check that the sample STL is in the bundle, not only in the helper)**.
  2. Layout: stage fills the window. A leading column, 360 pt wide, holds the 28 pt display headline, one sentence, and the two buttons. A soft gradient scrim behind the column keeps text contrast. Under it, a row of three numbered steps.
  3. Spin forever at 18 s per turn. With Reduce Motion, show a still three-quarter view.
  4. With large text, the column grows and the model shifts right, since the camera target offsets with the column width.
- **Screenshot check.** `shots/firstrun-light.png`, `shots/firstrun-dark.png`, and the same at 1.4× text.
- **Cost.** 2 days (needs P1 first for the stage to be worth showing).
- **What could go wrong.**
  - If the sample model is ugly, this makes it the first thing people see. Choosing or making a good sample is part of the cost and may take longer than the code.
  - Two `SCNView` instances (first run and later Edit) cost memory. Tear the showcase down on leaving.
  - Loses the "For a good scan" checklist from the first screen. It still shows on the scan screen before recording.
- **Metric.**
  - 5-second test: show the first screen for 5 s, then ask "what does this app do?" Score correct if the answer mentions both "3D model" and "scan or film". Pass at ≥ 4 of 5, and beat baseline.
  - Text over the stage keeps WCAG ≥ 4.5 at the worst pixel behind the headline and buttons.

### P6. Processing that shows work

- **Goal.** The waiting minute feels like progress without claiming a percentage the helper cannot report.
- **Files and pieces.** `Sources/CADApp/Screens.swift` (`ProcessingView.preview`), `AppModel.swift` (keep the scan video URL in `Processing`), and a new `ProcessingStage` view in `CADApp`.
- **Steps.**
  1. On entry, pull 12 frames from the scan video with `AVAssetImageGenerator` (local, fast). For a mesh file or the sample, skip to step 3.
  2. Lay the frames as small cards on an ellipse around the centre. They fan in over 0.8 s, then dim to 40%.
  3. A `Canvas` point cloud in a `TimelineView(.animation)`: 1,500 points that drift from random positions toward a loose sphere around the centre, slowly, with no endpoint. The stage name ("Building the model") stays as the only honest status.
  4. On `.ready`, freeze the cloud and hand off to P3's sweep in the Edit stage.
  5. Reduce Motion: frames shown still, no cloud, keep the stage text.
- **Screenshot check.** `shots/processing-*.png` at t = 1 s and t = 20 s (demo mode holds the stage).
- **Cost.** 2.5 days.
- **What could go wrong.**
  - The point cloud is decoration. It does not come from the real reconstruction, and a viewer may read it as real data. Mitigation: keep it abstract (a sphere, not the object shape), and do not label it as the model. If the helper ever exposes a real sparse cloud, swap it in.
  - `Canvas` at 60 fps with 1,500 points costs CPU on battery. Measure. Cap at 30 fps if needed.
  - Frame extraction on a very long video takes time. Use `requestedTimeToleranceBefore/After` loosely.
- **Metric.**
  - People test, with a stopwatch: show a 45 s screen recording of processing (baseline versus new), then ask "how long did that take?" Perceived wait is a measurable outcome. Pass if the median estimate falls by ≥ 15%.
  - Also ask "is the app still working or stuck?" at the 30 s mark. Pass if ≥ 4 of 5 say working (baseline to measure).
  - CPU use under 25% of one core during the wait (Activity Monitor or `top -l` sampled 10 times).

### P7. Edit ghost and size deltas

- **Goal.** After an edit, the user can say what changed and by how much.
- **Files and pieces.** `ViewerScene.swift` (keep the old node, ghost material), `ViewerUI.swift` (`SizeBadge` with a delta), and `ViewerController` (store the previous size).
- **Steps.**
  1. On `setModel(edit: true)`, keep the old node. Swap its material to `fillMode = .lines`, constant lighting, signal colour at 20%. Fade opacity to 0 over 1.2 s, then remove it. This shares the old node with P3. Build P3 first and take the ghost from it.
  2. For scale-type edits, if old and new bounding boxes differ by more than 2% on any axis, first animate the old node's scale to the new box over 0.35 s, then swap.
  3. `SizeBadge`: `contentTransition(.numericText(value:))` on each axis. Add a `DeltaChip` ("+8 mm H") in `signalSoft` that fades after 2 s. Hide the chip when the change is under 0.5 mm.
- **Screenshot check.** Filmstrip as in P3 for "make it 20% taller", "add a hole" and "make it smaller". `shots/edit-changed-*.png`.
- **Cost.** 1.5 days (after P3).
- **What could go wrong.** The wireframe of a dense scan (200k triangles) is a grey haze, not lines. Use the ghost as a translucent solid with a fresnel edge instead when the triangle count is over about 20k. The stretch looks wrong when the helper also moves the model, so only stretch when the base stays put.
- **Metric.**
  - In the P3 people test, add "by about how much?" for size edits. Pass if answers land within ±25% of the true change for ≥ 4 of 5 people (baseline is likely near zero, since there is no number shown).
  - The delta chip and badge keep WCAG ≥ 4.5 on the stage at their position.

### P8. Motion tokens and step rail

- **Goal.** Motion has consistent meaning: small things are quick, moves are springs, big moments are rare. The current step is clear at a glance.
- **Files and pieces.** `Theme.swift` (`Motion` enum: `quick`, `standard`, `spatial`, `hero`, plus the slow-mo multiplier from Plan 0), every `.animation(` and `withAnimation` site, `SCNTransaction` durations in `ViewerScene.swift`, and `StepIndicator` in `Components.swift`.
- **Steps.**
  1. Add the tokens, each with a Reduce Motion variant.
  2. Replace every hard-coded duration in SwiftUI and SceneKit with a token. SceneKit gets matching `CAMediaTimingFunction` values.
  3. `StepIndicator`: three labels on a hairline, a 2 pt signal bar under the current label, moved with `matchedGeometryEffect` in a shared `@Namespace`. Done steps get a 9 pt check.
  4. Keep the accessibility label as it is today.
- **Screenshot check.** Toolbar crop from every state shot. A `CADDY_SLOWMO=10` capture of a step change at 5 timestamps.
- **Cost.** 1 day.
- **What could go wrong.** Springs that are too soft feel laggy in a pro tool. Keep `bounce: 0` and durations short. The toolbar on macOS 26 may put glass behind the rail, which Apple says status items should avoid. Set `isBordered = false` via the AppKit toolbar item if SwiftUI gives no control **(unverified in SwiftUI)**.
- **Metric.**
  - `motionLiterals` = 0 outside `Theme.swift` (baseline 6).
  - No enter animation longer than 0.4 s except the `hero` cases, which are listed by name (checked by grep on `Motion.hero`).
  - People test: show the toolbar crop alone for 2 s. Ask "which step is the app on?" Pass at 5 of 5. The baseline may already pass. If so, the rail is not justified on clarity alone, and it should be cut or kept only for the step change motion.

---

## Plans for the other ideas

Same fields, shorter. Costs assume the top 8 and Plan 0 are done.

### Identity and palette

- **Lightness-stepped neutrals (Linear style).** Folded into P2 step 1. Metric: `surfaceDeltaL` steps differ from each other by ≤ 1 L* (even steps).
- **Separate status green from signal.** Goal: status never looks like brand. Files: `Theme.swift`. Steps: shift `good` toward yellow-green (hue about 140). Check ΔE2000 ≥ 25 from `signal`, also under deuteranopia simulation. Cost 0.25 day. Risk: green on amber warning gets close. Metric: the ΔE numbers above.

### Typography

- **Display numerals.** Goal: key numbers read from across a classroom. Files: `Theme.swift` (`TextRole.display` with `.fontWidth(.expanded)`), `Overlay.swift` (coverage percent), `ViewerUI.swift` (size badge on the stage, optional), `Screens.swift` (processing timer). Steps: add the role, apply in 3 places, test at 1.4×. Check: scan, processing and edit shots. Cost 0.5 day. Risk: expanded width breaks the ring's inner label at large text, so `minimumScaleFactor` must stay. Metric: from the projector-distance test (shot shown at 25% size, which approximates a back-row view), ≥ 4 of 5 people read the number correctly, versus baseline.
- **SF Mono dimensions.** Files: `ViewerUI.swift` `SizeBadge`, `ModelInfoRows`. Steps: mono 12 medium for digits, muted unit. Cost 0.25 day. Risk: mono at 12 looks small next to 13 SF Pro. Metric: digit columns align across rows (pixel x of the decimal point the same ±1 pt in the shot).
- **Quiet section headers.** Files: `Components.swift` `SectionHeader`. Steps: 11 semibold muted, tracking 0.3. Cost 0.1 day. Risk: at Default size, 11 pt muted can fail contrast. Metric: `wcag` ≥ 4.5, and in the P2 zone test, the inspector sections are still found by 5 of 5.
- **Wordmark.** Files: `RootView.swift` toolbar, `Screens.swift` `LaunchView`. Steps: SF Pro Expanded semibold 13, tracking 1, 6 pt signal dot. Cost 0.25 day. Risk: looks like a logo for a different product next to the system title bar. Metric: none beyond consistency. Honest note: this one is mostly taste. Do it last or skip it.
- **numericText everywhere.** Files: `ViewerUI.swift`, `EditScreen.swift` (`ElapsedText`, history count), `Components.swift`. Cost 0.25 day. Risk: none worth noting. Metric: no layout shift. The width of each number's frame stays constant across 10 sampled values (measure in a slow-mo capture).

### 3D stage, beyond P1

- **Material presets.** Goal: the model can look like a print. Files: `ViewerScene.swift` (`makeMaterial` becomes three builders), `ViewerUI.swift` (a 3-item menu in the viewer toolbar). Steps: ceramic default, PLA with procedural stripe normal map (`NSImage` drawn in code, `wrapT = .repeat`, scaled to 0.2 mm in world units), X-ray. Check: stage PNGs per preset. Cost 1.5 days. Risk: the layer-line normal map aliases into moiré at normal zoom. Mipmapping (`mipFilter = .linear`) helps but may not fix it. Fade it out with distance. Metric: no moiré, meaning the FFT of the model region in the shot shows no new peak at the stripe frequency at default zoom. Simpler fallback: a person can find the layer lines at 4× zoom and cannot see them at 1×.
- **Fresnel rim.** Files: `ViewerScene.swift` material shader modifier. Cost 0.5 day. Risk: makes holes in scans glow. Metric: `edgeContrast` +3 on dark stage with no rise in `formRange` loss.
- **View cube.** Files: new `ViewCube.swift` in `CADViewer`, `EditScreen.swift` overlay. Steps: a SwiftUI `Canvas` cube projected from yaw and pitch, with hit testing on faces calling `orbit` to principal angles. Cost 2 days. Risk: duplicates the "Reset view" button and adds clutter (the v1 complaint). Metric: people task "show me the model from the top" with and without the cube. Pass if median time drops by ≥ 30%. If it does not, cut it.
- **Bed outline.** Files: `ViewerScene.swift` `rebuildGrid`. Cost 0.5 day. Risk: the bed size is unknown until there is a printer setting, and a wrong outline misleads. Use a neutral label ("250 mm plate") until then. Metric: people question "would this fit on the printer?" answered correctly from the shot by ≥ 4 of 5, for one model that fits and one that does not.

### Scan screen, beyond P4

- **Segment completion pulse.** Files: `Overlay.swift` (`keyframeAnimator(trigger: doneCount)`). Cost 0.25 day. Risk: frequent pulses distract during a scan. Cap at one pulse per 0.5 s. Metric: slow-mo capture confirms one pulse per completed segment and none at other times.
- **Complete moment.** Files: `Overlay.swift`, `ScanView.swift`. Cost 0.5 day. Risk: a once-only flourish on a screen that is used many times a lesson. Keep it at 0.8 s. Metric: in the P4 people test, add "is the scan finished?" for a 100% shot. Pass at 5 of 5.
- **Scan beam.** Files: `ScanView.swift` overlay (`phaseAnimator` on a gradient strip). Cost 0.25 day. Risk: reads as a video glitch on some footage. Metric: people question on a 5 s recording, "is the app recording right now?" Pass at 5 of 5 with the beam and the REC badge both present. Then test without the badge. If people still answer right, the beam carries meaning. If not, it is decoration and should be cut.
- **Directional chevrons.** Files: `Overlay.swift` `WarningBar` variant. Cost 0.5 day. Risk: guidance only knows direction when a pose is available (`coverage.rings`). Without a pose, the chevrons must not show. Metric: the P4 "which side next" test with chevrons on and off.
- **Dark glass HUD.** Files: `Overlay.swift` backings. Cost 0.25 day. Risk: materials over live video can lower text contrast on bright frames. Respect Reduce Transparency with a solid fallback. Metric: worst-pixel WCAG ≥ 4.5 on the busy backdrop in `overlay.png`.

### Transitions, beyond P8

- **Scan to Process hand-off.** Files: `RootView.swift` (a shared `@Namespace`), `ScanView.swift` (snapshot the last frame), `Screens.swift`. Cost 1.5 days. Risk: `matchedGeometryEffect` across a `switch` in `RootView.content` with an `NSViewRepresentable` inside is fragile, and may need the snapshot image as a stand-in. Metric: slow-mo capture shows no frame where neither the camera nor the stage is visible (no blank flash), checked on 5 sampled frames.
- **Process to Edit.** Files: `RootView.swift`, `EditScreen.swift`, `Screens.swift`. Steps: one shared stage view across both steps so only the inspector moves. Cost 1.5 days (with P3 and P6 done). Risk: shared `SCNView` across steps changes view lifetimes, a refactor risk. Metric: same no-blank-frame check, plus `frameMs` stays in budget during the move.
- **Staggered first entrance.** Files: `EditScreen.swift` inspector. Cost 0.25 day. Risk: users who reopen see it again unless the "first time" flag is stored. Metric: runs once per launch at most (checked by a debug counter).

### Edit feedback, beyond P3 and P7

- **Stretch for scale edits.** Part of P7 step 2.
- **Applying state with the model visible.** Files: `EditScreen.swift` (drop the full material overlay, add a small glass capsule), `ViewerScene.swift` (a thin emissive plane moving on y, looping). Cost 1 day. Risk: users may try to orbit and click during the wait. That is fine, since only edits are locked. Metric: in a people test with the applying shot, "can you still look around the model?" answered yes by ≥ 4 of 5, against baseline.
- **History thumbnails.** Files: `EditScreen.swift` `row`, `ViewerScene.snapshot` at 72×72 px, a small cache keyed by version. Cost 1.5 days. Risk: rendering a snapshot per version on the main thread stalls the UI after an edit. Render off screen with a separate `SCNRenderer` after the sweep ends. Metric: people task "go back to the version before the hole was added" with and without thumbnails. Pass if median time drops by ≥ 30%.

### Empty states

- **Empty plinth.** Files: `EditScreen.swift` viewer, `ViewerScene.swift` (spot pool, dashed cube geometry). Cost 0.75 day. Risk: rarely seen, since Edit usually has a model. Value is mainly for drag and drop. Metric: people question on the empty shot, "what can you do here?" Pass if ≥ 4 of 5 mention dropping a file or scanning.
- **History before first change.** Files: `EditScreen.swift` `historySection`. Cost 0.25 day. Metric: none needed beyond copy review. Low impact. Do it only if near other edits.
- **Camera states.** Files: `ScanView.swift` `CameraStateCard`. Cost 0.25 day. Metric: worst-pixel WCAG over the blurred frame.

### Icon and splash

- **App icon.** Files: `Resources/make_icon.swift`, plus a 1024 px render from `ViewerScene.snapshot` of the hero object. Steps: render the object on the dark stage, composite the ring in signal colour, keep the macOS grid (824 pt body). Cost 1.5 days, of which half is choosing the object. Risk: a rendered 3D object at 16 px becomes mush. Design the 16 and 32 px sizes as simplified variants. Icon Composer layering for macOS 26 **(unverified with this script-based pipeline)**. Metric: Dock find test. Show a screenshot of a Dock with 12 icons including CADDY at 48 px, ask "find the 3D scanning app". Pass if median time ≤ baseline and ≥ 4 of 5 find it in under 3 s. Also check the 16 px render is distinguishable from the generic document icon by a 5-person "which is the app" test.
- **Splash.** Files: `Screens.swift` `LaunchView`. Steps: stage gradient, wordmark, ring drawn with `trim` animation. Cost 0.5 day. Risk: start-up is usually fast, so this may show for under a second and flash. Show it only after 400 ms. Metric: no splash frame visible when start-up takes under 400 ms (checked with slow-mo capture and a fake fast helper).

### Light and dark, beyond P2

- **Stage palette in both modes.** Part of P1 step 1.
- **Native inspector.** Files: `EditScreen.swift` (swap `HSplitView` for `.inspector(isPresented:)`), and a toolbar toggle. Cost 1 day. Risk: `.inspector` width rules differ from today's 340 to 440 pt range. Check that large text still fits. On macOS 14 the look is subtle, on 26 it gets glass. Metric: the inspector at 1.4× text shows no clipped labels (checked by a text-truncation scan in accessibility tree, via `NSAccessibility` values of labels ending in "…"). Value is mostly fit with the system, so treat it as a lower priority.

### Micro-interactions

- **Press scale 0.96.** Files: `Theme.swift` `BigButtonStyle`, `ChipButtonStyle`. Cost 0.1 day. Metric: slow-mo capture shows scale 0.96 on press and 1.0 on release, never smaller.
- **Shadows over borders.** Part of P2 step 4.
- **Concentric radii.** Files: `Theme.swift` (`corner` 14, `buttonCorner` 6, new `innerCorner` 10), plus call sites. Cost 0.25 day. Metric: grep shows every nested pair follows outer = inner + padding (a short table in the PR).
- **Toggle icon cross-fade.** Files: `ViewerUI.swift` `ViewerToolbar`. Cost 0.25 day. Metric: no frame in slow-mo where both icons are absent.
- **Hover preview for quick changes.** Files: `EditScreen.swift` `quickSection` (`onHover`), `ViewerScene.swift` (a translucent bounding-box ghost). Cost 1.5 days. Risk: only some quick changes have a predictable result before the helper runs (taller, wider, smaller yes, add a loop no). Show the preview only for those. Hover does not exist on touch-only setups, but this is a Mac app. Metric: people task, "make it a bit wider, but not too much", count of undo presses before the person is happy. Pass if median undos fall by ≥ 1.
- **Orbit snapping with haptics.** Files: `ModelViewer.swift` gesture handling, `ViewerScene.orbit`. Cost 0.75 day. Risk: snapping fights fine control. Snap only within ±4° and only on release. Haptics only work on Force Touch trackpads. Metric: people task "show the exact front view". Pass if success rises and median time drops, versus no snapping.
- **Sound set.** Files: three `.caf` files in `Resources`, `Package.swift` resources, `ScanModel.play`. Cost 1 day, mostly making or licensing the sounds. Risk: sounds are the most personal choice here and the classroom may mute them anyway. Licensing must be clear (make them, or use CC0 with a record of the source). Metric: peak level ≤ -18 dBFS (measured with `afinfo` plus a short Swift `AVAudioFile` peak scan). Sound count stays at 3, enforced by grep on `play(`.
- **Save confirmation.** Files: `EditScreen.swift` `saveButton`. Cost 0.25 day. Risk: `.drawOn` API shape **(unverified)**, so the fallback is `.replace`. Metric: in a people test, after clicking Save, "did it save?" answered yes from the button alone by 5 of 5, versus baseline where the answer is in the status line.

### Iconography

- **One weight, outline by default.** Files: every `Image(systemName:)` and `Label(... systemImage:)` site. Steps: set `.fontWeight(.medium)` at the root, use `.fill` names only for active states. Cost 0.5 day. Metric: grep for `.fill"` returns only active-state sites, listed in the PR.
- **Three custom symbols.** Files: an `.xcassets`-free `Symbols` folder of exported SVG templates, plus `Image("name")` sites. Cost 1.5 days. Risk: SwiftPM resource bundles with custom symbol SVGs need care to load as symbols **(unverified for a SwiftPM-only build)**. Metric: each symbol matches SF Symbols stroke weight at medium. Overlay a custom symbol and an SF symbol at 13 pt and compare stroke width in pixels (±0.25 px).
- **No outside icon sets.** A rule, not a task. Metric: grep for `Image("` that are not the custom set returns 0.
- **Symbol effects with purpose.** Files: `Overlay.swift` (REC `.pulse`), `Screens.swift` (stage checks `.bounce`), `EditScreen.swift` (applying `.breathe`, macOS 15+ with fallback). Cost 0.25 day. Metric: grep shows no `.symbolEffect` with `.repeating` on any control that is idle by default.

---

## Order and total

1. Plan 0 (1.5 days).
2. P2 and P8 together (2.5 days). They are cheap and every later shot depends on the tokens.
3. P1 (3 days).
4. P3 then P7 (4 days).
5. P4 (3 days).
6. P5 and P6 (4.5 days).

Top 8 plus harness: about 18.5 days. The other ideas add about 20 days if all were done, which they should not be. Each one must pass its metric or be dropped.

**Stop rule.** If after Plan 0, P2 and P1 the blind people tests show no measurable gain over baseline, stop polishing and go back to the reconstruction and edit-quality work in `IDEAS.md`.
