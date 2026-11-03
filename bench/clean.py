"""Turn a raw scan mesh or point cloud into a clean, printable STL.

Usage: uv run python clean.py IN.ply OUT.stl [--longest-mm 120] [--max-faces 50000]
                              [--report report.json] [--progress]

--progress prints one JSON line per step to stdout: {"progress": 0.4, "step": "repairing"}.
--report writes the quality score, warnings and log as JSON for the UI.

Steps: load (points get meshed), thin out huge meshes, cut away a scanned table, drop
floaters, smooth only as much as the noise needs, MeshFix each real part, stand it the
right way up, scale to mm, remove webs too thin to print, merge parts, decimate, sit on z=0.
"""
import argparse
import json
import os
import sys

import manifold3d as m3d
import numpy as np
import pymeshfix
import trimesh
from scipy import ndimage, sparse
from scipy.spatial import ConvexHull, cKDTree

PRE_CAP = 200_000    # max faces fed to MeshFix clean. It is superlinear: 1.9M faces took 230 s.
KEEP_PART = 0.05     # keep a separate piece if its area is at least this share of the biggest one (about 22% of its size)
MIN_WALL_MM = 0.8    # sheets thinner than this cannot print on a 0.4 mm nozzle. Treated as scan webs.


# ---------- io and manifold helpers (shared with edit.py and run_bench.py) ----------

def load(path):
    """Load PLY, OBJ, STL or anything trimesh reads.
    A point cloud comes back as a Trimesh with vertices and no faces. clean() meshes it.
    Turntable scanner .txt/.csv files go through turntable.py."""
    if str(path).lower().endswith((".txt", ".csv")):
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import turntable
        return turntable.load(path)
    mesh = trimesh.load(path, force="mesh", process=True)  # process merges STL face soup
    if isinstance(mesh, trimesh.Trimesh) and len(mesh.faces):
        return mesh
    geo = trimesh.load(path, process=False)
    pts = np.asarray(getattr(geo, "vertices", []), float)
    if len(pts) < 100:
        raise ValueError(f"{path}: no triangle mesh or point cloud found")
    return trimesh.Trimesh(pts, np.zeros((0, 3), np.int64), process=False)


def to_manifold(mesh):
    """trimesh -> manifold3d. Returns None if the mesh is not a valid closed manifold."""
    mesh = trimesh.Trimesh(mesh.vertices, mesh.faces, process=True)  # merge duplicate verts
    man = m3d.Manifold(m3d.Mesh(vert_properties=np.asarray(mesh.vertices, np.float32),
                                tri_verts=np.asarray(mesh.faces, np.uint32)))
    if man.status() != m3d.Error.NoError or man.is_empty():
        return None
    return man


def from_manifold(man):
    out = man.to_mesh()
    return trimesh.Trimesh(np.asarray(out.vert_properties)[:, :3], np.asarray(out.tri_verts), process=True)


def guess_scale_to_mm(extent_max):
    """Unit guess when no real size is given. Scanner apps usually export metres."""
    if extent_max < 2.0:  # under 2 units: assume metres
        return 1000.0
    if extent_max < 30.0:  # under 30 units: assume centimetres
        return 10.0
    return 1.0


def check(mesh):
    """Printability facts for a mesh, all in mm."""
    man = to_manifold(mesh)
    return {
        "watertight": bool(mesh.is_watertight),
        "manifold": man is not None,
        "volume_mm3": float(mesh.volume) if mesh.is_watertight else float("nan"),
        "components": len(mesh.split(only_watertight=False)),
        "faces": len(mesh.faces),
        "extents_mm": [round(float(e), 2) for e in mesh.extents],
    }


# ---------- building blocks ----------

def _face_labels(faces, n_verts):
    """Connected part id per face (parts share vertices)."""
    a = np.concatenate([faces[:, 0], faces[:, 1]])
    b = np.concatenate([faces[:, 1], faces[:, 2]])
    g = sparse.coo_matrix((np.ones(len(a), np.int8), (a, b)), shape=(n_verts, n_verts))
    return sparse.csgraph.connected_components(g, directed=False)[1][faces[:, 0]]


