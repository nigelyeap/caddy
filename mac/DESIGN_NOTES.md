# CADDIY design notes

One page. What the app looks like now, why, and how it got here.

## Who it is for

Students and teachers in a classroom, on a Mac or a projector. The look is a plain, professional Mac tool, close to Xcode's inspector or Preview. It should not look like a toy. Text size is a setting, so the back row can still read it.

## Current rules

- **Type.** SF Pro (the default system design), sentence case, medium weights. Title 20, body and buttons 13, secondary 12, caption 11. Mono 11 for counts and version numbers. Text size multiplies everything by 1, 1.2 or 1.4.
- **Colour.** Neutral grey surfaces with hairline borders (`line`). One accent, the system accent colour, so native and custom controls match. Green, amber and red only for status.
- **Shape.** Radius 8 for cards, 6 for buttons and fields. No shadows on panels.
- **Buttons.** One primary (filled accent) button per screen. Everything else is a secondary button or a compact chip with a hairline. On the Edit screen, Apply is primary until the first change. After that, Save STL is primary.
- **Copy.** Short, plain sentences. No exclamation marks, no em dashes, no semicolons.

## Screens

- **Toolbar.** "CADDIY", a divider, then a breadcrumb: Scan > Process > Edit. Sound and Text size sit on the right and are also in the menus.
- **First run.** A title, a "How it works" card with the three steps, a "For a good scan" checklist, and two buttons: Use the sample model (secondary) and Start scanning (primary). The cards sit side by side and stack when the text is large.
- **Scan.** The camera view from CADScan on the left. A 280 pt side panel on the right shows the three steps with Scan marked "Now", scan tips, and the other ways in: Open a scan file and Use the sample model.
- **Process.** A large placeholder where the model will appear, with a spinner and the current stage. A 320 pt status panel shows the source, elapsed seconds, the stage list, and what happens next. If processing fails, the panel shows the reason, the scan tips, and Back to scan as the primary action.
- **Edit.** The 3D view takes most of the width. The size badge is top left and the view buttons are bottom centre. The inspector on the right holds, from top to bottom:
  - "Describe a change" text field with Apply.
  - "Quick changes": eight labelled chips with an SF Symbol each, in a two-column grid under Size, Add and Cut.
  - "History" with a count, Undo and Redo buttons, and the version list. Undone versions show struck through. An empty-state hint shows before the first change.
  - "Model" card: size, volume, triangle count and a watertight check, plus New scan.
  - A footer that never scrolls away: the status line, "Open in" Tinkercad and FreeCAD, and Save STL.

## How it got here

1. **First version.** Teal accent, SF Pro Rounded, 20 pt body, big filled buttons, step pills and decorative icons. Feedback: cluttered and childish.
2. **Second version.** Neutral, SF Pro, 13 pt, one primary button, quick changes folded into an Examples menu, short history, "Open in" as a menu. Feedback: too empty and too plain, and the quick actions were hidden.
3. **Current version.** The professional rules from version 2 stay. The useful content comes back as tidy, visible pieces: the quick-change grid, the model card, the history with Undo and Redo, a visible Open in row, and side panels on Scan and Process so no screen is a blank centre.

## What we rejected

- **A percentage bar while processing.** The helper cannot report a true percent. A fake bar would mislead.
- **Big filled buttons for every action.** Too loud. Only the primary action is filled.
- **Menus for common actions.** Quick changes and Open in were easy to miss inside menus. They are visible chips now. The menu bar still has them for keyboard users.
- **Third-party fonts or icon packs.** SF Pro and SF Symbols match the system and need no install.
- **Confetti or sounds on every edit.** Fun once, tiring by the tenth edit in a lesson.
