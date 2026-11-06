# Handover: A1 academic research poster for CADDY

Written 2026-11-05. For whoever builds the poster, human or Claude session. Read this whole file first. Do not start laying out until the "Ask Nigel first" list is answered.

## The job

Make one A1 portrait poster (594 x 841 mm) about CADDY, a Mac app where a kid aged 8 to 14 scans an object, cleans it up, edits it with words or hand gestures, and saves an STL for Tinkercad or FreeCAD. Mascot: Caddy.

Output: `poster/caddy_poster.pdf` (vector, print ready) plus the source. Put everything in `~/Documents/cad-training/poster/`.

## Tool: LaTeX tikzposter, not an AI image maker

The poster is typeset, not generated. This is the standard academic route and it is already on this Mac.

- `xelatex` is at `/Library/TeX/texbin/xelatex`.
- `tikzposter.cls` is installed (TeX Live 2026).
- `typst` is installed at `/opt/homebrew/bin/typst` if Nigel prefers it. Do not install anything else without asking.

Start the file like this:

```latex
\documentclass[25pt, a1paper, portrait]{tikzposter}
```

Use `xelatex` with `fontspec` so fonts are real and embedded. Build with `xelatex caddy_poster.tex` (run twice). Check the page size afterwards:

```sh
pdfinfo caddy_poster.pdf | rg "Page size"   # expect about 1683 x 2384 pts
pdffonts caddy_poster.pdf                    # every font must say emb yes
```

Figures go in as PDF or SVG converted to PDF, never low-resolution PNGs. If a PNG is the only source, it needs 150 dpi or more at its printed size.

## Hard rules

1. No AI-generated imagery on the poster. Charts come from the repo's own data. Screenshots come from the running app. Caddy art must be the vector SVGs in `mac/mascot/poses/`. Some early mascot candidates were made with an image generator. Ask Nigel which pose files are his hand-built vector art before using any of them. `mac/mascot/poses/make_poses.py` draws the poses in code, which is the safe source.
2. No invented numbers, no vanity metrics. Every figure and number on the poster must trace to a file listed below, with the command that reproduces it.
3. Say what was not tested. See "Limits to state on the poster".
4. Writing style (Nigel's rule, applies to all poster text): no em dashes, no semicolons, no "not X but Y", no filler openers, no words like leverage or passionate. Short plain sentences. Scan the finished text before sending.
5. Do not push, publish, or email the poster. Hand Nigel the PDF.

## Ask Nigel first

Do not guess these. Ask in one batch.

- Title, authors, affiliation, supervisor, logos allowed on the poster.
- Which event or course is this for, and is there a template or colour rule.
- Is it a design poster (what we built) or a results poster (what we measured)? The content below supports both, with the build as the main story.
- Print route: A1 sent to a print shop (needs bleed and CMYK?) or a PDF only.
- QR code target, if any. The GitHub repo is https://github.com/nigelyeap/caddy.git. Confirm it is fine to show publicly.
- Which mascot poses to use.

## Suggested structure (portrait, three bands)

Keep it to about 400 to 600 words total. Large type, few words.

| Band | Block | Source |
|---|---|---|
| Top | Title bar with authors, Caddy hello pose | `mac/mascot/poses/01_hello.svg` |
| Top | Problem and aim: kids can scan and edit real objects, but CAD tools are too hard | `mac/CADDY_KID_PLAN.md`, `mac/DESIGN_FINAL.md` |
| Middle | Pipeline figure: Scan, Clean up, Edit, Save for Tinkercad or FreeCAD | draw as TikZ, boxes and arrows |
| Middle | Method 1, scanning guidance: orbit angle error before and after | `guidance/QUALITY_NOTES.md` |
| Middle | Method 2, clean up: watertight, one part, size within 2 percent | `bench/REPORT.md`, "Clean step" tables |
| Middle | Method 3, edit by words and by hand: typed edits, hand pinch, two-finger swipe, subtle snap | `mac/Sources/CADGesture`, `mac/Sources/CADViewer/Snapping.swift` |
| Bottom | App screenshots, light and dark | `mac/screens/edit_light.png`, `edit_dark.png`, `after_edit_dark.png` |
| Bottom | Limits and next steps | see below, plus `BACKLOG.md` |
| Bottom | QR code, references, acknowledgements | Nigel's answers |

Figure ideas that use real data:

- Bar chart of orbit angle error, before vs after, per scenario, from the table in `guidance/QUALITY_NOTES.md` (for example clean -23 to -0.4 degrees, handheld -430 to 4 degrees at the end of the scan). Re-run `uv run python eval_orbit.py` in `guidance/` to confirm before charting. Build the chart in `pgfplots` so it matches the poster fonts.
- Clean step table: six synthetic objects, all pass, dimension error 0.38 to 1.54 percent. Regenerate with `uv run python run_bench.py` in `bench/`.
- One screenshot with callouts (tool strip, size badge, hand camera bubble).

## Limits to state on the poster

These are true as of today and a reviewer will ask.

- The bench ran without the language model. `bench/REPORT.md` says "LLM EXERCISED: NO". The edit results test the parser, sandbox and checks with canned replies. Do not claim how often Claude writes a working edit script. If Nigel wants that claim, he must run the live bench with his API key first.
- Clean step results are on synthetic objects. One known failure: a hand fused to the object is kept as part of it (`hard_hand`, 112 percent dimension error).
- Scan guidance was tested on synthetic scenes and four public Objectron clips (Google, C-UDA-1.0 licence, cite it).
- Hand control (pinch, two-finger swipe, pinch-to-press tool buttons) and the snap are unit tested but not yet confirmed with a real camera or by kids. Do not report user results. There are none.
- No user study has been run. Do not write "kids loved it" or any satisfaction figure.
- Live camera plus LiDAR reconstruction is not built yet (`BACKLOG.md`, "Waiting on the user").

## Work steps

1. Get answers to the "Ask Nigel first" list.
2. Read `bench/REPORT.md`, `guidance/QUALITY_NOTES.md`, `mac/DESIGN_FINAL.md`, `mac/CADDY_KID_PLAN.md`, `BACKLOG.md`.
3. Re-run the two benches, note date and command next to each number in a `poster/NUMBERS.md` file.
4. Export figures to `poster/fig/` as PDF.
5. Write `poster/caddy_poster.tex`. Use a restrained palette that matches the app. Take colours from `mac/Sources/CADShared/Theme.swift` and the icon at `mac/Resources/caddy_logo_1024.png`.
6. Build, check page size and embedded fonts, render to PNG at low resolution and look at it. Check body text is at least 24 pt at A1 and nothing runs off a column.
7. Run the style scan on all text. Check every number against `poster/NUMBERS.md`.
8. Give Nigel the PDF path and a three-line list of what was left out.

## Known traps

- The project folder is not a git repo. The repo clone lives in the session scratchpad and may be gone. Do not push.
- Screenshots in `mac/screens/` may be out of date. Retake from `/Applications/CADDY.app` (bundle id `com.nigel.caddy`) if the layout changed. The tool strip now has pinch-to-press on Look, Move, Cut, Turn, Lift and Size. Add and Copy are mouse only.
- Use the session scratchpad for temp files, not `~` or `~/Downloads`.
