# IR turntable scanner: feasibility for CADDIY

Date: 2026-11-01. Three parallel research passes covered hardware, software and kid fit. This file merges them.

Source caveat: electronoobs.com returned HTTP 429 on every fetch. The build facts come from the same author's sketch on Wokwi (https://wokwi.com/projects/360881044577297409), whose header links to the tutorial, and from the Sharp datasheet via Pololu (https://www.pololu.com/product/2450). The hardware person should confirm the parts list against the real page.

## Verdict

Yes, with limits. It can feed CADDIY a printable STL of small, rounded, matte objects. It cannot be a handheld scanner, and it will not capture detail finer than about 5 mm. Treat it as a "build your own scanner" STEM project. It should not be the main way kids get their model.

## What the build actually is

- Sensor: Sharp GP2Y0A51SK0F IR triangulation sensor. Range 2 to 15 cm, about 60 Hz, analog output, strongly nonlinear. It is an IR LED, not a laser.
- Fixed turntable plus a vertical lead screw rail. Sensor sits 8 cm from the turntable centre.
- 200 readings per turn (full step, 1.8 degrees). Each reading averages 40 ADC samples.
- Up to 12 cm tall. As written, layers are 5 mm apart, so 24 layers and about 4,800 points.
- Output goes to the SD card only, as `scan_001.txt` with `x,y,z` lines. x and y are in cm. z is a layer counter. Serial runs at 9600 baud but every print is commented out.
- No homing. A limit switch pin is set up but never read.

Firmware bugs to fix before trusting any scan:
- `360/200` is integer division, so the code logs 1 degree per step while the motor turns 1.8. Every layer comes out skewed. Use `360.0/200`.
- `lead_screw_rotations_per_cm` is an `int` holding 1.25, so it becomes 1. The comments also mix mm and cm. Real layer height must be measured on the built machine.
- The file name is fixed, so each scan overwrites the last.

## Handheld conflict

This is a fixed turntable rig. It gets its geometry from known motor angles and heights. A single-point IR sensor held in the hand gives one distance with no position, so it cannot make a mesh without separate pose tracking. That is a different project. The app's `LiDARScanSource` stub in `Sources/CADScan/OtherSources.swift` describes a "handheld probe, or an iPhone", and the guided scan UI is camera based. A turntable needs its own simpler screen: port, progress, done.

## Quality to expect

- About 1 to 3 mm radial error on matte light objects, worse on darker ones. Layers 5 mm apart unless the firmware is changed.
- Edges smear because the IR spot is a few mm wide.
- Objects up to about 12 cm across (the surface must stay at least 2 cm from the sensor) and 12 cm tall. They must sit centred.
- About 8 to 10 minutes per scan at stock settings. Finer layers push it toward an hour.
- Top and bottom are never seen. Software fills them flat.
- No holes, undercuts, mug interiors or handle insides.

Works: clay models, matte plastic toys, a rubber duck, a chess pawn, fruit, a foam ball, a simple vase.
Fails: glass, chrome, black LEGO, phones, anything see-through, spiky or flat, anything taller than 12 cm. Sunlight and halogen lamps add noise, so scan indoors under a shroud.

## Software path (fits the existing pipeline)

Today the Mac app accepts stl, ply, obj and video files (`ScanFiles` in `Sources/CADApp/AppModel.swift`) and uploads them to `/api/scan`. The webapp runs `bench/clean.py`, which uses trimesh and manifold3d and already meshes faceless point clouds by voxelising. No open3d or pymeshlab, so skip Poisson and ball pivoting.

The points arrive as rings, so the best mesh is a radial grid r(angle, height). Join neighbouring rings as quads, wrap the seam and fan-cap both ends. That is watertight with no new library.

Step 1, SD file import, about 1 day. Gives a working demo.
- New `bench/turntable.py`: parse the txt, scale x and y to mm, apply calibration (centre offset, real z step, median filter along the angle), build the grid mesh, assert self-check on a synthetic cylinder.
- `bench/clean.py` `load()`: route `.txt` and `.csv` to it.
- `webapp/processing.py`: add `.txt` and `.csv` to `MESH_EXT`.
- `Sources/CADApp/AppModel.swift`: add `txt` and `csv` to `ScanFiles`.

