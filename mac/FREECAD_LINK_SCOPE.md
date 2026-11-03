# FreeCAD live link: scope

Goal: edits made in CADDY show up in FreeCAD without the kid exporting and importing by hand.

## Sources
- [Headless FreeCAD](https://wiki.freecad.org/Headless_FreeCAD): `FreeCADCmd script.py` runs a script with FreeCAD set up.
- [Part ShapeFromMesh](https://wiki.freecad.org/Part_ShapeFromMesh/en): mesh to shape needs a recalculated mesh and the sewing step can be slow.
- [Mesh to Part](https://wiki.freecad.org/Mesh_to_Part/cs): turning a mesh into a solid is not an easy operation.

## Options

### A. Open the file (built today)
CADDY saves the STL and opens it in FreeCAD. One way, no link back. Each edit means opening again.

### B. Watcher macro (recommended next, about 1 day)
CADDY writes the current model to a fixed file, for example `~/Documents/CADDY/current.stl`. A small FreeCAD macro (about 40 lines, installed once) watches that file and reloads the mesh object in the open document when it changes. One way, CADDY to FreeCAD. The kid keeps FreeCAD open and sees each edit appear.
- Risk: the macro runs inside the GUI, so it must update on the main thread. Test on one real FreeCAD install. None is installed on this Mac yet.
- Needs from the user: install FreeCAD (free, official site), one click to run the macro.

### C. Solid conversion (optional, 1 to 2 days)
Run `FreeCADCmd` with a script that turns the mesh into a Part solid, so FreeCAD can edit faces and holes. Scan meshes with tens of thousands of triangles may sew slowly or fail, so decimate first and fall back to the plain mesh on failure. Real scans need testing. Do not promise this works on scans until tried.

### D. Two-way sync (not recommended)
Edits made in FreeCAD flowing back into CADDY. Needs change detection and conflict handling. Skip until a teacher asks for it.

## Plan
1. Install FreeCAD (user, official download). I will not install it.
2. Build option B in `mac/freecad/caddy_watch.FCMacro` plus a "Send to FreeCAD" toggle in the viewer.
3. Try on the bench STLs, then on real scans once they exist.
4. Try option C on the same files and keep it only if it works on scans.

## Open questions
- Which FreeCAD version does the enrichment company use? (Check before building.)
- Is Tinkercad the main tool for the kids? If so, B matters less and the Tinkercad copy button is enough.
