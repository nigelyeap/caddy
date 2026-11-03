# CADDIY Arrange mode: kid-facing design plan

Scope: UX only. Matches EditScreen, Tutorial, CaddiyLines, Builds and Theme. No code was changed.

## 1. The big decision: one stage, a tool strip, a Parts list

Today a drag anywhere on the stage orbits the camera. Moving parts needs the same gesture.
Fixing that clash is the main design job. Plan:

- Add a tool strip down the left edge of the stage. Three tools, big icons with words under them:
  Look (default), Move, Cut. Plus two action buttons below a gap: Add and Copy.
- Look keeps today's behaviour exactly. The tour step "Drag it to turn it around" still works.
- Move: drag on a part slides it. Drag on empty floor still orbits. So a kid is never stuck.
- Cut: drag draws a cut line. Nothing else happens in this tool.
- Clicking a part selects it in every tool. Clicking empty floor clears the selection.
- Two-finger trackpad drag and scroll always orbit and zoom, in every tool.
- The inspector gets a new section at the top, "My parts", above "Describe a change".
  It only shows once there are two or more parts, so the one-model flow looks the same as today.
- No new screen and no new step in the Scan, Clean up, Edit indicator. Arrange lives in Edit.

Why not a separate Arrange screen: kids would have to learn when to switch. One stage keeps the flow.

Selection look (not colour alone): a gold outline (Theme.gold) around the part, a small name tag
floating above it ("Cup"), and the matching row lit in My parts with Theme.accentSoft.
Each part gets a soft tint from the existing Tint set so two parts are easy to tell apart.

"Describe a change" and Quick changes act on the selected part. A chip above the text box says
"Changing: Cup". With nothing selected and several parts, tiles are greyed with the hint
"Pick a part first". Risk: the helper today edits one STL. It must take a part id.

## 2. Mockups

Main state, two parts, Move tool, cup selected:

```
+--------------------------------------------------------+-------------------------------+
| [12 x 8 x 9 cm]                                        | My parts                  (2) |
| +------+   . . . . . . . print bed . . . . . . . .     |  [*] Cup        selected      |
| | Look |   .                                      .    |  [ ] Pencil holder            |
| |>Move<|   .        .-"Cup"-.                     .    |  Put away (0)                 |
| | Cut  |   .       (#########)    [====]          .    | ----------------------------- |
| |------|   .        '#######'     [    ]          .    | Describe a change             |
| | Add  |   .         gold ring    [====]          .    | Changing: Cup                 |
| | Copy |   .                                      .    | [ Try: make it 20% taller  ]  |
| +------+   . . . . . . . . . . . . . . . . . . . .     | Quick changes ...             |
|                      [ view buttons ]       (Caddiy)   |                [ Save STL... ]|
+--------------------------------------------------------+-------------------------------+
```

While dragging a part (Move tool):

```
   pointer: closed hand          part lifts 2 mm and casts a darker shadow on the floor
            .-"Cup"-.            a thin line drops from the part to its floor spot
           (#########)  <--      a distance tag follows it: "4 cm from the edge"
            '   |   '
           ~~~~~~~~~~~ shadow    on release it settles down. No floating.
```

Cut tool, line drawn, waiting to confirm:

```
+------------------------------------------------------+
|              \                                       |
|        .---- \ ----.     left half tinted orange      |
|       ( ####  \ ### )    right half tinted blue       |
|        '----   \---'                                 |
|                 \   <- dashed gold line              |
|   [ Cut here ]  [ Try again ]  [ Turn line 90 ]      |
+------------------------------------------------------+
  Caddiy: "Snip! Check the colours, then tap Cut here."
```

Smart split prompt, right after Clean up finishes:

```
+--------------------------------------------+
|  (Caddiy, idea pose)                       |
|  I found 2 things in your scan!            |
|  I made them into 2 parts.                 |
|      [ Keep them apart ]  [ Stick back ]   |
+--------------------------------------------+
```

Add sheet:

```
+----------------------------------------------------------+
| Add a part                                       [Close] |
| [ Ready-made ] [ My builds ] [ Scan a new thing ]        |
|  [cube] [ball] [tube] [peg] [base] [A-Z] [wheel] [star]  |
+----------------------------------------------------------+
```

## 3. Each feature, how it lives and how it is taught

Drag to move
- Lives: Move tool. Drag slides along the floor. Shift drag lifts up or down.
- On release the part drops onto the floor or onto the top of whatever is under it. Parts never float.
- One whole drag is one History row: "Moved Cup". A drag never fills the list with tiny steps.
- First use hint: "Grab a part and slide it. Let go to drop it."
- Pointer: open hand over a part, closed hand while dragging, normal arrow over empty floor.

