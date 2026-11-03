# CADDY kid plan: Caddy the mascot, kid language, delight, safety, access

Written 2026-10-31. Plan only. No source file was changed. The highlight tutorial is planned elsewhere and is left out here.

Users are kids aged 8 to 14 in one private class with one teacher. The build is demo-grade.

Read before writing: `DESIGN_FINAL.md`, `README.md`, every file in `Sources/CADApp`, `Sources/CADShared/Theme.swift`, `Sources/CADScan/Overlay.swift`, `ScanLogic.swift` (`GuidanceText`), `ScanView.swift`, `CADViewer/ModelExport.swift`, `CADViewer/ViewerUI.swift`, `webapp/app.py`, `webapp/processing.py`, `bench/edit.py` and `guidance/guidance.py` (`MESSAGES`).

Facts marked **[ran]** were checked by running the code. The rest come from reading it.

## 0. Ground rules from earlier rulings

`DESIGN_FINAL.md` set a quiet pro look. The user called teal "childish" and ruled out confetti and added sounds. Caddy has to fit that. So:

- One Caddy per screen, at most. He sits on a solid panel, never on the 3D stage or the live video. The stage stays free of added objects.
- Caddy never carries meaning alone. Every pose comes with one line of plain text, and the text does the work. Caddy is hidden from VoiceOver.
- He changes pose when something happens. He does not idle, blink, bob or loop.
- A Settings toggle "Show Caddy" lets older kids or the teacher turn him off. The text lines stay when he is off.

### The Caddy view

One view, `CaddyView(mood:size:)`, in `CADShared` so both `CADApp` and `CADScan` can use it. `mood` is an enum: `happy`, `thinking`, `pointing`, `oops`, `celebrate`.

Until the art is chosen, each mood is an SF Symbol in a round `Theme.raised` well with `Theme.ink` line art. When art arrives, each mood becomes one image in the bundle. The call sites do not change. A pose change uses `Theme.motion(reduceMotion)` as a 0.18 s cross-fade, and with Reduce Motion it swaps instantly.

Sizes: 96 pt on the first run panel, 56 pt in the edit inspector and processing panel, 40 pt inside small cards.

The tutorial agent can reuse the same view and moods.

## 1. Where Caddy appears, screen by screen

| Screen | Where | Mood | What Caddy says (the text line) | Hardware? |
|---|---|---|---|---|
| First run (`FirstRunView`) | Top of the left panel, above the title | happy | "Hi, I'm Caddy. Let's turn a real thing into a 3D model you can print." | Buildable now |
| Launch failed (`LaunchView`) | Above the title | oops | "CADDY could not get ready. Ask your teacher to help." | Buildable now |
| Scan, before Start (`CoachCard`) | Inside the coach card, left of the steps | pointing | "Put your object in the middle of the table. Then press Start scan." | Webcam now, probe blocked |
| Scan, recording | In the side panel, never on the video | pointing, then happy | Repeats the current `WarningBar` line. Points toward the missed side once the ring has a gap. "You got every side!" at full coverage. | **Blocked on the probe.** The webcam path works today, but pointing at missed sides needs real coverage data. |
| Scan, camera problem (`CameraStateCard`) | Inside the card | oops | The card text, rewritten (section 2) | Card states exist. Probe disconnect states are blocked. |
| Processing (`ProcessingView`) | Top of the right panel | thinking | "I'm building your model. This takes about a minute." Changes once to "Almost done" at the last stage. At 60 s: "This is taking a long time. You can go back and try again." | Sample and model files work now. **Real video timing is blocked.** `processing.py` sleeps 3 s and returns the sample cup, since video to mesh does not exist yet. |
| Processing failed | Same place | oops | "That scan did not work. Try again, or use the practice cup." | Buildable now |
| Edit, empty (no changes yet) | Top of the inspector, above "Describe a change" | pointing | "Tell me a change, like 'make it taller'. Or tap a quick change." This replaces "No changes yet..." in History. | Buildable now |
| While Claude applies an edit | Inspector top, beside the Apply button's timer | thinking | "Working on it..." with the elapsed seconds. No loop. The stage dim stays as `DESIGN_FINAL` item 7 ruled. | Buildable now |
| Edit worked | Inspector top | happy | "Done! Spin it around to check it. Then save it." | Buildable now |
| Claude asks a question (ASK) | Inspector top | thinking | Claude's own short question, for example "Taller or wider?" | Needs the fix in section 4 first |
| Claude cannot do it (CANNOT) | Inspector top | oops | Claude's own short sentence | Needs the fix in section 4 first |
| Edit failed for another reason | Inspector top | oops | The kid-language error (section 2). Raw text stays in Details. | Buildable now |
| Offline (no internet) | Inspector top, plus the existing banner | oops | "I can't reach Claude right now. The quick changes still work." | Needs the fix in section 4 |
| First time the model is print-ready | Model section | happy | "Ready to print!" (section 3) | Buildable now |
| Save | Save section, beside the status line | celebrate | "Saved! Your file is called My model.stl. It is on the Desktop." plus a Show in Finder button | Buildable now |
| New scan confirm | The confirmation dialog stays plain. Caddy is not in system dialogs. | none | Dialog text rewritten: "Start a new scan? Your model will be cleared. Save it first if you want to keep it." | Buildable now |
| After New scan | Scan screen coach card | pointing | Same as "Scan, before Start" | Same as scan |