def _smooth(mesh, iters):
    """Taubin smoothing, capped per vertex at about the noise level.
    Sharp edges want to move far, noise moves a little. Capping the move keeps edges and volume."""
    v0 = mesh.vertices.copy()
    # Noisier scans get more passes. Noise = median off-surface jitter per vertex, relative to edge length.
    # Bench: light synthetic noise reads about 0.05 to 0.09, heavy about 0.10 to 0.18.
    e = mesh.edges_unique
    a, b = np.r_[e[:, 0], e[:, 1]], np.r_[e[:, 1], e[:, 0]]
    nb = np.column_stack([np.bincount(a, v0[b, k], len(v0)) for k in range(3)])
    deg = np.bincount(a, minlength=len(v0))[:, None]
    off = np.abs(((v0 - nb / np.maximum(deg, 1)) * mesh.vertex_normals).sum(1))
    noise = np.median(off) / np.median(mesh.edges_unique_length)
    iters = int(round(iters * np.clip(noise / 0.08, 1, 2.5)))
    trimesh.smoothing.filter_taubin(mesh, iterations=iters)
    d = mesh.vertices - v0
    mag = np.linalg.norm(d, axis=1)
    cap = 2.0 * np.median(mag)
    mesh.vertices = v0 + d * np.minimum(1.0, cap / np.maximum(mag, 1e-12))[:, None]


def _boundary_loops(mesh):
    """Open edges grouped into holes. Returns a list of (centre, diameter)."""
    e = np.sort(mesh.faces[:, [0, 1, 1, 2, 2, 0]].reshape(-1, 2), axis=1)
    uniq, cnt = np.unique(e, axis=0, return_counts=True)
    b = uniq[cnt == 1]
    if not len(b):
        return []
    lab = _face_labels(np.column_stack([b, b[:, 1]]), len(mesh.vertices))
    out = []
    for i in np.unique(lab):
        p = mesh.vertices[np.unique(b[lab == i])]
        out.append((p.mean(0), float(np.linalg.norm(np.ptp(p, 0)))))
    return out


def _extents(v):
    """Bounding box size ignoring the 0.1% most extreme points (spikes and fins)."""
    return np.ptp(np.percentile(v, [0.1, 99.9], axis=0), axis=0)


def _plane_basis(n):
    u = np.cross(n, [1, 0, 0] if abs(n[0]) < 0.9 else [0, 1, 0])
    u /= np.linalg.norm(u)
    return np.column_stack([u, np.cross(n, u)])


def _support_plane(pts, w, rng):
    """Find a scanned table: a big flat patch, wider than the object, with the object on one side.
    Returns (unit normal pointing at the object, offset, tol) or None."""
    size = float(np.ptp(pts, 0).max())
    tol = 0.012 * size
    sub = pts[rng.choice(len(pts), min(len(pts), 20_000), replace=False)]
    best, best_s = None, 0.0
    for _ in range(300):
        a, b, c = sub[rng.integers(0, len(sub), 3)]
        n = np.cross(b - a, c - a)
        if np.linalg.norm(n) < 1e-12:
            continue
        n /= np.linalg.norm(n)
        s = np.count_nonzero(np.abs((sub - a) @ n) < tol)
        if s > best_s:
            best, best_s = (n, float(a @ n)), s
    if best is None:
        return None
    n, off = best
    inl = np.abs(pts @ n - off) < tol
    c = pts[inl].mean(0)  # least squares refit on the inliers
    n = np.linalg.svd(pts[inl] - c, full_matrices=False)[2][2]
    off = float(c @ n)
    d = pts @ n - off
    inl = np.abs(d) < tol
    if w[inl].sum() < 0.08 * w.sum():
        return None
    up, down = w[d > tol].sum(), w[d < -tol].sum()
    if max(up, down) < 0.9 * (up + down):
        return None  # stuff on both sides: a shelf inside the object, not a table
    if down > up:
        n, off, d = -n, -off, -d
    B = _plane_basis(n)
    obj = pts[d > tol] @ B
    tab = pts[inl] @ B
    if len(obj) < 50 or np.ptp(tab, 0).prod() < 1.3 * np.ptp(obj, 0).prod():
        return None  # flat patch no wider than the object: a flat base, not a table
    return n, off, tol