Add from the library
- Lives: Add button on the tool strip, plus Change menu "Add a Part..." (Shift Command A).
- Ready-made: about 10 simple printable shapes and letter blocks, bundled STLs.
- My builds: any saved build drops in as a new part. Reuses BuildLibrary.items as is.
- Scan a new thing: goes to the Scan screen with a gold banner "Scanning a new part for your build".
  Back returns to the same build. The new scan lands as a new part.
- New parts appear in the nearest free spot on the bed, never on top of another part.
- Caddiy: "Ta da! A new part. Drag it where you want it."
- Risk: today New scan clears the model. Scene-adding needs a separate path in AppModel.

Smart splitting
- Runs after Clean up when the mesh has two or more big separate pieces.
- Automatic, but it shows as History row 2 "Split into 2 parts", so one Undo puts it back.
- Tiny specks (under about 2 percent of the biggest piece) are dropped as scan noise, also undoable.
- Caddiy line as mocked above. Names are "Part 1", "Part 2". Kids can rename with a double click.
- Risk: scans of one object with a thin handle may break into pieces by mistake.
  The "Stick back" button covers that.

Join ("Stick together")
- Select two parts: Shift click on the stage, or tick two rows in My parts.
- A "Stick together" chip appears in My parts and on a right click menu.
- Joined parts move as one and show one outline and one name. "Pull apart" splits them back.
- Under the hood this is a group, not a mesh merge. The real merge happens only on Save STL.
  That keeps Pull apart exact and cheap.
- Caddiy: "Now they move together. Like best friends."
- Hint if they do not touch: "These do not touch. They will print as two pieces."

Cutting
- Lives: Cut tool. Select the part first, or the cut goes through whatever the line crosses.
- The kid drags a line. The cut is a flat slice through that line, straight away from the camera.
- Before anything changes, the two halves get two tints. The kid confirms with the gold Cut here.
  Esc or Try again clears the line. Nothing is cut until Cut here.
- Each half becomes its own part and slides apart 5 mm so the kid sees the cut worked.
- Cut faces are filled in, so both halves print as solids.
- First use hint: "Draw a line across your part. I cut along it, straight away from you."
- Risk: kids will cut at an odd camera tilt and get a slanted slice. The colour preview is the guard.
  Offer "Straight cut" (on by default) that snaps the slice to the nearest upright or flat angle.
- Risk: open or messy scan meshes may not cap cleanly. Show "That cut did not work. Try a bit
  higher." and leave the part untouched.

Duplicate ("Copy")
- Lives: Copy button, Command D, and right click.
- The copy appears beside the original in a free spot, with the name "Cup 2".
- Caddiy: "Two of them! Twice the fun."

## 4. Safety and forgiveness

- Every scene action is a History row with its own small icon: move, add, split, join, cut, copy.
  Undo and Redo work the same as today (Command Z, Shift Command Z).
- Nothing is destroyed. Delete is "Put away". The part goes to a "Put away" tray at the bottom of
  My parts and can be brought back. The tray empties only when the build is closed.
- Print bed: a lit rectangle on the floor grid, 180 by 180 mm by default. A teacher setting changes it.
  Parts past the edge get orange stripes, and Save STL shows a gentle note, never a block.
- Floating is not possible with gravity on. A toggle for older kids, "Let parts float", turns it off.
  When off, a floating part shows a dotted drop line and the note "This will need supports to print."
- Overlap: two parts that overlap but are not joined get a soft amber glow where they meet, and the
  hint "These overlap. Stick them together, or move one?" with two buttons.
- Lost parts: Reset view frames every part. A part dragged way off screen springs back to the bed edge.
- Save STL with several parts saves everything on the bed as one file, which is what slicers expect.

## 5. Tour and Home / My builds

Tour (TutorialScript.steps)
- Keep the main tour short. Add one step after "viewerTools":
  id "toolStrip", target .toolStrip, line "These tools move, cut and add parts. Try them later!",
  pose .pointLeft, advance .next.
- Everything else is taught by first-use hints. One bubble from StageCaddiy the first time each
  tool is picked, stored in AppStorage like seenIntro. Each hint shows once, and the Help menu can
  reset them.
- New CaddiyMoment cases: .arrange, .split, .cut, .join, .offBed, .added. Lines stay short and plain
  so the existing copy test still passes.

Sample lines with poses
- .arrange: "Pick Move, then slide a part." (.pointLeft)
- .added: "Ta da! A new part." (.cheer)
- .split: "I found 2 things! Now they are 2 parts." (.idea)
- .cut: "Snip snip! Two parts now." (.cheer)
- .join: "Now they move together." (.loveIt)
- .offBed: "Oops, that part is off the bed." (.sad, then "Drag it back in. You can do it!" .cheer)

