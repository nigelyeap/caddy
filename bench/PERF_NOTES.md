# Clean step: speed and real-scan robustness

Measured 2026-10-30 on an Apple M4 with 16 GB of RAM and 10 cores. Other agents were running at the same time, with a load average of 3 to 6, so timings vary by about 30%. The old and new code were run back to back under the same load.

Rerun with:

```
uv run python perf.py                 # 100k, 500k, 1M, 2M faces
uv run python perf.py --clean OLD.py  # any other clean.py, for comparison
uv run python synth_hard.py           # failure-mode cases only
uv run python run_bench.py            # 6 base cases + hard cases + edits
```

## Speed and memory

The input is a noisy toy with holes and floaters, cached in `out/perf/`. Clean time does not include loading the file. Peak memory is the peak RSS of the child process.

| faces in | before: quiet machine | before: same load as after | after | peak MB before | peak MB after | faces out after |
|---|---|---|---|---|---|---|
| 88k | 0.66 s | 1.0 s | 0.8 s | 324 | 314 | 28,960 |
| 464k | 6.0 s | 11.8 s | 4.0 s | 1,140 | 1,248 | 41,866 |
| 946k | 23.8 s | 32.6 s | 11.9 s | 2,092 | 2,279 | 29,526 |
| 1.9M | 234 s, NOT watertight | not rerun | 25.5 s | 1,970 | 3,101 | 33,210 |

The 1M target was under 15 s. The new code takes 11.9 s while other agents are loading the machine. The old code took 32.6 s under the same load.

### What was slow

On 1M faces, the old code spent 17 of its 22 s in `MeshFix.repair()`. MeshFix clean grows faster than the face count.

### The fix

`_meshfix(mesh, cap)` handles any part over 200k faces in three steps:

1. MeshFix fills its holes. This is fast, about 0.1 s.
2. manifold3d simplifies the part down to 200k faces, in about 1 to 2 s.
3. The full MeshFix clean runs on the smaller mesh.

If the filled mesh is not manifold, the code falls back to the full slow clean.

I tried grid vertex clustering first and dropped it. It created about 37k non-manifold edges on the 500k mesh, and MeshFix then threw away almost everything.

### Where the 1M time goes now

- Building the MeshFix object takes 2.3 s per call. That is pymeshfix's `load_arrays` and cannot be avoided.
- Smoothing and the noise estimate take 0.8 s. The remaining part of that stage is part extraction, hole measurement and the extents checks.
- manifold3d simplify takes 1 to 2 s.
- The MeshFix clean on 200k faces takes about 2 s.

### Memory

Peak memory at 2M faces went up from 2.0 to 3.1 GB. The full-size filled mesh and its manifold copy are both held at the same time. If phones or small servers matter, cut `PRE_CAP` or free the MeshFix object sooner.

### Other fixes found along the way

- Simplify sometimes left a 4-face zero-volume sliver pinched onto the surface. This made the old 1M output non-watertight. `_drop_slivers` now removes it.
- Each part's smoothing passes now scale with the measured noise, from 10 passes up to 25. This fixed `toy_heavy`, which failed the 2% check before: it went from 2.47% to 1.54%.

## Progress for the web app

`clean()` and `clean_scan()` take `progress(frac, step)`, where frac runs from 0 to 1 and step is a short plain phrase. On the command line:

```
python clean.py in.ply out.stl --progress            # one JSON line per step: {"progress": 0.25, "step": "smoothing and repairing"}
python clean.py in.ply out.stl --report report.json  # quality, warnings, log, parts, rotated, scale_guessed
```

`python clean.py src dst` behaves as before. The `clean(mesh, longest_mm, ...)` call still returns `(mesh, log)`. Warnings and the quality score are added to the end of the log as `warning: ...` and `quality: N` lines.

`clean_scan()` returns a dict with these fields:

- `mesh`
- `quality`, from 0 to 100
- `warnings`, as plain English sentences
- `log`
- `parts`
- `rotated`
- `scale_guessed`