Caddy never appears in the Settings window, the Diagnostics popover, TeacherDetails or system dialogs. Those belong to the teacher.

## 2. Kid-language pass

### Rules

1. Reading age 8. Short words. One idea per sentence. Most sentences under 12 words.
2. Say what to do next. Every problem message ends with one action the kid can take.
3. Talk to the kid as "you". Caddy speaks as "I". The app does not say "the helper", "the service" or "the engine".
4. No blame. Say "That did not work". Avoid "invalid", "error", "failed".
5. Jargon goes to the teacher. These words stay out of kid strings unless they carry a gloss: watertight, triangles, mesh, manifold, faces, helper, guidance, service, coverage, tracking, processing, STL, PLY, OBJ, port, API, key, engine.
6. File types are allowed only where the kid acts on them (Save STL, Open a file). Add the gloss once: "STL is the file type 3D printers use."
7. Numbers stay real. Sizes in mm keep the existing "About as big as a golf ball" comparison.
8. The raw text stays in `TeacherDetails` under "Details". It is never deleted.
9. Model info rows for teachers (Triangles) show only when "Show diagnostics" is on.

Glosses to use, word for word:
- **Ready to print** (for watertight): "The outside has no gaps, like a balloon with no holes. A printer needs that."
- **Tiny flat pieces** (for triangles): "Your model is made of lots of tiny flat pieces stuck together."

### Ten before and after examples, from the real strings

| # | Where | Before | After |
|---|---|---|---|
| 1 | `Screens.swift` LaunchView | "The helper could not start" | "CADDY could not get ready. Ask your teacher to help." |
| 2 | `AppModel.swift` BannerKind.lostContact | "Lost contact with the helper. Trying again." | "CADDY lost its connection for a moment. Trying again." |
| 3 | `AppModel.swift` poll, status error | "The scan could not be turned into a model. Scan again, or use the sample model." | "That scan did not work. Try again, or use the practice cup." |
| 4 | `AppModel.swift` send, success | "Change applied. Check the model, then save it." | "Done! Spin it around to check it. Then save it." |
| 5 | `AppModel.swift` send, timeout | "Claude is taking too long. Check the history before you try again." | "This is taking a long time. Look at your list of changes before you try again." |
| 6 | `Integration.swift` ModelInfoRows | "Watertight: No, may not print cleanly" | "Ready to print: Not yet. There is a gap, so the printer may get it wrong." with the gloss on hover and for VoiceOver |
| 7 | `ViewerUI.swift` toolbar | "Show triangles" | "Show the tiny pieces" |
| 8 | `ScanLogic.swift` GuidanceText.lost | "Guidance service unreachable. You can keep recording." | "I stopped checking your scan. You can keep filming." |
| 9 | `ScanLogic.swift` GuidanceText.nearlyDone | "Coverage complete. Press Finish scan." | "You got every side! Press Finish scan." |
| 10 | `AppModel.swift` Ideas chip | "Scale to half size" (label), "Add a centre hole" (label) | "Make it half as big", "Poke a hole through the middle". The `text` sent to the backend stays the same, because it must match `bench/edit_cases.py`. |

