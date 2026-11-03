# UX notes

Two parts. Part 1 is what changed in the web app and what was checked. Part 2 is the design spec for the native SwiftUI Mac app that replaces the web UI. The local API it talks to is in `API.md`.

## Part 1. Web app changes

The web UI will be replaced, so this was kept to cheap, high-value fixes. The API work carries over to the Mac app.

### What changed

Server (`app.py`)
- Redo. Undo moves a version to a redo stack. Redo brings it back. A new edit clears it. New `POST /api/redo`.
- Edits no longer hold the state lock for 30 seconds or more. Status polls stay fast during an edit. A second edit, or undo and redo, during an edit gets a clear 409.
- One error shape everywhere: `{"detail": {"message", "detail"}}`. The message is plain words for the kid. The detail is the raw text for the teacher.
- Edit failures are mapped to plain messages: no Claude key, Claude refused, shape broke, took too long.
- The model and its history survive a server restart (`data/state.json`).
- State says when the model is the sample cup (`sample`) and when the scan started (`started`).
- Old STL versions are cleared when a new scan starts.
- `test_api.py` checks every endpoint and the JSON shapes against a running server.

Page (`static/`)
- Step indicator with numbers, done ticks and `aria-current`.
- First-run coach card on the camera view. A "waiting for the camera" hint if the permission prompt sits unanswered.
- Camera errors by cause: blocked, no camera, in use by another app, not on localhost, unplugged. Each has a retry button. The sample button turns primary.
- Light and focus checks run before Start, so the room can be fixed first. The ring only shows while recording.
- Overlay: bigger chips with a dot and a word, thicker ring, warning box with a border, a green "Good. Keep walking slowly." when nothing is wrong, "All the way round. Press Finish scan." at 95 percent, a REC timer.
- If guidance stops answering, the chips go grey. Old green chips are never left up.
- "Open a scan file" accepts STL, PLY, OBJ or video. This is the backup when the camera fails in class.
- Progress screen lists real stages: sending (real upload percent), building, ready. It shows elapsed seconds and no fake percentage. After 60 seconds it says it is slow and offers Back.
- Failed scan: plain message, teacher details folded away, Try again and Use a sample.
- Edit screen: example chips that match the canned scripts, so they work with no key. Ten show, the rest sit under "More ideas". "Name on it" only fills the box. Enter sends, Shift and Enter adds a line. The button shows "Working on it, 12 s". The viewer shows a busy layer.
- History marks the current version and shows undone ones struck through. Empty history says what to do.
- Undo and Redo buttons plus Cmd Z and Shift Cmd Z.
- Viewer: size readout in mm, "Sample cup" badge, Reset view, a slow first turn that stops on touch, arrow keys to turn, plus and minus to zoom, a floor grid.
- three.js loads only when the viewer opens. Scanning still works without the internet.
- Lost contact banner with auto retry. When the server comes back without the model, the page goes back to Scan and says why.
- Light and dark themes with a toggle that is remembered. Reduced motion stops the spinner, REC blink, auto turn and press scale.
- Layout for desktop, 768 px tablet and phone widths.

### What was verified

- `uv run python test_api.py http://localhost:8011` prints ok. It covers sample scan, status shape, STL download, canned edit, undo, redo, empty edit, bad frame, real JPEG frame and reset.
- In the browser pane: camera blocked state, sample flow through all three steps, a canned chip edit, undo then redo by keyboard, a free text edit with no key (plain message plus teacher details), the busy state during an edit.
- Overlay legibility on a busy photo behind the video at 1280 px.
- Edit screen at 1280 px dark and 768 px light. Scan screen at 800 px.
- Server killed: lost contact banner appears. Server back with saved state: model kept. Server back without it: page returns to Scan with a message.
- No console errors apart from the expected 500 from the no-key edit.

### What was not verified