Home and My builds
- A build becomes a scene. Plan: save a "name.caddiy" folder with one STL per part, a small
  scene.json for spots, groups and names, and a merged STL for Save STL and old code paths.
- Old plain-STL builds still open as a one-part scene. Nothing breaks.
- My builds rows show a "3 parts" chip when a build has more than one part.
- Home behaves the same. It saves the whole scene.
- Risk: BuildLibrary keys everything off the .stl file name. It needs a second file type.

## 6. Accessibility

- My parts is the VoiceOver home for the scene. Each row reads "Cup, part 1 of 3, selected, on the bed".
- Row custom actions: Move left, right, forward, back, up, down. Copy. Put away. Cut in half.
  Stick together with the next part.
- Keyboard on the stage: Tab or the bracket keys move between parts. Arrow keys nudge 5 mm.
  Shift arrow nudges 1 mm. Option up and down lifts. Command D copies. Delete puts away.
- Each move posts an announcement: "Cup moved. 2 cm from the bed edge."
- Cut without drawing: in the Cut tool, Return places a level line through the middle of the part.
  Up and down arrows slide it. R turns it 90 degrees. Return again cuts. Esc cancels.
  The menu also offers "Cut in Half Across" and "Cut in Half Down".
- Reduce Motion: no lift, no settle bounce, no slide apart after cut, no Caddiy hop. Parts snap.
- Reduce Transparency: the cut preview tints go solid.
- Text size: strip labels follow textScale. At Extra large the strip goes icons only, with help tags.
- Selection uses an outline plus a name tag plus the list row, never colour alone.

## 7. Honest risks

- Biggest build cost: the helper and the history model are single-mesh today. A scene needs a part
  list in state, per-part edits from Claude and per-part undo. This is the real work, not the UI.
- Hit testing a part under the pointer in the 3D view is new. Without it, Move and Cut cannot work.
- Cutting arbitrary scan meshes and filling the cut face is the riskiest maths here.
  Start with straight cuts only and a clear failure line.
- Smart split on noisy scans may make junk parts. The speck filter and Stick back are the guard.
- Gravity stacking needs a downward ray onto other parts. Ship floor-only drop first if it slips.
- Kids may grab a part when they meant to spin. Look as default tool and orbit on empty floor
  should cover it. Test this with real 8 year olds before anything else.
- Save STL merges parts. Overlapping parts that are not joined still print fused. The overlap hint
  says so.

## 8. More ideas for the scene

Scores are 1 to 5. Appeal is how much an 8 to 14 year old would care. Difficulty is build cost.

| # | Idea | Pitch | Appeal | Difficulty |
|---|------|-------|--------|------------|
| 1 | Turn | A round handle on the selected part spins it on the floor. R turns 15 degrees. | 4 | 2 |
| 2 | Part colours | Paint each part a colour from 8 crayons. Just for looks, or for multi-colour printers. | 5 | 1 |
| 3 | Mirror copy | Copy a part flipped, for left and right ears, wings or shoes. | 4 | 2 |
| 4 | Snap on top | Drop a part on another and it clicks into the centre of its top face. | 4 | 3 |
| 5 | Will it stand? | A button that tips the build if it would fall over, then shows where to add a base. | 5 | 3 |
| 6 | Name stamp | Type a name and a raised letter plate appears as a new part. | 5 | 3 |
| 7 | Ring of copies | Make 6 copies in a circle, for a flower, a crown or a gear. | 4 | 2 |
| 8 | Peg and hole | Pick two parts and Caddiy adds a peg on one and a matching hole on the other. | 3 | 4 |
| 9 | Ruler | Drag between two spots and see the distance in cm and in Lego studs. | 3 | 2 |
| 10 | Spin show | Record a short turning video or GIF of the build to show friends. | 4 | 2 |
| 11 | Build challenges | Caddiy cards like "Make a phone stand from 3 parts", with a sticker when done. | 5 | 3 |
| 12 | Print time | A little clock that says about how long it will print, and how much plastic. | 3 | 3 |

Recommended top 4
1. Turn. Moving without turning feels broken. It belongs in the first release next to Move.
2. Part colours. Cheapest delight on the list and it makes selection clearer for free.
3. Will it stand? Teaches real design thinking and stops failed prints. Kids love the tip-over.
4. Name stamp. Every kid wants their name on the thing. Reuses the Add flow and the existing
   Words tiles idea.

Skipped on purpose: free scaling handles. "Describe a change" and the Size tiles already do this,
and a third way to resize would muddle the first release.