More strings for the same pass, listed so none are missed:
- `AppModel.open`: "CADDY opens STL, PLY and OBJ files, and videos. This file is a different type." becomes "CADDY can't open this kind of file. Try a 3D model file or a video."
- `Screens.swift` scanTips: "Matte objects with some texture" becomes "Things that are not shiny work best".
- `GuidanceText.chips`: "Tracking lost" becomes "Can't see it". "Out of focus" becomes "Blurry".
- `ProcessingView`: the title "Processing" becomes "Making your model". "Building the model" stays.
- `ScanSidePanel`: "Open a scan file…" becomes "Open a model file…".
- `webapp/app.py` `_friendly`: already close. "Without the Claude key I only know the example changes. Tap one of those." becomes "Right now I can only do the quick changes. Tap one of those."
- `guidance/guidance.py` `MESSAGES` and the stub in `app.py`: already plain. "Lost the object. Point the camera at it and step back to where you were." is long. It becomes "I lost your object. Point at it and go back a step."
- `RootView` drop dialog: "Open this file? The current model will be cleared." becomes "Open this file? Your model will be cleared. Save it first if you want to keep it."

## 3. Feedback and delight that is not noise

### Sounds

The toggle exists (`soundEnabled`, toolbar button and Settings). Today only the scan screen plays sounds: "Tink" per finished side and "Glass" at full coverage (`ScanView.swift` around line 170).

Plan:
- Move the existing `play(_:)` gate from `ScanModel` into `CADShared` so every target uses one gate that reads `soundEnabled`. No new code path.
- Add exactly two sounds, both macOS system sounds:
  - Edit worked: "Pop".
  - Save: "Hero". This is the one celebration.
- No sound on errors. A buzzer reads as "you did it wrong" to an 8-year-old.
- No sound on undo, redo, chip taps or Caddy pose changes.
- `DESIGN_FINAL` ruled "no sounds added". These two need the user's yes (open question 2).

### Print-ready reward

After an edit, `bench/edit.py` `validate` only lets a printable mesh through. So edited models are always print-ready. The reward belongs to the moment the model first becomes print-ready, usually the first clean scan or the first edit after a scan with gaps.

- When `MeshInfo.isWatertight` goes from false or unknown to true for this model, show a "Ready to print" pill in the Model section with Caddy happy for one pose change.
- It shows once per model. It stays as a quiet green check after that.
- No sound for this one. The save sound is the only celebration sound.

### The one celebration at save

- Caddy celebrate pose, the "Hero" sound, and the line "Saved! Your file is called My model.stl. It is on the Desktop."
- A "Show in Finder" button next to the line. `ModelExport.revealInFinder` already exists.
- It holds for 8 s, which is the current note fade in `AppModel.save`. Then Caddy goes back to happy.
- No confetti. The user ruled it out.

### Rejected, and why

| Idea | Why it is out |
|---|---|
| Streaks | The class meets on a set day. A streak punishes a kid who was absent and means nothing about skill. |
| Points or XP | Nothing in the work gives a point a real meaning. More edits is not better work. |
| Leaderboards | One small private class. Ranking kids creates shame and gains nothing. |
| Badge collections, levels, "unlock" items | Invented vanity metrics. They pull attention from the model. |
| Counting edits or saves as achievements | Same reason. The History list already shows what a kid did. |
| Confetti or particle bursts | The user ruled it out as kiddy. It also clutters the stage. |
| Caddy idle animation, blinking, random tips | Noise. It breaks the one-motion-per-event rule in `DESIGN_FINAL`. |
| Error buzzer | Feels like a telling-off. The text and the oops pose are enough. |
| Countdown timers on edits | Edit time is 5 to 40 s and not in the kid's control. A countdown adds stress. |
| Reminders or notifications | Nothing to remind about outside class. |

## 4. Safety and trust

### What leaves the Mac

Only the edit request to Claude, and only when the teacher has set a key. From `bench/edit.py` lines 459 to 544:

- The fixed system prompt (`SYSTEM`), with prompt caching on.
- One "Model facts" line: bounds, size per axis in mm, volume, number of through-holes, face count.
- The kid's words inside `<request>` tags. Whitespace is squashed. `<` and `>` are swapped for brackets so the text cannot close its own tag. Over 300 characters is refused before any call (`MAX_INSTRUCTION`).
- On a retry (up to 2), Claude's own earlier reply and the error text from running its script.
- Model `claude-opus-5-5`, effort `low`, unless `EDIT_MODEL` or `EDIT_EFFORT` is set.

