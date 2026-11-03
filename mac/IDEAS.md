# CADDY ideas and critique

Written 2026-10-30 from the repo docs (README, DESIGN_NOTES, FREECAD_LINK_SCOPE, BACKLOG, webapp/API.md, webapp/UX_NOTES.md, bench and guidance notes) and the NH5001 pivot handover. Nothing here was built or run. Items marked **(unverified)** rest on web reports or my own reading and need a check.

## Top 5 next steps

1. **Run the live Claude bench, then Haiku.** Every edit number so far is canned (`LLM EXERCISED: NO`). Free-text edits are the headline feature, and nobody knows how often Claude gets them right. Two commands from `bench/EDIT_NOTES.md`, about $2 in total. If Haiku matches Opus on the 27 cases, edits get cheaper and faster, which matters for 5 to 40 s waits with a 9-year-old.
2. **Try Apple Object Capture for video to mesh.** RealityKit's `PhotogrammetrySession` runs on macOS 12+ and is fastest on Apple silicon. It takes a folder of HEIC, JPG or PNG images and writes OBJ or USDZ ([Apple docs](https://developer.apple.com/documentation/realitykit/creating-3d-objects-from-photographs)). OBJ already goes through `bench/clean.py`. This could close the biggest gap ("every scan gives the cup") with no new dependency. The user said reconstruction details are coming, so pitch it to them first and do not build ahead of that. **(unverified: quality on webcam or 1 fps frames, and scale without depth)**
3. **Build a demo kit before the NH5001 judging.** Three real objects, scanned (with Polycam or Object Capture if CADDY cannot yet), cleaned, edited and printed. Put the scan files in the app as "Open a scan file" samples. Bring the physical object, the print and a rehearsed prompt list. Record a backup video of the full loop. The UX notes already say a toy car turning into a cup will sink the demo.
4. **Add a print-readiness card with a printer setting.** Replace the fixed 250 mm bed with a printer picker. Add a thin-wall warning, an overhang warning and a filament estimate in grams. Most of the parts exist already: the ray-cast thickness code in `clean.py`, the bed check in `edit.py`, and volume in the Model card. This is what the teacher profile's "identify the cause of a failed print" pain asks for.
5. **Run one pilot class with an enrichment company and log it.** Claire's main criticism was thin customer evidence. A local session log (time from scan to saved STL, edits tried, edits refused, prints done) turns one class into numbers for the deck. It also shows what kids actually type, which feeds the edit helpers. Needs a parental consent sheet, per the handover.

## Ranked ideas

Effort is in working days for one person. Impact is 1 to 5 for the enrichment use case and the demo.

