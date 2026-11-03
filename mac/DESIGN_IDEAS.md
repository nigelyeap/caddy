# CADDY design ideas

Written 2026-10-30. This file covers look, feel, layout, motion and identity only. No features and no engineering plans. It was written from the code (`Theme.swift`, `CADApp/*`, `CADViewer/ViewerScene.swift`, `CADScan/*`, `Resources/make_icon.swift`) and `DESIGN_NOTES.md`. The CADDY window was not open, so I took no screenshot. Nothing here was built.

Effort: **S** is under half a day, **M** is one to three days, **L** is more. Impact is visual impact from 1 to 5.
**(unverified)** marks an API or behaviour I could not confirm from Apple docs during this pass.

The package targets macOS 14. Anything marked "macOS 15+" or "macOS 26+" needs an `if #available` check with a fallback.

## Top 8, ranked

| # | Idea | Effort | Impact |
|---|---|---|---|
| 1 | **Studio stage** for the 3D view: soft studio reflections, a gradient backdrop, a grid that fades out, a faint reflective floor, contact shadows. This one change makes the app look expensive. | M | 5 |
| 2 | **Graphite and signal palette.** Cool tinted neutrals with three clear elevation levels, plus one brand colour (signal cyan) kept for spatial things only: scan coverage, edit highlights, the model's selection. | S | 5 |
| 3 | **The reveal sweep** as the one signature motion. A glowing horizontal plane sweeps up the model and leaves solid mesh behind it. Used when the first model appears, after an edit, and (downward) on undo. | M | 5 |
| 4 | **Full-bleed scan viewfinder.** Camera fills the area. Corner brackets frame the object. A coverage ring in perspective sits on the "floor" around the object. A round shutter button replaces the text button. | M | 5 |
| 5 | **First run on the real stage.** The sample model turns slowly on the studio stage behind a short headline and two buttons. This replaces the two text cards. | M | 5 |
| 6 | **Processing that shows work happening.** Frames from the video fan out, then a point cloud gathers in the centre of the same stage. This replaces the grey box with a spinner. No fake percentage. | M | 4 |
| 7 | **Edit ghost and size deltas.** The old shape stays as a faint cyan wireframe for a moment while the new one settles. The size badge counts to the new value and shows "+8 mm" in cyan. | S to M | 4 |
| 8 | **Motion tokens and a step rail.** Four named curves in place of one 0.18 s ease out everywhere. The toolbar breadcrumb becomes a small rail with a sliding indicator. | S | 4 |

## Diagnosis: what still looks plain or off

- **Three greys with no hierarchy.** `background` F3F3F4, `panel` FFFFFF and `viewer` ECECEE sit within a few percent of each other. In dark mode it is 1C1C1E, 242426 and 19191B. Nothing reads as in front of anything else. Every surface gets the same 1 pt `line` border, so borders do two jobs: structure and fake elevation.
- **No identity colour.** The accent is the system accent (blue on most Macs). The app icon is teal with an amber ring. The scan overlay ring is green. Three different colour stories, and none of them belongs to CADDY.
- **The 3D view looks like a 2010 viewer.** It has a flat solid background, a slate clay with no environment reflections, uniform grid lines that stop at a hard square edge, and a floor that shows only the shadow. Pro tools (Shapr3D, Fusion, the slicers) all use a gradient or studio backdrop and some form of image-based light. This is the biggest gap, because the model is the product.
- **The scan screen looks like a form.** The camera sits letterboxed in a black 16:9 box. Generic black 72% capsules sit over it. A flat donut sits in the corner, and a 280 pt panel repeats the tips from the first run. The moment that should feel like magic reads like a settings page.
- **The processing screen is the dead moment.** It is a system spinner in a grey rectangle for up to a minute.
- **One motion curve for everything.** Screen changes, banners, hovers and the coverage ring all use `easeOut(0.18)` and opacity. Screen changes have no sense of place. The ui-ux-pro-max motion rules flag "one duration copied to every transition" directly.
- **Edit feedback is a blink.** The new mesh crosses over in 0.2 s, then the whole model glows accent for 0.9 s. You see that something happened, not what changed. The "Applying" state covers the whole viewer in material, so the model vanishes during the wait.
- **Type has one register.** Almost everything is 13 pt or 12 pt. The biggest text is 20 pt. Numbers (sizes, coverage, counts) are the most interesting data in the app, yet they look like body text.
- **The inspector is one long scroll of equal-weight blocks.** Every chip has the same weight and every section has the same header.
- **Smaller things.** Nested radii are not concentric (8 pt card around 6 pt fields with 12 pt padding). The launch screen is a 64 pt icon and a spinner. The "CADDY" toolbar title is plain 13 pt semibold text.