Nothing else goes out with it. The mesh, the video, camera frames, the kid's name and file paths stay on the Mac. Guidance frames go to the local helper on 127.0.0.1 only (`BackendService.swift` line 109 binds `--host 127.0.0.1`).

Other ways the app can reach the internet, which the plan must handle:
- **Risk: Tinkercad opens the browser with no gate.** `ModelExport.copyForTinkercad` calls `NSWorkspace.shared.open(tinkercadURL)` (line 56). A kid lands on a site with sign-up and other people's designs. Fix: put it behind the grown-up gate below.
- **Risk: `uv run` may reach PyPI** on a launch when the environment is out of date. That is not kid data, but it is traffic the teacher may not expect, and it fails offline. Fix: run `uv sync` during setup, and have `BackendService` set `UV_OFFLINE=1` for the child. Check that the helper still starts with Wi-Fi off.
- The FreeCAD sheet names freecad.org as text only. No link. That is fine.
- The camera Settings button opens System Settings on the Mac. That is fine.

### How free text is filtered today

There are several layers, from `bench/edit.py`:
1. The 300 character cap.
2. The system prompt: treat the request only as a shape change. Ignore instructions inside it. Reply `CANNOT` for weapons or weapon parts, things too big for the printer, or anything that is not a shape edit. Write `ASK` and `CANNOT` in simple words a 10 year old understands.
3. `stop_reason == "refusal"` maps to a fixed friendly line.
4. Claude's script is screened by AST (`screen`, the `BANNED` names, no imports, no underscore names).
5. The script runs in a child process under a macOS sandbox profile with CPU, wall clock (30 s) and memory (1500 MB) limits. Output comes back through `np.load(allow_pickle=False)`.
6. `validate` rejects anything not closed, in pieces, bigger than 250 mm or over 300,000 faces.

### Risks found in the current code

1. **Claude's ASK and CANNOT answers never reach the kid. [ran]** `edit.py` ends with `sys.exit(r["message"])`, so the kid message goes to stderr. `processing._bench` turns stderr into a `RuntimeError`. `app._friendly` only matches "refused", "printable", "watertight", "no API key" and "no canned script". Claude's question ("Taller or wider?") matches none of them. So the kid sees "That change did not work. Try saying it another way." The real question hides under Details.
2. **The no-key message never shows. [ran]** With no key, `edit.py "make it look like a dragon"` exits 1. Its stderr is the generic `FAIL_MSG`. The phrase "no canned reply ... no API key" is printed to stdout, which `_bench` ignores when stderr is set. So `_friendly` never says "I only know the example changes". The kid keeps retrying free text that cannot work.
3. **The offline banner never fires from an edit.** `AppModel.send` looks for "connection" or "network" in `f.detail`. The API error (`api: APIConnectionError...`) is also printed to stdout, so it never reaches `detail`. This one is from reading, by the same path as risk 2.
4. **With a key set, the quick-change chips need the internet.** `edit.py` uses the canned scripts only when there is no key. With a key, the chips go to Claude too. So the banner line "The example changes still work" is false whenever a key is set and the network is down. The chips also wait 5 to 40 s for something that has a canned answer.
5. **Claude's raw text shows under Details**, which a kid can open. It is short (capped at 300 characters by `parse`) and comes from Claude under the system prompt, so the risk is low. Once risk 1 is fixed it shows in the main line anyway, so it gets one cheap check: one line, at most 200 characters, and nothing that looks like a URL. If the check fails, show the fixed fallback line.
6. **Scan videos stay on disk.** `app.upload_scan` writes `webapp/data/scan.<ext>` and nothing deletes it. A webcam video can show kids' faces and the room. The Mac's own temp recording is deleted after upload (`deleteAfter`), but the helper's copy is not. Fix: delete it in `_process` once cleaning is done.
7. **Settings is open to kids.** Cmd+comma opens it. A kid can change the helper port (the app then fails on the next launch), turn on Diagnostics, and open `webapp/data` in Finder. The key is never shown, only "Found" or "Not set". That part is right.

### Fixes