Step 2, live USB serial, about 2 to 3 days including bench time.
- Firmware prints raw `layer,step,adc` plus `LAYER` and `DONE` markers, so calibration lives on the Mac.
- New `Sources/CADScan/SerialPort.swift` using POSIX termios (about 80 lines). Skip ORSSerialPort, it would be the first third-party dependency. The app is not sandboxed today, so no entitlement is needed. If it is ever sandboxed, add `com.apple.security.device.serial`.
- New `Sources/CADScan/TurntableScanView.swift`: port picker, layer progress, point count, writes the txt on `DONE`.
- `Integration.swift` scan step: choose camera or turntable.

Step 3, calibration settings, about 1 day. Centre distance, z step and sensor curve coefficients, fitted from 3 to 5 known distances.

Total about 4 to 5 days of software. Step 1 alone is enough to test real scans.

## Safety

Two steppers and a lead screw make pinch points. Add a cover, a stop switch and low motor current. Use a certified closed 12 V adapter with no exposed terminals. Stepper drivers get hot. Screws and nuts are small parts, so an enclosure helps. IR LED eye risk is negligible.

## Recommended path

1. Main path for kids: phone or Mac camera plus a cheap manual turntable, processed by Apple Object Capture (`PhotogrammetrySession`, native on Apple silicon Macs). Around 1 mm detail in minutes for no extra hardware cost. It fits the existing camera scan source and guided overlay. Same weakness on shiny and see-through objects.
2. Keep the IR turntable as an optional build-it-yourself project. Do Step 1 above once the hardware exists. Add serial only if the hardware person commits to the firmware changes.
3. Skip VL53L1X ToF sensors. Their wide field of view makes them worse than the Sharp sensor for small objects.
4. Phone LiDAR alone is about 1 cm, too coarse for small objects. Commercial handheld scanners (Creality Ferret, Revopoint, about $300 to $700) are a later premium option only if Object Capture falls short.

## Top risks

- The handheld plan and this hardware do not match. Decide which product it is first.
- Firmware bugs silently distort the geometry. Scans look wrong and nobody knows why.
- Kids bring shiny, dark or hollow objects and get blobs.
- 8 minutes or more per scan with no live feedback loses attention.
- Moving parts and a power supply in a kids' product need a proper enclosure.

## Questions for the hardware person

1. Is the goal still handheld? If yes, this tutorial is the wrong base. If no, can we call it a turntable scanner and design the app screen for that?
2. Can you change the firmware to fix the angle and lead screw bugs, home on the limit switch, and stream raw `layer,step,adc` lines over USB serial with `LAYER` and `DONE` markers?
3. Once built, can you scan a known cylinder (for example a 60 mm can) and a matte toy and send us the raw files plus the measured centre distance and real layer height? That gives us calibration data and a real accuracy number.

## Addendum: checked against the real page text (pasted by the user)

The agents could not load the page, so this section replaces any conflicting detail above.

Confirmed from the page and its code:
- Fixed turntable plus Z lead screw, Sharp GP2Y0A51SK0F, two A4988 drivers, SD card output. Not handheld.
- Output is `x,y,z` per line in `scan_001.txt`. The file name is fixed. Serial printing is commented out.
- Homing exists in the limit switch version. The earlier "no homing" claim was wrong.
- Default layer height is 0.5 mm, not 5 mm. 40 ADC samples are averaged per point. 200 points per revolution.
- The author says the precision "is not that good" and suggests it is for learning.

Bugs found in the code as written (read, not run):
1. `RADIANS = (PI/180) * (360/steps)`: `360/200` is integer division and gives 1, so each step is logged as 1 degree. The motor turns 360 degrees and the points cover only 200. Every scan is squashed. It should be 1.8.
2. Units: `z` grows in mm but the stop test compares it with `z_axis_height` in "cm". The default stops at 12 mm, not 12 cm. x and y are in cm. The cloud mixes units, so z needs a x0.1 scale on import, and the height setting must be fixed.
3. `lead_screw_rotations_per_cm` is an `int`. The default is 8. A common T8 screw (8 mm lead) needs 1.25 and would truncate to 1, so Z moves wrong distances.
4. `analogReference(INTERNAL)` is called, but the schematic wires AREF to 3.3 V. On a Nano that fights the internal reference. It should be `EXTERNAL`. Check before powering.
5. The distance polynomial is from the GP2Y0A41SK0F datasheet (4 to 30 cm), but the part is the A51 (2 to 15 cm). The curve does not match, so radii are off until it is recalibrated with known objects.
6. The sensor sits 8 cm from the centre and reads down to 2 cm, so objects must fit inside about 6 cm radius, not the claimed 13 cm.

Timing: at the defaults (12 units of z at 0.5 = 24 layers) a scan takes roughly 8 to 10 minutes. If the height bug is fixed to a true 12 cm it becomes about 80 minutes.