## 1. Visual identity and palette

**Graphite and signal.** Cool graphite neutrals (a hint of blue, very low chroma) and one brand colour, signal cyan, named for the scan beam. Controls keep the system accent, so native controls still match the user's Mac. Signal cyan belongs to the spatial layer: coverage, the reveal sweep, edit ghosts, measurement deltas, and the icon ring. Apple's Pro apps split colour the same way. Chrome follows the system, and viewport highlights have their own colour.

| Token | Light | Dark | Use |
|---|---|---|---|
| `window` | F2F3F5 | 111214 | Window base |
| `surface` | FFFFFF | 1A1B1E | Inspector, side panels |
| `raised` | F7F8FA | 232528 | Fields, wells, chips |
| `ink` | 16181C | ECEDEF | Primary text |
| `muted` | 63666E | 9A9DA5 | Secondary text (check 4.5:1 on `raised`) |
| `hairline` | ink at 8% | white at 8% | Dividers only |
| `signal` | 0B8A99 | 3CCFDD | Brand spatial colour |
| `signalSoft` | signal at 14% | signal at 18% | Fills behind signal text |
| `stageTop` / `stageBottom` | F4F5F7 / D9DCE1 | 2A2D33 / 0E0F11 | Viewer backdrop gradient |

- **What it looks like.** Calm and darker overall. The viewport is clearly the brightest or deepest thing on screen. One teal-cyan thread runs through the scan ring, the edits and the icon.
- **How to build.** Add the tokens to `Theme` with the existing `dynamic(_:_:)` helper. Make hairlines `Theme.ink.opacity(0.08)` so they adapt over materials. Keep the old token names as aliases, since the file says other targets use them. Effort S. Impact 5.
- **Linear's approach is worth copying in spirit.** They rebuilt themes in LCH so elevation steps look even, and cut each theme to base, accent and contrast. Here that means picking the three neutrals by equal lightness steps, not by eye. Effort S. Impact 3.
- **Status colours stay as they are,** but move them away from the brand. `good` green must never look like `signal`. Effort S. Impact 2.

## 2. Typography

- **Add a display register for numbers.** Coverage percent, the size readout and the processing timer use SF Pro at 28 to 34 pt, with `.fontWidth(.expanded)` (macOS 13+) and `.monospacedDigit()`. Units ("mm", "%") sit in `muted` at half size, baseline-aligned. Build with a new `TextRole.display`. Effort S. Impact 4.
- **Dimensions in SF Mono.** "40 × 40 × 48" in SF Mono 12 medium and "mm" in muted. This looks like a CAD readout without a third-party font. Effort S. Impact 3.
- **Quieter section headers.** Inspector headers become 11 pt semibold `muted` with `.tracking(0.3)`, like Xcode and Final Cut. Content takes the 13 pt weight. This adds hierarchy for free. Effort S. Impact 3.
- **Wordmark.** "CADDY" in SF Pro Expanded semibold, tracking +1, with a 6 pt signal dot or a tiny ring glyph before it. Used in the toolbar, the splash and the About box. Effort S. Impact 3.
- **Keep** SF Pro, sentence case and the text size multiplier. Use `.contentTransition(.numericText())` on every number that changes. It is already on the coverage ring. Add it to size, volume, triangles and the elapsed timer. Effort S. Impact 3.

## 3. The 3D viewer stage

This is the single biggest lever. Everything below is SceneKit, already in use.