## Failure modes

Each case has a generator in `synth_hard.py` and a check in `judge()`. A case passes when:

- the result is printable
- the part count is right
- the dimensions are within 2%, or 5% when no size is given
- for upright cases, height and footprint match after squaring both meshes up the same way
- for the handle case, the genus matches

The cases also appear in REPORT.md under the clean step. Edits do not run on them.

| case | what it simulates | result | dim err | vol err | quality |
|---|---|---|---|---|---|
| hard_big_holes | three holes 24 mm wide, one on top of the head | PASS | 1.10% | 0.73% | 70 |
| hard_bridged_handle | 0.5 mm web filling a mug handle loop | PASS, loop restored | 0.57% | 0.62% | 90 |
| hard_table_toy | toy on a table, no underside, file in metres | PASS | 0.53% | 0.82% | 81 |
| hard_table_block_tilted | block on a table, whole scene tilted | PASS | 1.50% | 4.35% | 65 |
| hard_drift | one side scanned twice, 1.2 mm apart | PASS | 0.20% | 0.50% | 100 |
| hard_drift_fused | whole toy scanned twice, stitched into one surface | PASS | 0.32% | 0.82% | 100 |
| hard_hand | a hand fused to the toy | KNOWN limit | 112% | 29% | 85 |
| hard_points | point cloud only, metres | PASS | 0.79% | 2.87% | 90 |
| hard_points_table | point cloud with a table and no underside | PASS | 1.38% | 4.89% | 90 |
| hard_tilted_block | block at a random tilt | PASS | 0.46% | 2.42% | 95 |
| hard_yup_mug | Y-up export, the mug lies on its side | PASS | 0.65% | 0.48% | 95 |
| hard_two_parts | two objects plus dust | PASS, both kept | 1.18% | 0.82% | 95 |
| hard_units_cm | no size given, file in cm | PASS | 0.28% | 0.71% | 90 |

The 6 base cases all pass. `toy_heavy` failed before this change.

| case | dim err before | dim err after | vol err before | vol err after |
|---|---|---|---|---|
| toy_light | 0.54% | 0.66% | -0.59% | -0.75% |
| toy_heavy | 2.47% (fail) | 1.54% | +0.69% | +0.29% |
| mug_light | 0.62% | 0.61% | -0.64% | -0.63% |
| mug_heavy | 1.20% | 1.06% | -1.69% | -1.64% |
| block_light | 0.61% | 0.58% | -2.25% | -2.12% |
| block_heavy | 1.37% | 0.38% | -7.00% | -5.81% |

### How each mode is handled

- **Table or flat support.** RANSAC finds a plane that is wider than the object's footprint, with almost everything else on one side of it. The plane is cut away and the rim is pulled down onto it. The table normal then decides which way is down.
- **Hand or other attached object.** This is not solved. Geometry alone cannot tell a fused hand from part of the object. The case documents the limit. Real fixes would be colour or segmentation from the capture app, or a user brush.
- **Thin web bridging a handle or ear.** Rays are cast inward from each face. Any area thinner than 0.8 mm is removed with 2 rings of margin, and MeshFix closes the result again. This runs only when the web is bigger than about 60 mm2. A real handle under 0.8 mm would also be removed, but it would not print on a 0.4 mm nozzle anyway.
- **Double surfaces from drift.** A big piece that sits mostly inside the main piece's box is dropped as a second scan layer. If MeshFix cuts off more than 4% of any side of a part, that part is rebuilt from sampled points using a voxel signed-distance surface.
- **Point clouds.** The voxel closing, signed distance and manifold3d `level_set` path needs no new dependency. A 60k-point toy takes about 3 s. Detail is softer, and the user gets a warning.
- **Orientation.** The table normal wins if there is one. Otherwise the code compares the base width with -Z down and with -Y down, then falls back to trimesh stable poses. Yaw is set by area-weighted PCA of the footprint.
- **Scale.** A given longest side always wins. Otherwise the code guesses metres, cm or mm and warns the user to measure.
- **Multi-part objects.** Any piece with at least 15% of the largest piece's area is kept, up to 4 pieces. The user gets a warning that they print separately.
- **Quality score and warnings.** Each finding takes points off a score of 100. Big holes are labelled bottom, top or side, and the hole penalty is capped at 30.