- A live camera. The browser pane blocks camera access. Recording, MediaRecorder output in Safari, the real guidance engine on real frames and the "waiting for permission" hint are untested.
- Upload progress on a large video.
- Claude edits with a real key. Only canned scripts and the no-key path ran.
- Touch on a real iPad, and a real projector.
- Offline viewer message. three.js still comes from a CDN.

## Part 2. Native Mac app design spec

### Principles

- Readable from the back of a classroom. Body text is 20 pt, bigger than normal Mac apps.
- One thing to do per screen, and one big button for it.
- Always tell the truth about what the app is doing and how long it has taken. No fake progress.
- Every failure has a way forward on the same screen.
- Colour is never the only signal. Every state also has a word and a symbol.

### Window and structure

- One window. Minimum 1024 by 700 pt. Opens at 1280 by 800. Supports full screen for the projector.
- Unified toolbar. Left: app name. Centre: the step indicator. Right: Sound toggle and a "Text size" menu (Large, Larger, Largest) for the projector.
- No sidebar. The flow is linear and kids should not wander.
- The content area swaps between Scan, Clean up and Change. Use a 0.25 s crossfade, none with Reduce Motion.
- A full-width banner under the toolbar for app-wide problems: server starting, lost contact, model lost.
- The Python server runs as a child process. The app owns its start and stop. See `API.md`.

### Step indicator

Three capsules: 1 Scan, 2 Clean up, 3 Change and print.
- Current: accent fill, white number in a white circle, semibold label.
- Done: green circle with a checkmark SF Symbol, green label.
- Ahead: grey outline circle, secondary label.
- VoiceOver reads "Step 2 of 3, Clean up, current".
- Steps are not buttons. Moving back happens through screen buttons only, so a model is never lost by a stray click.

### Screen: launch

- While the server starts: app icon, "Getting ready" and a small spinner. If it takes more than 10 s: "This is taking longer than usual." plus a Show details button with the server log tail.
- If the server never answers in 30 s: "The app could not start its helper." Buttons: Try again, Show details.
- If a saved model exists, open straight on Change. Otherwise open on Scan.

### Screen: first run

Shown once per Mac, and again from Help.
- Three cards in a row, each with an SF Symbol and one line:
  - "Put your object in the middle of a table."
  - "Walk slowly all the way around it."
  - "Type a change and print it."
- Primary button: "Start". Secondary link: "Try it with a sample first".
- This is also where the camera permission is asked. The system prompt appears only after the user presses Start, never on launch.

### Screen: scan

Layout: live camera fills the content area with 24 pt margins and 18 pt corners, 16 by 9. Controls sit in a bar under it.

Overlay on the camera, top-left: three chips (Speed, Light, Focus). Top-right: coverage ring, 200 pt, with the percent in the middle. Bottom-centre: the message box. Bottom-left while recording: REC dot and time.

Control bar: "Start scan" (large primary). While recording it becomes "Finish scan" in red. Then the secondary buttons "Use a sample" and "Open a scan file" (hidden while recording). A camera picker menu sits at the right when more than one camera exists, so an iPhone through Continuity Camera can be the probe.

States
- Ready, before Start. Coach card over the lower half of the video: "Get ready to scan" and the three steps. Light and focus chips are live. The ring is hidden. If light or focus is bad, the message box says how to fix it.
- Recording. Coach card gone. Ring visible. Message box shows the first warning, or "Good. Keep walking slowly." in green.
- Nearly done. At 95 percent: "All the way round. Press Finish scan." The Finish button gets a soft glow.
- Checks stopped. Three failed frames in a row: chips go grey and read "Speed", "Light", "Focus". Message: "The checks are not answering. Keep going slowly."
- Practice mode. When the engine is `stub`, a small note under the bar: "Practice mode: the ring fills on a timer. Light and focus checks are real."
- Empty recording. "The recording was empty. Press Start scan and try again."

Camera permission and device states, each shown as a centred card on a dark camera area, with the camera overlay hidden:

| State | Title | Text | Buttons |
| --- | --- | --- | --- |
| Not asked yet | Let us use the camera | We need the camera to see your object. Nothing is saved until you press Start scan. | Allow camera |
| Denied or restricted | The camera is blocked | Ask your teacher to turn on the camera for this app in System Settings. | Open System Settings, Use a sample |
| No camera | No camera found | Plug in a camera or connect an iPhone. Then press Try again. | Try again, Use a sample |
| In use | Another app is using the camera | Close Zoom, FaceTime or Photo Booth. Then press Try again. | Try again, Use a sample |
| Disconnected mid-scan | The camera stopped | Check the cable, then press Try again. Your recording was not kept. | Try again |

"Open System Settings" deep links to Privacy and Security, Camera.

Overlay rules
- Overlay colours are fixed and do not follow the theme. They sit on live video.
- Every overlay element has a 78 to 85 percent black backing. Text is white or yellow with no thin weights.
- Chip shape: capsule, 3 pt border, a coloured dot and a word. Good is green with a checkmark. Bad is red with an exclamation mark and a red tint.
- Ring: 12 segments with white 4 pt gaps. Empty is 50 percent black. Partly done is orange. Done is green. Each segment also has a tick when done, for colour-blind kids.

### Screen: clean up (processing)

Centred column, max 560 pt wide.
- Title: "Making your 3D shape".
- A checklist of real stages: "Sending the video 42%", "Building the shape", "Ready to change". Done stages get a green tick. The current one is bold with a small spinner.
- "Time so far: 14 s" in tabular digits.
- After 60 s: "This is taking longer than usual. You can keep waiting or go back." and a "Back to scan" button.
- Sample: the first stage reads "Loading the sample".

Failed state
- Title: "That scan did not work".
- Text: "The scan could not be turned into a shape. Try the scan again, or use the sample model."
- A disclosure: "Details for the teacher", with the raw error in a monospaced, selectable box and a Copy button.
- Buttons: "Back to scan" (primary), "Use a sample".

### Screen: change and print

Layout: an HSplitView. Left: 3D viewer, at least 60 percent. Right: inspector panel, 360 to 440 pt.

Viewer
- RealityKit or SceneKit view. Soft studio light, a faint floor grid at the base.
- Top-left badge "Sample cup" in amber when `sample` is true.
- Top-right size pill: "40 × 40 × 48 mm", with the help tag "Width by depth by height".
- Bottom-left: "Reset view". Bottom-right hint: "Drag to turn. Pinch to zoom."
- On first open the model turns slowly once. It stops at the first touch. Off with Reduce Motion.
- Busy layer during an edit: dim the model, show "Claude is writing the change. 12 s".
- Model swap after an edit: crossfade 0.2 s, keep the camera where the kid left it.

Inspector, top to bottom
- "What do you want to change?" field, two lines, grows to five. Placeholder: "Make it 20 percent taller".
- Primary button "Make the change". While busy: "Working on it, 12 s", disabled.
- "Or tap an idea:" then a wrapping row of capsule chips: Taller, Half the size, Add a base plate, Flat bottom, Hole in the middle, Peg on top, Cut in half, Keyring loop, Name on it, Number 7 on top. A "More ideas" fold holds the rest (ears, eyes, wings, crown, hollow, lid, handle, coin slot, legs, studs, twist and more). Tapping fills the field with the full sentence and sends it, so kids see the words that worked. "Name on it" fills the field and leaves the cursor at the end for the name.
- Message area, below the chips.
- "Changes" heading with Undo and Redo buttons on the same line.
- History list. Current version bold with "(now)". Undone versions struck through and secondary. Empty: "No changes yet. Type one above or tap an idea."
- "Save STL" primary button. Then a disclosure "How to open it", with one line each for Tinkercad and FreeCAD.
- "Scan something new" secondary button at the bottom. It asks first: "Start a new scan? This model will be cleared." Buttons: Start new scan, Cancel.

Edit messages