| Idea | What it looks like | How to build | Effort | Impact |
|---|---|---|---|---|
| Studio light environment | Soft highlights roll across curves as you orbit. Matte clay suddenly looks like a real object. | Draw a 1024×512 equirect `NSImage` in code: dark gradient plus two or three soft white rectangles as softboxes. Set `scene.lightingEnvironment.contents` and `intensity` ≈ 1.2. No asset download needed. Reduce the directional lights to key plus rim. | M | 5 |
| Cyclorama backdrop | A vertical gradient that is lighter behind the model and darker at the bottom, with a soft vignette. Reads as a photo studio. | `scene.background.contents` = a gradient `NSImage` built from `stageTop` and `stageBottom`, or `SCNCamera.vignettingIntensity` ≈ 0.4 and `vignettingPower` ≈ 1. | S | 5 |
| Grid that fades | Fine 10 mm lines plus stronger lines every 50 mm. They fade to nothing toward the edge, with no hard square boundary. | Split into minor and major geometry. A fragment shader modifier on the grid material multiplies alpha by `1 - smoothstep(r*0.6, r, length(worldXZ))`. Set `blendMode = .alpha`. | S | 4 |
| Faint reflective floor | A trace of the model is mirrored in the floor and fades within a few millimetres. Feels like a satin plinth. | `SCNFloor.reflectivity` ≈ 0.06 to 0.1, `reflectionFalloffEnd` ≈ radius × 0.5. Keep the shadow-only look by also giving the floor material a low-alpha diffuse. Reflection doubles the render cost (Apple docs). | S | 4 |
| Contact shadow and AO | The model sits on the floor. Creases and holes darken a little. | `SCNCamera.screenSpaceAmbientOcclusionIntensity` ≈ 0.6 to 1 **(unverified on this SceneKit version)**. Keep the current soft deferred shadow and tighten `shadowRadius` near the base. | S | 4 |
| Material presets | Default "Matte ceramic" (warm off-white, roughness 0.55, a hint of clearcoat). Optional "PLA" (the chosen filament colour, roughness 0.4). Optional "X-ray" (signal edges, 15% fill). | Three `SCNMaterial` builders. For PLA, add a procedural stripe normal map at 0.2 mm pitch along the build axis, so close-ups show faint layer lines. | M | 4 |
| Fresnel rim | A thin bright edge on the silhouette. It separates the model from a dark backdrop without a hard outline. | `.surface` shader modifier: `_surface.emission.rgb += signalRim * pow(1 - dot(_surface.normal, _surface.view), 3) * 0.15`. Keep it subtle. | S | 3 |
| Tone mapping | Richer contrast with no blown highlights. | `camera.wantsHDR = true`, a fixed `exposureOffset`, `wantsExposureAdaptation = false`, `bloomIntensity` ≈ 0.15 only on signal emissive bits. | S | 3 |
| View cube | A small orientation cube in the top right, like Fusion. Faces read Top, Front and Right. Clicking a face swings the camera there. | A second small `SCNView` sharing the camera rotation, or a SwiftUI `Canvas` cube drawn from yaw and pitch. | M | 3 |
| Bed outline | A thin rounded rectangle on the floor at the printer's bed size, with a tiny label. It turns the grid into a "print plate". | One more line geometry in `rebuildGrid`. | S | 3 |

Mark the stage colours as their own tokens. The stage should stay a stage in both light and dark mode, never a flat panel colour.

## 4. The scan screen as the hero moment