- **One result shape from `edit.py`.** Print one JSON line on stdout: `{"kind": "edit|ask|cannot|fail", "message": ..., "reason": "no_key|offline|timeout|other"}`. `processing.apply_edit` parses it. `app.py` returns `kind` and `message` in the error body. `AppModel.send` maps `ask` to Caddy thinking, `cannot` to oops, `offline` to the banner and the offline line, and `no_key` to "Right now I can only do the quick changes." This fixes risks 1, 2 and 3 in one place, where every caller already goes through.
- **Canned first for chip text.** In `edit.py`, when the text exactly matches a `CANNED` key, use the canned script even when a key is set. This fixes risk 4. It makes chips instant and free, and it is the offline mode.
- **Offline mode.** When the reason is `offline`: show the banner, keep the chips enabled, and set the field placeholder to "Claude is offline. Tap a quick change." The field stays usable so typing is not lost.
- **Grown-up gate.** Use `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` from LocalAuthentication. That is the Mac password or Touch ID, so it is a real gate that a 14-year-old cannot guess like a sum question. Gate these: the Tinkercad button, the Helper and Claude sections of Settings, and the Diagnostics toggle. Once a grown-up unlocks it, it stays unlocked until the app quits (open question 3).
- **Delete scan videos** after processing (risk 6).

## 5. Access: Reduce Motion, VoiceOver, 1.4x text, dyslexia, motor and handedness

| Need | What exists | What is missing |
|---|---|---|
| Reduce Motion | `Theme.motion(reduceMotion)` turns every SwiftUI animation off. Spin stops (`ModelViewer` line 81). The REC dot holds still. The success bounce in `NoteView` is gated. | Caddy pose changes must use the same helper. The coming P3 sweep must snap (already ruled). Nothing else needed. |
| Reduce Transparency | The applying dim goes from 0.4 to 0.7. | `SizeBadge` and `ViewerToolbar` use `.regularMaterial`. Give them a solid `Theme.panel` fallback. |
| VoiceOver | Labels on the coverage ring, status chips, REC badge, steps, size badge, history rows, delta chip and viewer buttons. Scan messages are announced at most once per 3 s. | No announcement when an edit finishes or fails. The note appears silently. Post `AccessibilityNotification.Announcement` when `model.note` changes. Do the same for processing stage changes and for the save line. Hide Caddy from VoiceOver. The text line is the label. |
| 1.4x text | `TextSize` up to 1.4. `themeFont` scales every role. Buttons and chips grow their minimum height. The save row reflows with `ViewThatFits`. | Several fonts are fixed: `StepIndicator` (12 pt), `SizeBadge` and the delta chip (13 pt), `ViewerToolbar` icons (28 by 24 frame), `HelpSheet` (22, 15 and 13 pt), `WorkflowSteps` icons. Move them to `themeFont` or multiply by `textScale`. Caddy's size also multiplies by `textScale` up to a cap. |
| Dyslexia-friendly option | None. | An "Easier reading" toggle in Settings. It adds letter spacing (`.tracking` about 0.06 em), line spacing about 1.4, left alignment everywhere and no all-caps. Do it in the one `ThemedFont` modifier through an environment flag. A bundled dyslexia font such as OpenDyslexic is optional. The evidence for special fonts is weak, while spacing helps (open question 5). |
| Hit targets | `Theme.minHit` 28 pt. Chips are 24 pt high. | Small for an 8-year-old on a trackpad. Raise chips to 32 pt and the main buttons to 36 pt at Default size. Check that the inspector still fits at 1.4x. |
| Trackpad and mouse | Drag to rotate, scroll and pinch to zoom (`ModelViewer` `scrollWheel`, `magnify`). Menu commands for zoom and reset. | No keyboard way to rotate. Add arrow keys to orbit and plus or minus to zoom, so kids who find drag hard can still look around. Nothing needs a right-click. Keep it that way. |
| Left-handed use | The Mac swaps mouse buttons at the system level. The app does not depend on button side. | The inspector is always on the right. A "Panel on the left" option is cheap with `HSplitView` order, but nobody has asked for it (open question 7). |
| Keyboard | Shortcuts for new scan, open, sample, save, undo, redo, type a change (Cmd L), each quick change, reset view and zoom. Return applies an edit. | None for this plan. |

## 6. Build order

Effort is in working days. Each item has the check that decides success. Do the backend fix first, because Caddy's ASK and CANNOT poses depend on it.

### Buildable now