| When | Message |
| --- | --- |
| Empty field | Type what you want to change first. Or tap an idea. |
| Success | Done. Turn it around to check, then save it. |
| No Claude key | Without the Claude key I only know the example changes. Tap one of those. |
| Claude refused | Claude would not make that change. Try asking for something else. |
| Shape broke | That change broke the shape, so I kept the old one. Try it a different way. |
| Took too long | That took too long. Try a simpler change. |
| Client timeout | Claude is taking too long. Wait a little, then look at the list of changes before you try again. |
| Busy | Still working on the last change. Wait a moment. |
| Other failure | That change did not work. Try saying it another way. |

Errors get a red tinted box and "Details for the teacher". Success gets a green box that fades after 6 s.

### App-wide states

| State | Banner text | Behaviour |
| --- | --- | --- |
| Lost contact | Lost contact with the helper. Trying again. | Retry every 3 s. The current screen stays. Buttons that need the server are disabled. |
| Helper restarted, model gone | The app restarted and the model was lost. Scan again or use a sample model. | Go to Scan. Amber banner. Cleared by the next scan. |
| No internet, Claude needed | Claude needs the internet. The example changes still work. | Shown when a free text edit fails on network. Chips stay enabled. |

### Components

- StepIndicator
- Banner (error red, info amber)
- BigButton (primary, destructive, secondary)
- GuidanceChip (neutral, good, bad)
- CoverageRing (12 segments, percent label)
- OverlayMessage (warning, good)
- CoachCard
- CameraStateCard (title, text, up to two buttons)
- StageChecklist with ElapsedTimer
- TeacherDetails disclosure with Copy
- ModelViewer with SizePill, SampleBadge, BusyLayer
- IdeaChip
- HistoryList (current, past, undone, empty)
- ConfirmDialog (new scan)

### Type scale

Sizes are at the default "Large" text size. "Larger" multiplies by 1.2, "Largest" by 1.4. Use SF Pro, with SF Pro Rounded for headings and chips, which reads friendlier for kids. Use monospaced digits for every timer and percent.

| Role | Size pt | Weight |
| --- | --- | --- |
| Screen title | 34 | Bold |
| Section heading | 24 | Semibold |
| Body and buttons | 20 | Regular, buttons Semibold |
| Big button | 24 | Semibold |
| Overlay message | 28 | Heavy |
| Chip | 20 | Heavy |
| Secondary and hints | 17 | Regular |
| Teacher details | 14 | Monospaced |

### Spacing and shape

- Spacing steps: 4, 8, 12, 16, 24, 32, 48.
- Screen margin 24. Panel padding 20. Gap between buttons 12.
- Radii: panels 18, buttons 12, chips full capsule. Nested radius equals outer radius minus padding.
- Hit areas at least 44 by 44 pt. Big buttons 60 pt tall.
- Panels use a soft shadow for depth, with no border.

### Colour tokens

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| background | #F4F1EA | #12171B | Window |
| panel | #FFFFFF | #1B2329 | Inspector, cards |
| ink | #1B252D | #EEF2F4 | Main text |
| muted | #4C5861 | #A9B4BB | Secondary text |
| accent | #1F6B65 | #4FC1B6 | Primary buttons, current step |
| onAccent | #FFFFFF | #08201E | Text on accent |
| ok | #2E8B4F | #48C774 | Done, success |
| warn | #C77A0A | #F0A020 | Sample badge, info banner |
| bad | #C0372C | #FF6B5E | Errors, Finish scan |
| line | #D6CFC2 | #2F3B43 | Dividers, field borders |
| viewer | #F7F5F0 | #1E272D | 3D background |
| focus | #1A5FD0 | #8AB4FF | Focus ring |

Overlay, the same in both themes: backing black at 78 to 85 percent, text white, warning yellow #FFD36B, good #48C774, bad #FF6B5E, ring partial #F0A020. Body text on background passes WCAG AA in both themes. Check accent buttons again once the final hex values are set in the asset catalog.

### Motion, sound and haptics