- **Full bleed.** The camera fills the whole content area with `aspectFill` and 12 pt continuous corners and a 1 pt inner white-at-10% outline. The 280 pt side panel goes away while scanning. Tips live on a pre-scan overlay card only. Effort S. Impact 5.
- **Viewfinder brackets.** Four thin L-shaped corner brackets in white at 70% frame the target area. They ease 6 pt inward and turn signal when the object is centred and in focus. Build: a `Shape` of four corner paths, with an animated inset bound to guidance state. Effort S. Impact 4.
- **Coverage orbit in perspective.** The 12 segments become a ring lying on the table around the object, in place of a flat donut in the corner. Covered segments fill with signal and get a soft glow. Missing segments stay as a dashed white track. A small comet dot marks the current camera angle when a pose is known. Build: the existing `SegmentArc` ring inside `.rotation3DEffect(.degrees(68), axis: (1,0,0))`, anchored at the bottom centre, plus `.shadow(color: signal, radius: 6)` on filled arcs. The percent moves to a display-size readout under the ring. Effort M. Impact 5.
- **Segment completion.** When a side completes, its arc fills in 0.25 s, then pulses once (scale 1 to 1.06 to 1) with the existing Tink sound. Build: `.keyframeAnimator(trigger: doneCount)`. Effort S. Impact 4.
- **Complete moment.** At 100% one light sweep runs round the ring. The brackets turn green for a moment. The shutter button changes to "Finish" with a check. Build: an angular gradient mask with `rotationEffect` driven by `keyframeAnimator`, once only. Effort S. Impact 4.
- **Scan beam.** While recording, a faint horizontal signal line (2 pt, 30% opacity, soft falloff) drifts slowly up and down the frame. It says "capturing" without words. Build: a `LinearGradient` strip with a `phaseAnimator` offset loop, off with Reduce Motion. Effort S. Impact 4.
- **Directional guidance.** "Move left" style hints show a short row of three chevrons that ripple in the direction of travel, not text alone. Build: `Image(systemName: "chevron.right")` × 3 with staggered opacity in a `phaseAnimator`. Effort S. Impact 3.
- **HUD styling.** Replace black 72% capsules with dark glass: `.ultraThinMaterial` with `.environment(\.colorScheme, .dark)`, a 1 pt white-at-12% border, and 11 pt medium text. On macOS 26, `.glassEffect()` **(unverified on this target, needs availability check)**. Effort S. Impact 3.
- **Shutter button.** A 56 pt round button under the video: a white ring with a red disc that morphs into a rounded square when recording, like the Camera app. Elapsed time sits beside it in SF Mono. Build: one `RoundedRectangle` whose corner radius and size animate between states, with `.spring(duration: 0.35, bounce: 0)`. Keep the Space shortcut. Effort S. Impact 4.

## 5. Transitions between the three steps

- **Motion tokens.** Replace the single curve with four:
  - `quick`: easeOut 0.12 s, for hover and colour.
  - `standard`: easeOut 0.22 s, for panels appearing.
  - `spatial`: `.spring(duration: 0.4, bounce: 0)`, for things that move or resize.
  - `hero`: `.spring(duration: 0.8, bounce: 0)`, for once-per-session moments.
  Exits run at about 70% of enter time. All return nil with Reduce Motion, as now. Effort S. Impact 4.
- **Step rail.** The toolbar breadcrumb becomes three small labels on a hairline with a 2 pt signal bar under the current step. The bar slides along with `matchedGeometryEffect` when the step changes. Completed steps get a tiny check. Effort S. Impact 3.
- **Scan to Process.** The last camera frame freezes and shrinks into the processing stage, then dims and desaturates as frames fan out from it. Build: snapshot the preview layer to an image, then `matchedGeometryEffect` between the camera container and the stage container. Effort M. Impact 4.
- **Process to Edit.** The point cloud tightens, then the reveal sweep (section 6) builds the mesh from the floor up. The inspector slides in from the trailing edge 120 ms later. Build: shared stage view across both screens, so only the inspector animates. Effort M. Impact 5.
- **Staggered entrance, first time only.** On first arrival in Edit, inspector sections fade up 8 pt in sequence, 60 ms apart. Never on later visits. Effort S. Impact 2.

## 6. Edit feedback: how a change visibly happens

- **Reveal sweep (signature).** A thin glowing signal plane rises through the model. Below it is the new solid mesh. Above it is the old mesh as a faint ghost. The sweep takes 0.7 s. Undo runs it downward. Build: a `.surface` shader modifier with `#pragma arguments float u_reveal`. Convert `_surface.position` to world space via `scn_frame.inverseViewTransform` and discard above `u_reveal`. Add emission in a 1 mm band at the cut. Animate `u_reveal` with a `CABasicAnimation` on the material key **(animating custom shader arguments unverified)**. Effort M. Impact 5.
- **Ghost of the old shape.** For about 1.2 s after a change, the previous mesh stays as a signal-coloured wireframe at 20% opacity, then fades. You can see what grew, shrank or got cut. Build: keep the old node, swap its material to `fillMode = .lines` plus constant signal colour, and fade its opacity in an `SCNTransaction`. Effort S. Impact 4.
- **Scale changes look like scaling.** For "make it taller" style edits, animate the old node's scale to the new bounding box before the swap, so the shape stretches and does not just fade. Effort S. Impact 4.
- **Delta chips.** The size badge counts to the new value (`numericText`). A small signal chip "+8 mm H" appears beside it for 2 s. Effort S. Impact 4.
- **Applying state keeps the model visible.** Drop the full-viewer material blanket. Instead, a slow scan beam loops over the model (the same beam as the scan screen, now in 3D, as a thin emissive plane moving on y). A small glass capsule shows "Applying" and the elapsed time. Effort S to M. Impact 4.
- **History with thumbnails.** Each version row gets a 36 pt rendered thumbnail from `ViewerScene.snapshot`, on the stage backdrop. The current row has a 2 pt signal leading bar in place of the grey fill. Effort M. Impact 4.