def _cut_plane(mesh, n, off, tol):
    """Drop everything on or below the table and pull the new cut edge down onto the table."""
    d = mesh.vertices @ n - off
    keep = (d[mesh.faces] > tol).all(1)
    mesh = trimesh.Trimesh(mesh.vertices.copy(), mesh.faces[keep], process=False)
    mesh.remove_unreferenced_vertices()
    e = np.sort(mesh.faces[:, [0, 1, 1, 2, 2, 0]].reshape(-1, 2), axis=1)
    uniq, cnt = np.unique(e, axis=0, return_counts=True)
    rim = np.unique(uniq[cnt == 1])
    d = mesh.vertices @ n - off
    rim = rim[d[rim] < 3 * tol]
    mesh.vertices[rim] -= np.outer(d[rim], n)
    return mesh


def _meshfix(mesh, cap=None):
    """MeshFix on one part: fill every hole, remove self intersections and leftovers.
    Above `cap` faces, fill holes, simplify with manifold3d to `cap`, then clean the small mesh.
    MeshFix clean is the slow step and grows faster than the face count (1.9M faces took 230 s)."""
    fix = pymeshfix.MeshFix(np.asarray(mesh.vertices, float), np.asarray(mesh.faces, np.int32))
    fix.remove_smallest_components()  # first, so holes are not filled on junk
    fix.fill_holes(0, True)
    if cap and len(fix.faces) > cap:
        man = to_manifold(trimesh.Trimesh(fix.points, fix.faces, process=False))
        if man is not None:
            tol = 2e-4 * float(np.ptp(fix.points, 0).max())
            small = man.simplify(tol)
            while small.num_tri() > cap:
                tol *= 1.4
                small = man.simplify(tol)
            return _meshfix(from_manifold(small))
    fix.clean()
    return trimesh.Trimesh(fix.points, fix.faces, process=True)


def _base_width(mesh, down, com):
    """How wide a base the object has when `down` faces the floor, or 0 if it would tip over.
    The base is the patch of points in the lowest 3% of its height. The centre of mass must sit over it."""
    h = mesh.vertices @ -down
    band = mesh.vertices[h < h.min() + 0.03 * np.ptp(h)]
    B = _plane_basis(down)
    p, c = band @ B, com @ B
    if len(p) < 3 or np.ptp(p, 0).min() < 0.1 * np.ptp(mesh.vertices @ B, 0).max():
        return 0.0
    hull = ConvexHull(p)
    if (hull.equations[:, :2] @ c + hull.equations[:, 2] > 0.02 * np.ptp(p, 0).max()).any():
        return 0.0
    return float(np.ptp(p, 0).min())


def _upright(mesh, plane_n):
    """Rotation (4x4) that stands the object up, and a reason or None if it stays as is."""
    if plane_n is not None:
        if plane_n[2] > np.cos(np.radians(3)):
            return np.eye(4), None
        return trimesh.geometry.align_vectors(plane_n, [0, 0, 1]), "turned it so the table side is down"
    com = mesh.center_mass if mesh.is_watertight else mesh.centroid
    wz = _base_width(mesh, np.array([0, 0, -1.0]), com)
    wy = _base_width(mesh, np.array([0, -1.0, 0]), com)
    if wy > 1.5 * wz:  # stands much better on -y: the file was saved Y-up
        return trimesh.geometry.align_vectors([0, 1, 0], [0, 0, 1]), "turned it from Y-up to Z-up"
    if wz:
        return np.eye(4), None
    tfs, probs = trimesh.poses.compute_stable_poses(mesh, n_samples=1)
    ok = [T for T, p in zip(tfs, probs) if p > 0.02] or list(tfs[:1])
    heights = [(trimesh.transform_points([com], T)[0, 2] - trimesh.transform_points(mesh.vertices, T)[:, 2].min())
               for T in ok]
    T = ok[int(np.argmin(heights))].copy()  # lowest centre of mass is the steadiest pose
    T[:3, 3] = 0
    return T, "it was lying at an angle, so it was turned to stand on its steadiest side"


def _yaw_align(mesh):
    """Spin about z so the main direction of the footprint runs along x (area weighted PCA).
    A block lines up with its long edge, a mug with its handle."""
    p, w = mesh.triangles_center[:, :2], mesh.area_faces
    c = p - np.average(p, axis=0, weights=w)
    _, vec = np.linalg.eigh((c * w[:, None]).T @ c)
    return trimesh.transformations.rotation_matrix(-np.arctan2(vec[1, 1], vec[0, 1]), [0, 0, 1])