| # | idea | who benefits | effort | impact | risk or dependency |
|---|---|---|---|---|---|
| 1 | Live Claude bench run on Opus, then Haiku and Sonnet. Record pass rate per instruction. | everyone, demo | S (0.5) | 5 | Needs the user to run it with the key. Expect failures on vague and mixed cases. |
| 2 | Object Capture prototype: save guided-scan frames as JPEGs, run `PhotogrammetrySession`, feed OBJ to `clean.py`. | kids, demo | M (2 to 4) | 5 | Waits on the user's camera details. Webcam frames at 1 fps may be too few. Object Capture wants texture and dislikes shiny or clear objects. **(unverified on our frames)** |
| 3 | Demo kit: 3 prepared real scans, printed results, prompt list tested per object, backup video. | demo | S (1 to 2) | 5 | Needs a printer and a real scan source. |
| 4 | Pilot session log: local JSON per session with timings, prompts, refusals, saves. Export as CSV for the teacher. | buyer, course evidence | S (1) | 5 | Privacy: store on the Mac only, no names. Tell parents what is logged. |
| 5 | Printer picker in Settings sets bed size and nozzle. Presets for common school printers, plus custom. Draw the bed outline to scale in the viewer. | teacher | S (1) | 4 | Preset sizes must be checked on spec sheets (for example Bambu A1 mini and Prusa MINI around 180 mm, Ender-3 around 220 mm). **(unverified)** |
| 6 | Thin-wall warning. Reuse the inward ray cast from `clean.py`, flag areas under 1.2 mm (3 nozzle widths), tint them in the viewer. | kids, teacher | M (2) | 4 | Ray cast can be slow on big meshes. Run on the cleaned mesh only. |
| 7 | Overhang warning: share of downward faces steeper than 45 degrees, with "add supports in your slicer" text. | teacher | S (1) | 3 | A rough number. Scanned organic shapes will often trip it, so word it as advice. |
| 8 | Filament estimate in grams (volume times PLA density times an infill guess). | teacher, parents | S (0.5) | 3 | Only a guess without a slicer. Label it "about". Print time is harder, skip it. |
| 9 | "Lay it flat" chip: pick the most stable face down. `clean.py` already uses trimesh stable poses. | kids | S (0.5) | 3 | None worth noting. |
| 10 | "Open in slicer" button. Detect Bambu Studio, OrcaSlicer, PrusaSlicer or Cura and open the STL with `NSWorkspace`, same pattern as FreeCAD. | teacher | S (1) | 4 | Each app must register for STL. Test `open -a` per app. **(unverified)** |
| 11 | Show the edit as plain steps. Turn the helper call into a line like "Added a 6 mm hole through the middle". A "Show the code" toggle for older kids. | kids (learning) | S (1) | 4 | Needs the script returned through the API. Small change in `webapp/`. |
| 12 | Export the edit history as an OpenSCAD file: `import("scan.stl")` plus the same holes, pegs and cuts as primitives. Kids see code-CAD for their own object. | older kids, teacher | M (2 to 3) | 4 | Every helper needs an OpenSCAD twin. `add_loop` and `place_on_top` need care. |
| 13 | Challenge cards: short missions ("make it fit in a 30 mm cube", "add a loop for a keyring") checked automatically with the bench `judge` logic. | kids, teacher | M (2 to 3) | 4 | Content work. Needs a teacher to write the first 10 cards. |
| 14 | Measure tool: click two points in the viewer, show mm. Pair with a ruler step before cleaning ("How long is it?"). | kids (learning) | M (2) | 4 | The ruler input already exists in `clean.py` as `longest_mm`. Unit guesses under 30 mm are unreliable, so ask every time. |
| 15 | Size reference next to the model: a coin or a Lego brick drawn to scale. | kids | S (0.5) | 3 | None worth noting. |
| 16 | Initials or name emboss helper. "Write my name on it" is CANNOT today. Kids will likely ask for this first. | kids | M (2 to 3) | 4 | Needs font outlines. Options: trimesh path text or a small font file plus extrusion. New dependency, ask first. **(guess about demand, check in pilot)** |
| 17 | More helpers kids will ask for: mirror, make N copies in a row, magnet hole, phone or pencil slot, hollow with 2 mm walls. | kids | M (2 to 4) | 4 | Hollowing could use the `level_set` path that `clean.py` already has. Add only what the pilot log shows. |
| 18 | Edit progress and cancel. Show "Claude is writing a plan", "Checking it prints", with a Cancel button. | kids | S (1) | 3 | `POST /api/edit` blocks today. Cancel needs a server change. |
| 19 | Word filter and teacher view of all typed requests, with refused ones flagged. | teacher, buyer | S (1) | 4 | Overlaps with idea 4. Parents and centres will ask what kids can type. |
| 20 | Coverage fill-in mode: after a lap, weak sectors turn amber and an arrow says "go back to the left side". | kids | M (2) | 4 | Ring thresholds are tuned on synthetic frames only. Needs real footage first. |
| 21 | Turntable mode. A webcam on a Mac does not walk around the object. The kid turns the object on a lazy Susan instead. | kids, teacher | M (3) | 4 | The guidance engine assumes the camera moves. A static background will read as no motion. Needs an object mask or the scan mat below. |
| 22 | Printed scan mat: an A4 sheet with ArUco markers under the object. Gives true scale, a fixed centre and which way is up, from the camera alone. | kids, teacher | M (2 to 3) | 4 | OpenCV has ArUco in recent builds. Check the installed `opencv` package has it. **(unverified)** |
| 23 | Object check before scanning: one frame, warn about shiny, dark, see-through or tiny objects, using the existing light and glare checks. | kids | S (1) | 3 | Thresholds unproven on real cameras. |
| 24 | Class kit export: per kid, a one-page HTML or PDF with before and after pictures, the steps they took and the final size. | buyer, parents | M (2) | 4 | Feeds the enrichment pitch: parents see work and re-enrol. Needs per-student project folders (idea 25). |
| 25 | Per-student projects. Today the server keeps one model. A simple folder per student name or number. | teacher | M (2 to 3) | 3 | Touches `webapp/` state and the one-model rule in API.md. Keep it local files. |
| 26 | Before and after ghost in the viewer (old version as a faint outline). | kids | S (1) | 3 | Two meshes in SceneKit, small cost. |
| 27 | History thumbnails instead of text rows. | kids | S (1) | 2 | Render a small snapshot per version. |
| 28 | Tinkercad size guard. Reports say Tinkercad rejects STL files over 25 MB ([Boise State guide](https://www.boisestate.edu/library-makerlab/?p=903)). Decimate before export if the file is bigger. | kids | S (0.5) | 2 | **(unverified, no official Autodesk source found)**. Clean output is 30k to 50k faces, about 2 MB, so this rarely bites. |
| 29 | Tinkercad lesson card: after import, group with a hole shape, resize with handles. Short and pictorial. | kids, teacher | S (1) | 3 | `TinkercadHelp` sheet exists. Extend it. |
| 30 | FreeCAD watcher macro (option B in FREECAD_LINK_SCOPE). | older kids | S (1) | 2 | Only worth it if the customer uses FreeCAD. Ask first. Kids aged 8 to 14 are more likely on Tinkercad. |
| 31 | Run edits on a cloud server so class Macs never hold the API key. | buyer | L (5+) | 3 | Cost, accounts and data handling for minors. Only after a paying pilot. |

## Risks

- **The headline loop is unproven end to end.** Scan to mesh does not exist, edits are canned, guidance is tuned on synthetic frames. A judge who asks "is this real" needs an honest answer. Say which parts run on real data and which run on samples.
- **Mac-only.** Many enrichment centres may run Windows laptops or Chromebooks. **(unverified, ask the customer)**. The web app in `webapp/` is the hedge. Keep it working.
- **API key on a classroom Mac.** The sandbox is strong for a same-user process, and `sandbox-exec` is deprecated by Apple. Cost per edit is small but someone has to pay and hold the key. Decide who before the pilot.
- **Internet in class.** Free-text edits need it. The eight chips work offline. Make sure the demo can fall back to chips.
- **Camera permission on managed Macs.** Ship the one-page setup checklist from UX_NOTES.
- **Hands fused to the object.** A known limit. Teach "put it on the mat, hands off" in the guidance copy.

## Do not build yet

- Two-way FreeCAD sync and mesh-to-solid conversion (options C and D). Nobody has asked, and scans may not sew.
- Colour. Parked in BACKLOG.
- A custom probe enclosure or LiDAR hardware before one pilot class works with a phone or webcam.
- Accounts, logins or cloud sync. One user, local files, until a buyer asks.
- A built-in slicer or print-time estimate. Hand off to the slicer the school already uses.
- An automatic model router for edits. Pick one model from the bench run.
- A percentage progress bar during processing. Already rejected in DESIGN_NOTES for good reason.
- Fusion 360, Onshape or Blender links. Too heavy for this age group. Revisit for older students.