## 7. Empty states

- **First run.** The sample model turns slowly (the existing 18 s spin) on the full studio stage. Over the left third sits a 28 pt display headline, one sentence, and the two buttons. The three steps sit as a slim row of numbered labels at the bottom. The cards go away. Effort M. Impact 5.
- **Viewer with no model.** An empty plinth: the fading grid, a soft spotlight pool on the floor, and a dashed signal outline of a cube where the model will stand. One line: "Drop a scan file here or start a scan." When a file drags over, the dashed cube brightens and the pool widens. Effort S. Impact 4.
- **History before the first change.** A single muted line with a small "sparkle on cube" symbol and the three most useful quick changes as inline suggestions. Effort S. Impact 2.
- **Camera states.** No camera, denied or busy each get a large thin SF Symbol (`video.slash`, `lock.shield`) in white at 50% on a blurred dark frame. Avoid plain black. Effort S. Impact 2.

## 8. App icon and splash

- **Icon.** A dark graphite squircle with a soft top light. In it, a matte off-white faceted object (a low-poly vase or mug, sitting slightly off centre) is rendered on the app's own stage. A thin signal-cyan scan ring orbits at a tilt with one segment missing. The amber and teal go, so the icon matches the app. Build: render the hero object with `ViewerScene.snapshot` at 1024 px and composite it in `make_icon.swift`. For macOS 26, layer it in Icon Composer so it picks up Liquid Glass **(unverified for this build pipeline)**. Effort M. Impact 4.
- **Splash and launch.** Replace "64 pt icon plus spinner" with the stage backdrop gradient, the wordmark centred, and the scan ring drawing on underneath (`trim(from:to:)` animated over 1.2 s, then a slow loop). If start-up fails, the ring stops and turns `bad`, and the message appears below. Effort S. Impact 3.

## 9. Light and dark

- **Dark is the hero look** for screenshots, demos and projectors. Light must still feel deliberate. Effort S. Impact 3.
- **The stage keeps its own palette in both modes.** Light: a pale studio grey with a cool cast. Dark: deep graphite. Never the same colour as the panels. Effort S. Impact 4.
- **Elevation by lightness, not borders.** In dark mode, higher surfaces are lighter (111214, 1A1B1E, 232528). In light mode, the inspector is pure white on F2F3F5, with an 8% hairline only where two equal surfaces meet. Effort S. Impact 4.
- **Signal has two values.** A deeper teal in light mode keeps 4.5:1 on white for text. The brighter cyan in dark mode carries the glow. Effort S. Impact 3.
- **Native chrome.** Use SwiftUI `.inspector(isPresented:)` (macOS 14) for the right panel, in place of `HSplitView`, to get the system inspector look and the toggle. On macOS 26, Apple says inspectors get edge-to-edge glass automatically, and toolbar items get glass unless `isBordered` is false. Keep the step rail un-glassed, since Apple says status items should avoid glass. Effort M. Impact 3.

## 10. Micro-interactions and sound

- **Press scale 0.96** on chips and buttons (`scaleEffect(configuration.isPressed ? 0.96 : 1)` with the `quick` curve). Never below 0.95. Effort S. Impact 3.
- **Shadows for elevation, borders for structure.** Chips and floating viewer controls lose the 1 pt border and get two stacked soft shadows (y 1 blur 2 at 8%, y 4 blur 12 at 6%). Dividers stay as hairlines. Effort S. Impact 3.
- **Concentric radii.** Outer = inner + padding. With 6 pt fields and 8 pt padding, the card should be 14 pt. Pick 6, 10 and 14 as the radius set. Effort S. Impact 2.
- **Toggle icons cross-fade** with scale 0.25 to 1, opacity 0 to 1 and blur 4 to 0 (the make-interfaces-feel-better values). Or use `.contentTransition(.symbolEffect(.replace))`, already used on the sound button. Effort S. Impact 2.
- **Quick-change chips preview on hover.** Hovering "Taller" shows a 30% signal ghost of the stretched bounding box in the viewer. Pure feedback, no edit. Effort M. Impact 4.
- **Orbit snapping with haptics.** When an orbit drag passes a principal view (front, side, top), the camera settles there and the trackpad gives a light tick through `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, ...)`. Effort S. Impact 3.
- **Sound set.** Three short, quiet custom sounds (bundled `.caf`, around -18 dB), all behind the existing Sound toggle:
  - a soft tick when a scan side completes,
  - a two-note chime when coverage reaches 100%,
  - a low "thock" when an STL saves.
  No sound on ordinary edits, as `DESIGN_NOTES.md` already decided. Effort S. Impact 2.