def _thin_faces(man, mesh, min_mm):
    """Faces whose opposite wall is closer than min_mm."""
    c, n = mesh.triangles_center, mesh.face_normals
    out = np.zeros(len(c), bool)
    for i in range(len(c)):
        for hit in man.ray_cast(c[i] - n[i] * 1e-3, c[i] - n[i] * min_mm):
            if np.dot(hit.normal, n[i]) < -0.5:
                out[i] = True
                break
    return out


def _grow(faces, sel, rings):
    """Grow a face selection by vertex-sharing rings."""
    for _ in range(rings):
        vs = np.zeros(faces.max() + 1, bool)
        vs[faces[sel].ravel()] = True
        sel = vs[faces].any(1)
    return sel


def mesh_points(pts, cap_bottom=False, res=160):
    """Points to a closed mesh with no extra dependency: voxelise, morphological close,
    fill the inside, then a level set through manifold3d.
    ponytail: no normals used, so thin open sheets come out thick. Open3D Poisson is the upgrade."""
    size = float(np.ptp(pts, 0).max())
    h = size / res
    spacing = float(np.median(cKDTree(pts).query(pts[:: max(1, len(pts) // 5000)], k=2)[0][:, 1]))
    r = max(2, int(np.ceil(1.5 * spacing / h)))
    r0, solid = r, None
    # Grow the closing radius until the inside fills. Then try capping the open bottom
    # (gravity-aligned scans miss the underside).
    for r, cap in [(r0, cap_bottom), (2 * r0, cap_bottom), (r0, True), (2 * r0, True), (4 * r0, True)]:
        pad = r + 3
        lo = pts.min(0) - pad * h
        idx = np.floor((pts - lo) / h).astype(int)
        occ = np.zeros(idx.max(0) + pad + 1, bool)
        occ[tuple(idx.T)] = True
        closed = ndimage.binary_dilation(occ, iterations=r)
        if cap:
            k0 = int(np.argmax(closed.any((0, 1))))
            for k in range(k0, k0 + r + 1):
                closed[:, :, k] = ndimage.binary_fill_holes(closed[:, :, k])
        solid = ndimage.binary_fill_holes(closed)
        if solid.sum() > 1.3 * closed.sum():
            break
    else:
        return None  # never closed: leave it to the caller
    solid = ndimage.binary_erosion(solid, iterations=r, border_value=0)
    sdf = (ndimage.distance_transform_edt(solid) - ndimage.distance_transform_edt(~solid)) * h
    sdf = ndimage.gaussian_filter(sdf, 0.8)
    nx, ny, nz = sdf.shape
    flat = sdf.ravel().tolist()

    def f(x, y, z):  # trilinear lookup, plain Python is fast enough here
        x, y, z = (x - lo[0]) / h - 0.5, (y - lo[1]) / h - 0.5, (z - lo[2]) / h - 0.5
        i, j, k = int(x), int(y), int(z)
        if i < 0 or j < 0 or k < 0 or i >= nx - 1 or j >= ny - 1 or k >= nz - 1:
            return -size
        fx, fy, fz = x - i, y - j, z - k
        b = (i * ny + j) * nz + k
        c00 = flat[b] * (1 - fz) + flat[b + 1] * fz
        c01 = flat[b + nz] * (1 - fz) + flat[b + nz + 1] * fz
        b += ny * nz
        c10 = flat[b] * (1 - fz) + flat[b + 1] * fz
        c11 = flat[b + nz] * (1 - fz) + flat[b + nz + 1] * fz
        return (c00 * (1 - fy) + c01 * fy) * (1 - fx) + (c10 * (1 - fy) + c11 * fy) * fx

    hi = lo + np.array(sdf.shape) * h
    man = m3d.Manifold.level_set(f, [*lo, *hi], 1.5 * h)
    return from_manifold(man)


# ---------- the pipeline ----------

def clean_scan(mesh, longest_mm=None, max_faces=50_000, smooth_iters=10, progress=None,
               min_wall_mm=MIN_WALL_MM, orient=True, seed=0):
    """Clean a scan. Returns a dict: mesh (mm, on z=0), quality (0-100), warnings (plain English for the UI),
    log (technical lines), parts, rotated, scale_guessed."""
    say = progress or (lambda frac, step: None)
    rng = np.random.default_rng(seed)
    log, warn = [], []
    penalty = 0
    is_points = len(mesh.faces) == 0
    log.append(f"in: {len(mesh.vertices)} verts, {len(mesh.faces)} faces, extents {np.round(np.ptp(mesh.vertices, 0), 4).tolist()}")

    # 1. Point clouds: find the table first, then build a surface.
    plane_n = None
    if is_points:
        say(0.05, "building a surface from points")
        pts = np.asarray(mesh.vertices, float)
        plane = _support_plane(pts, np.ones(len(pts)), rng)
        if plane is not None:
            n, off, tol = plane
            d = pts @ n - off
            R = trimesh.geometry.align_vectors(n, [0, 0, 1])
            pts = trimesh.transform_points(pts[d > tol], R)
            z0 = off  # the table is now the plane z = off
            rim = pts[pts[:, 2] < z0 + 2 * tol].copy()
            rim[:, 2] = z0  # copy the lowest ring down onto the table so the object keeps its full height
            pts = np.vstack([pts, rim])
            plane_n = np.array([0, 0, 1.0])  # already turned
            warn.append("A flat table under the object was found and cut away.")
        # drop stray points far from the rest
        dd = cKDTree(pts).query(pts, k=8)[0][:, -1]
        pts = pts[dd < 5 * np.median(dd)]
        mesh = mesh_points(pts, cap_bottom=plane is not None)
        if mesh is None:
            raise ValueError("could not build a closed surface from these points, the scan has too many gaps")
        log.append(f"meshed {len(pts)} points -> {len(mesh.faces)} faces")
        warn.append("The file had points only, no surface. A surface was built from them, so fine detail is softer.")
        penalty += 10

    # 3. Cut away a scanned table.
    if not is_points:
        say(0.15, "looking for a table")
        w = np.bincount(mesh.faces.ravel(), np.repeat(mesh.area_faces, 3), len(mesh.vertices))
        plane = _support_plane(np.asarray(mesh.vertices, float), w, rng)
        if plane is not None:
            plane_n = plane[0]
            mesh = _cut_plane(mesh, *plane)
            warn.append("A flat table under the object was found and cut away.")
            log.append(f"table cut, normal {np.round(plane_n, 3).tolist()}")

    # 4. Parts: keep big plausible pieces, drop floaters.
    say(0.2, "removing loose bits")
    lab = _face_labels(mesh.faces, len(mesh.vertices))
    area = np.bincount(lab, mesh.area_faces)
    keep = np.flatnonzero(area >= KEEP_PART * area.max())
    keep = keep[np.argsort(-area[keep])][:4]
    # A big piece sitting inside the main piece's box is a second scan layer from drift, not a second object.
    box = [mesh.vertices[mesh.faces[lab == k].ravel()] for k in keep]
    lo, hi = box[0].min(0), box[0].max(0)
    keep = [k for k, b in zip(keep, box) if k == keep[0] or
            ((b >= lo) & (b <= hi)).all(1).mean() < 0.5]
    dropped = int((area > 0).sum() - len(keep))
    if dropped:
        log.append(f"dropped {dropped} small pieces ({100 * (area.sum() - area[keep].sum()) / area.sum():.1f}% of area)")
    if dropped > 3:
        warn.append(f"Removed {dropped} loose bits floating around the object (dust, fingers, background).")

    # 5. Smooth, measure holes, repair, per part.
    parts, holes = [], []
    for i, pid in enumerate(keep):
        say(0.25 + 0.35 * i / len(keep), "smoothing and repairing")
        part = trimesh.Trimesh(mesh.vertices, mesh.faces[lab == pid], process=False)
        part.remove_unreferenced_vertices()
        # Bench finding: 0.3 mm noise left in makes MeshFix cut off a mug handle as "self intersecting".
        if smooth_iters and not is_points:
            _smooth(part, smooth_iters)
        holes += _boundary_loops(part)
        before = _extents(part.vertices)
        if len(part.faces) > PRE_CAP:
            say(0.3, "thinning out a big scan")
        fixed = _meshfix(part, PRE_CAP)
        if len(fixed.faces) == 0:
            continue
        lost = 1 - _extents(fixed.vertices) / before
        if lost.max() > 0.04 and not is_points:
            # Repair cut a chunk off. Rebuild this part from its points instead.
            log.append(f"meshfix lost {lost.max():.0%} of a side, rebuilding from points")
            rebuilt = mesh_points(part.sample(min(200_000, 20 * len(part.faces))))
            if rebuilt is not None:
                fixed = _meshfix(rebuilt)
                warn.append("The surface was tangled (double walls or overlaps), so it was rebuilt. "
                            "Fine detail is softer.")
                penalty += 10
            else:
                warn.append("Repair cut part of the shape away. Check thin parts like handles and ears.")
                penalty += 20
        parts.append(fixed)
    if not parts:
        raise ValueError("repair left nothing, input is too broken")
    log.append(f"meshfix: {sum(len(p.faces) for p in parts)} faces in {len(parts)} part(s)")
    mesh = trimesh.util.concatenate(parts) if len(parts) > 1 else parts[0]

    # 6. Which way is down.
    say(0.65, "standing it up")
    T = np.eye(4)
    if orient:
        T, why = _upright(mesh, plane_n if not is_points else None)
        if why:
            T = _yaw_align(mesh.copy().apply_transform(T)) @ T
            mesh.apply_transform(T)
            warn.append(f"The scan was not upright, so {why}. Check it looks the right way up.")
            penalty += 5
            log.append(f"rotated: {why}")

    # 7. Scale to mm. A known real length beats any unit guess.
    longest = float(mesh.extents.max())
    factor = longest_mm / longest if longest_mm else guess_scale_to_mm(longest)
    mesh.apply_scale(factor)
    S = np.diag([factor] * 3 + [1.0]) @ T
    log.append(f"scale x{factor:.4g} -> longest {mesh.extents.max():.2f} mm")
    if not longest_mm and mesh.extents.max() > 250:
        shrink = 200.0 / mesh.extents.max()  # unknown real size and too big for the bed: fit it, the warning below says so
        mesh.apply_scale(shrink)
        S = np.diag([shrink] * 3 + [1.0]) @ S
        warn.append("The scan was bigger than the print bed, so it was shrunk to fit. Enter its real longest side to get the true size.")
    if not longest_mm:
        unit = {1000.0: "metres", 10.0: "centimetres", 1.0: "millimetres"}[factor]
        warn.append(f"No real size was given, so the file was read as {unit} "
                    f"(longest side {mesh.extents.max():.0f} mm). Measure the real object and enter its longest side.")
        penalty += 10

    # 8. Manifold and decimate.
    say(0.75, "simplifying")
    mans = [to_manifold(p) for p in (mesh.split(only_watertight=False) if len(parts) > 1 else [mesh])]
    if any(m is None for m in mans):
        raise ValueError("mesh is still not manifold after repair")
    man = m3d.Manifold.batch_boolean(mans, m3d.OpType.Add) if len(mans) > 1 else mans[0]
    man = _decimate(man, max_faces, float(mesh.extents.max()))
    mesh = _drop_slivers(from_manifold(man))

    # 9. Webs thinner than a printer can make: bridged ears and handles.
    if min_wall_mm:
        say(0.85, "checking for thin webs")
        thin = _thin_faces(man, mesh, min_wall_mm)
        web = _grow(mesh.faces, thin, 2) if thin.any() else thin
        web_area = float(mesh.area_faces[thin].sum())
        if web_area > max(60.0, 0.005 * mesh.area):
            rest = trimesh.Trimesh(mesh.vertices, mesh.faces[~web], process=False)
            rest.remove_unreferenced_vertices()
            lab = _face_labels(rest.faces, len(rest.vertices))
            a = np.bincount(lab, rest.area_faces)
            fixed = [_meshfix(trimesh.Trimesh(rest.vertices, rest.faces[lab == i], process=False))
                     for i in np.flatnonzero(a >= KEEP_PART * a.max())]
            mans = [m for m in (to_manifold(f) for f in fixed if len(f.faces)) if m is not None]
            if mans:
                man = m3d.Manifold.batch_boolean(mans, m3d.OpType.Add) if len(mans) > 1 else mans[0]
                mesh = _drop_slivers(from_manifold(man))
                warn.append(f"Removed {web_area / 2:.0f} mm2 of paper-thin web (thinner than {min_wall_mm} mm), "
                            "often a scan bridging an ear or handle to the body. Check those spots.")
                penalty += 10
                log.append(f"thin web removed: {web_area:.0f} mm2 of faces under {min_wall_mm} mm")

    # 10. Report holes in plain words, now that we know up and size.
    size = float(mesh.extents.max())
    lo, hi = mesh.bounds
    big = []
    for c, diam in holes:
        c = trimesh.transform_points([c], S)[0]
        diam *= factor
        if diam > 0.12 * size:
            zf = (c[2] - lo[2]) / max(hi[2] - lo[2], 1e-9)
            where = "bottom" if zf < 0.15 else "top" if zf > 0.85 else "side"
            big.append((diam, where))
    penalty += min(30, sum(40 * d / size for d, _ in big))
    seen = set()
    for diam, where in sorted(big, reverse=True):
        if where in seen:
            continue
        seen.add(where)
        what = "The bottom was missing" if where == "bottom" and diam > 0.4 * size else \
            f"A gap about {diam:.0f} mm across on the {where} was missing"
        warn.append(f"{what} and was filled in with a smooth patch. Check that area.")
    small = len(holes) - len(big)
    if small:
        log.append(f"filled {small} small holes")
    if len(parts) > 1:
        warn.append(f"Kept {len(parts)} separate pieces. They will print as separate parts.")
        penalty += 5

    # 11. Sit it on the build plate, centred on x and y.
    say(0.95, "placing on the build plate")
    lo, hi = mesh.bounds
    mesh.apply_translation([-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]])
    log.append(f"out: {len(mesh.faces)} faces, extents {np.round(mesh.extents, 2).tolist()} mm")
    say(1.0, "done")
    return {"mesh": mesh, "quality": int(max(0, round(100 - penalty))), "warnings": warn, "log": log,
            "parts": len(parts), "rotated": not np.allclose(T, np.eye(4)), "scale_guessed": not longest_mm}


def _drop_slivers(mesh):
    """Simplify can leave a zero-volume sliver pinched onto the surface by one edge. Drop such bits."""
    if mesh.is_watertight:
        return mesh
    bits = mesh.split(only_watertight=False)
    big = max(b.area for b in bits)
    return trimesh.util.concatenate([b for b in bits if b.area > 0.01 * big])


def _decimate(man, max_faces, size):
    """manifold3d simplify with a growing tolerance until under max_faces."""
    tol = 0.0005 * size
    while man.num_tri() > max_faces and tol < 0.05 * size:
        man = man.simplify(tol)
        tol *= 1.4
    return man


def clean(mesh, longest_mm=None, max_faces=50_000, smooth_iters=10, progress=None):
    """Return (clean mesh in mm sitting on z=0, list of log lines). Warnings are appended to the log.
    Use clean_scan() for the quality score and warnings as separate fields."""
    r = clean_scan(mesh, longest_mm, max_faces, smooth_iters, progress)
    return r["mesh"], r["log"] + [f"warning: {w}" for w in r["warnings"]] + [f"quality: {r['quality']}"]


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--longest-mm", type=float, help="measured longest side of the real object")
    ap.add_argument("--max-faces", type=int, default=50_000)
    ap.add_argument("--report", help="write quality, warnings and log as JSON here")
    ap.add_argument("--progress", action="store_true", help="print JSON progress lines")
    a = ap.parse_args()
    prog = (lambda f, s: print(json.dumps({"progress": round(f, 2), "step": s}), flush=True)) if a.progress else None
    r = clean_scan(load(a.src), a.longest_mm, a.max_faces, progress=prog)
    if not a.progress:
        print("\n".join(r["log"]))
        print("\n".join(f"warning: {w}" for w in r["warnings"]))
        print(f"quality: {r['quality']}")
        print(check(r["mesh"]))
    if a.report:
        with open(a.report, "w") as f:
            json.dump({k: r[k] for k in ("quality", "warnings", "log", "parts", "rotated", "scale_guessed")}, f, indent=1)
    r["mesh"].export(a.dst)
    sys.exit(0)