- Step change: 0.25 s crossfade.
- Ring segment fills: 0.3 s ease out, with a soft tick sound when a segment turns green and a short chime at 100 percent. Sound is on by default with a toolbar toggle, because a quiet room makes it a nice moment.
- Buttons: scale to 0.96 on press.
- REC dot blinks once a second.
- Viewer: one slow turn on first open.
- Haptics: on a Force Touch trackpad, a light `levelChange` tap when a drag passes the reset angle in the viewer. If an iPhone becomes the probe later, play a light tap on each green segment and a success pattern at 100 percent on the phone, since the kid is holding it.
- Reduce Motion: no crossfades, no auto turn, no blink, no press scale. Ring segments change at once. Sounds stay.

### Keyboard, trackpad and touch

| Action | Keyboard | Trackpad and mouse | Touch (iPad later) |
| --- | --- | --- | --- |
| Start or finish scan | Space | Click the button | Tap |
| Use a sample | Cmd Shift S | Click | Tap |
| Open a scan file | Cmd O | Click, or drop a file on the window | Files picker |
| Send a change | Return. Shift Return adds a line | Click | Tap |
| Focus the change field | Cmd L | Click | Tap |
| Undo, redo | Cmd Z, Cmd Shift Z | Edit menu | Buttons |
| Save STL | Cmd S | Click | Share sheet |
| New scan | Cmd N | Click | Tap |
| Turn model | Left and right arrows | Drag | One finger drag |
| Tilt model | Up and down arrows | Drag | One finger drag |
| Zoom | Cmd plus, Cmd minus | Pinch or scroll | Pinch |
| Reset view | Cmd 0 | Double click | Double tap |
| Full screen | Cmd Ctrl F | Green window button | n/a |

- All of these also live in the menu bar, so they can be found.
- Full keyboard access works. Tab order follows reading order. Idea chips are buttons.
- VoiceOver: the ring reads "Scanned 48 percent. 5 of 12 sides done." Chips read their word. The viewer reads its size and "Sample cup" when true. Warnings are announced when they change, at most once every 3 s.

### Research notes

- Apple's Object Capture guidance asks for even, diffuse light, a plain non-shiny background, the object kept still, lots of overlap, and several orbits at different heights. Shiny, see-through, very dark or plain single-colour objects scan badly. The coach card and a "Good objects to scan" help page should say this in kid words: "Pick something with a bit of pattern. Shiny or see-through things are hard."
- Object Capture and Polycam style apps guide with a ring or dome that fills in as you go around, plus short live warnings. This app follows the ring pattern. A second ring for a higher orbit should come when real pose arrives.
- HIG for Mac: unified toolbar, a split view with an inspector for the edit screen, standard menu bar commands for every shortcut, and traffic lights left alone. A sidebar is not used because the flow is linear.

## Five open UX risks

1. The scan does nothing yet. Every video gives the same sample cup. The badge says so, but a demo that scans a toy car and shows a cup will disappoint. Until reconstruction exists, demos should load a prepared STL or PLY through "Open a scan file", or be framed as a sample.
2. The guidance ring is untested with a live camera. With the stub it fills on a timer. With the real engine its thresholds were tuned on synthetic frames only. A ring that fills wrongly in front of a class undercuts trust fast. Calibrate on 5 to 10 real classroom scans before any sales demo.
3. Claude edits are slow and can fail. 5 to 40 seconds feels long for a 9 year old. The canned chips are the safe demo path. Free text needs the key and the internet, and a bad prompt can still break the shape. Pre-test a list of good prompts per sample object.
4. The edit sandbox is not a real sandbox (`bench/edit.py` says so). Kids type anything. Before free text is open to kids, run edits in an isolated process with no network, and add a simple word filter for what reaches Claude.
5. Camera permission on school Macs. Managed Macs often block the camera or need an admin to approve it, and the prompt only shows once. The first class could stall on a grey box. Ship a one-page setup checklist for the instructor and keep "Use a sample" and "Open a scan file" one tap away on every camera error.