- **Save confirmation.** Save STL shows `checkmark` drawing on in the button for 1.2 s, then returns to its label. Build: `.symbolEffect(.drawOn)` on macOS 26 **(unverified API shape)**, falling back to `.replace`. Effort S. Impact 2.

## 11. Iconography

- **SF Symbols only, one weight.** Medium weight to match 13 pt medium labels. Hierarchical rendering for multi-layer symbols. Outline by default, fill only for the active state (the viewer toggles already follow half of this). Effort S. Impact 2.
- **Three custom symbols** for things SF Symbols lacks: "cube inside scan ring" (Scan), "cube with sparkle" (Edit), "mesh repair". Make them from SF Symbol templates in Apple's SF Symbols app, so they get weights and effects for free. Effort M. Impact 3.
- **No outside icon sets.** The better-icons skill pulls Lucide, Tabler and others through Iconify. Mixing them with SF Symbols breaks stroke matching. Use them only as sketch references for the custom symbols. Effort S. Impact 1.
- **Symbol effects with purpose only.** `.pulse` on REC, `.bounce` once on a completed step check, `.breathe` on "Applying" (macOS 15+). Never on idle chrome. Effort S. Impact 2.

## Avoid

- Rounded fonts, big filled buttons, step pills and decorative illustrations. Version 1 was called childish for these.
- A second accent on controls. Signal stays in the spatial layer.
- Neon glow, heavy bloom, lens flare, depth of field, chromatic aberration on the model. These read as gaming, not CAD.
- Glass on everything. Only floating controls over the viewer and the scan HUD. Apple keeps status items off glass.
- Animated mesh-gradient backgrounds behind the UI. Pretty in a demo, noisy in a 40 minute lesson.
- Fake progress bars or percentages while processing. Already rejected, still right.
- Motion on high-frequency actions (typing, every hover, every edit chime).
- Confetti, emoji, mascots.
- Hard grid edges, pure black viewport backgrounds and pure white light-mode stages.
- Third-party fonts. SF Pro widths and SF Mono give enough range.

## Sources

- Apple, WWDC23 "Meet Object Capture for iOS": capture dial that shows which sides have enough images, point cloud overlay. https://developer.apple.com/videos/play/wwdc2023/10191
- Apple, WWDC25 "Build an AppKit app with the new design": glass sidebars and inspectors, toolbar glass, status items without glass. https://developer.apple.com/videos/play/wwdc2025/310/
- Apple, WWDC25 SF Symbols 7: Draw On and Draw Off. https://developer.apple.com/videos/play/wwdc2025/337/
- Apple docs, `SCNFloor.reflectivity` and reflection falloff, `SCNCamera.bloomIntensity` (needs `wantsHDR`). https://developer.apple.com/documentation/scenekit/scnfloor
- Linear, "How we redesigned the Linear UI" (LCH themes, three inputs) and "Behind the latest design refresh" (supporting chrome recedes). https://linear.app/now/how-we-redesigned-the-linear-ui and https://linear.app/now/behind-the-latest-design-refresh
- OrcaSlicer source mirror: a commit adding a radial gradient background to the 3D view. https://git.trueserve.org/PublicCodeMirror/OrcaSlicer-bambulab/commit/510b472b519509db77fa98bd46f48410161341a1

Not verified this pass: Polycam and Scaniverse live coverage visuals (only third-party write-ups found), Shapr3D and Fusion specifics (from memory), `screenSpaceAmbientOcclusionIntensity`, animating custom SceneKit shader arguments, `.glassEffect()` and `.symbolEffect(.drawOn)` availability on this target, and `MeshGradient` (believed macOS 15+, not used above).