### Volume loss on sharp edges

Smoothing moves are now capped per vertex at 2 times the median move. Sharp edges keep more of their shape and noise still gets smoothed out. The gain is small. Block light went from -2.25% to -2.12% and block heavy from -7.0% to -5.8%.

Most of the remaining loss on block_heavy comes from the missing bottom. MeshFix closes it with a minimal patch, and the bevelled rim of the opening is lost. Feature-preserving denoising, such as bilateral normal filtering, would help further. That is more code and more tuning. I left it out until a real scan shows the need.

### Scan gap or real opening

No geometric heuristic does this reliably, so every hole is filled. A cup's mouth and a scan gap look the same. Both are boundary loops with clean rims. Possible signals and why each fails:

- **Rim planarity.** Real openings are often planar. So are the undersides that a table hides.
- **Hole size relative to the object.** A mug mouth and a missing bottom are about the same size.
- **Whether the scanner could see the area.** This needs camera poses, which the file does not have.

What the code does instead is report each big hole by position, for example "A gap about 24 mm across on the top was missing and was filled in". The user can then cut it open again in the edit step. The edit step already has cut and hole helpers.

## Dependencies worth adding (none installed, all awaiting approval)

| package | version checked | licence | macOS arm64 / py3.14 | what it would add | what it can access |
|---|---|---|---|---|---|
| fast-simplification | 0.2.0 | MIT | cp314 wheel, 148 kB | Quadric decimation, said to be 4 to 5 times faster than VTK. It could replace the manifold3d simplify pre-pass and could also decimate before MeshFix load. | Pure compute, no network or files. Source: github.com/pyvista/fast-simplification |
| open3d | 0.20.0 | MIT | cp310 to cp314 | Poisson and ball-pivoting surfaces from points (oriented normals required), statistical outlier removal, RANSAC planes. | Large wheel. Its visualiser can open windows, which we would not use. No network use in the meshing code. Source: github.com/isl-org/Open3D |
| pymeshlab | 2025.7.post1 | GPL-3 | cp310 to cp314 | Screened Poisson, hole closing, and many other filters. | GPL-3 matters if the app is distributed. Pure compute. Source: github.com/cnr-isti-vclab/PyMeshLab |
| libigl | 2.6.3 | MPL-2 | abi3 wheel built for 3.12, likely loads on 3.14 (untested) | Winding numbers for robust inside tests, and signed distance. | Pure compute. Source: github.com/libigl/libigl-python-bindings |

Rejected:

- **ManifoldPlus.** It has a non-commercial licence and no pip package, so it would need a C++ CMake build.
- **Instant Meshes.** It does quad remeshing for modelling, which does not help printing.

My recommendation is fast-simplification first, because it is small, MIT-licensed and targets the remaining bottleneck. Open3D is the one to try second if the voxel point-cloud path looks too soft on real scans.

## What only real scans can answer

- Real hands and fingers. Are they ever fused to the object, or does the capture app already separate them?
- Shiny and dark surfaces. How big and where are the real gaps, and do they look like the synthetic round holes?
- Fused double surfaces from long drift. The synthetic version is a clean offset, and real drift is uneven.
- Unit guesses for objects under about 30 mm. In cm and mm the numbers overlap, so the guess can be wrong without a measured size.
- Thick webs from 0.8 to 2 mm. They are printable, so they are kept, but they may still be scan errors.
- Real noise levels. The smoothing pass count is tuned on synthetic Gaussian noise, and phone LiDAR noise is lumpier.
- Peak memory on the server that will run this. 2M faces needs about 3 GB.