| Order | Item | Effort | Check that decides success |
|---|---|---|---|
| 1 | One JSON result from `edit.py`, parsed in `processing.py`, passed through `app.py`, mapped in `AppModel.send` (risks 1, 2, 3) | 1 d | With no key, typing "make it look like a dragon" shows the quick-changes line, not the generic one. A mock client that replies "ASK: Taller or wider?" puts that exact question in the note. With Wi-Fi off and a key set, a free-text edit shows the offline banner. Add these three cases to `webapp/test_api.py`. |
| 2 | Canned first for exact chip text (risk 4) | 0.25 d | With a key set and Wi-Fi off, all eight chips apply. With Wi-Fi on, each chip finishes in under 3 s and the cost logged is $0. |
| 3 | Delete the scan video after processing, `UV_OFFLINE=1` for the helper | 0.25 d | After a video scan, `webapp/data` holds no `scan.*` file. The helper starts with Wi-Fi off. |
| 4 | Kid-language pass (section 2) plus a jargon check script | 1 d | A small script lists every string literal in `Sources/CADApp`, `Sources/CADScan`, `Sources/CADViewer` and the kid messages in `app.py`, `edit.py` and `guidance.py`. It fails on any rule 5 word outside teacher-only views. It passes. The user reads the ten examples and approves them. |
| 5 | `CaddyView` with placeholder art and five moods, Settings toggle "Show Caddy" | 1 d | The `CADDY_DEMO` harness renders each mood in light and dark at 1x and 1.4x. With Reduce Motion, two frames 1 s apart are identical. VoiceOver skips Caddy and reads the text line. |
| 6 | Wire Caddy into each buildable screen in section 1 | 1.5 d | Each harness state shows at most one Caddy and its line. None overlaps text or the stage at 1.4x. With the toggle off, every line still shows. |
| 7 | Sounds: one shared gate in `CADShared`, add "Pop" on edit done and "Hero" on save | 0.25 d | With Sound off, no event in the app plays a sound. With Sound on, one edit plays one sound and one save plays one sound. |
| 8 | Print-ready pill and save celebration | 0.75 d | The pill shows once when the model first becomes print-ready and does not show again for later edits to that model. Save shows the celebrate pose, the file name, the folder and Show in Finder, and it settles after 8 s. |
| 9 | Grown-up gate on Tinkercad, Settings teacher sections and Diagnostics | 0.75 d | Cancelling the password prompt opens no browser and changes no setting. After one unlock, the gate does not ask again until the app quits. |
| 10 | Access fixes: announcements, fixed fonts to `themeFont`, solid fallbacks for materials, bigger chips, arrow-key orbit, Easier reading toggle | 2 d | VoiceOver says "Done" after an edit without moving focus. A search for `.font(.system(size:` in kid-facing views finds none left. Chips measure 32 pt or more at Default. Arrow keys rotate the model. Easier reading changes spacing on every screen in the harness. |
| | **Buildable total** | **8.75 d** | |

### Blocked on scan hardware (the probe, and real video to mesh)

| Order | Item | Effort | Check that decides success |
|---|---|---|---|
| H1 | Caddy in scan guidance: coach card pose, side-panel line that follows `WarningBar`, point toward the biggest gap in the coverage ring, "You got every side!" | 1.5 d after the probe works | In real probe scans, kids reach full coverage without the teacher stepping in for 3 of 4 tries. Caddy's line changes at most once every 3 s, the same as the announcement throttle. |
| H2 | Processing wait tuned to real reconstruction time | 0.5 d after video to mesh exists | On a real scan the "Almost done" line and the 60 s "taking a long time" line show at the right stage. The line changes at most once every 20 s. |
| H3 | Probe error states (unplugged, battery, lost signal) as `CameraStateCard` cards with the oops pose | 0.5 d after the probe's failure modes are known | Unplugging the probe mid-scan shows the card within 2 s with one action to take. |

## 7. Open questions for the user

1. Caddy's look. Also, should older kids be able to hide him (the plan assumes yes, a Settings toggle)?
2. `DESIGN_FINAL` said no added sounds. May the plan add "Pop" on edit done and "Hero" on save?
3. Is the Mac password or Touch ID the grown-up gate? Once per launch, or every time?
4. Should the Tinkercad button stay for kids behind the gate, or move to teacher only?
5. Easier reading: spacing only, or also bundle a dyslexia font?
6. Should kids see Claude's own ASK and CANNOT wording (the plan says yes, with a length and link check), or fixed lines only?
7. Is a "panel on the left" option needed for any kid in the class?
8. Keep scans on the Mac between classes, or delete videos right after processing (the plan says delete)?
