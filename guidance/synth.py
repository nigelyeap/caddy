"""Synthetic orbit scans with ground truth, for tests and eval_orbit.py.

A small painter's-algorithm renderer: every surface is a flat textured
quad. The scene is a box-shaped part on a table inside a room. The camera
walks around the part like a student would, with optional hand shake,
roll, off-centre framing, height changes, panning, fast steps, rolling
shutter, auto exposure, noise and JPEG compression.

World axes: x right, y up, z towards the start position. Distances in metres.
"""

import math

import cv2
import numpy as np

W, H = 640, 480


def _tex_blocks(rng, w, h, cells):
    small = rng.integers(0, 256, (cells[1], cells[0], 3), dtype=np.uint8)
    return cv2.resize(small, (w, h), interpolation=cv2.INTER_NEAREST)


def _tex_clutter(rng, w, h, base=150, n=60):
    """Room-like clutter: random rectangles, lines and blobs on a soft base."""
    img = np.full((h, w, 3), base, np.uint8)
    img = cv2.add(img, cv2.resize(rng.integers(0, 40, (8, 8, 3), dtype=np.uint8), (w, h)))
    for _ in range(n):
        c = tuple(int(v) for v in rng.integers(0, 256, 3))
        x, y = int(rng.integers(0, w)), int(rng.integers(0, h))
        k = rng.integers(0, 3)
        if k == 0:
            cv2.rectangle(img, (x, y), (x + int(rng.integers(10, w // 4)), y + int(rng.integers(10, h // 4))), c, -1)
        elif k == 1:
            cv2.line(img, (x, y), (int(rng.integers(0, w)), int(rng.integers(0, h))), c, int(rng.integers(1, 5)))
        else:
            cv2.circle(img, (x, y), int(rng.integers(4, w // 12)), c, -1)
    return cv2.addWeighted(img, 0.55, np.full_like(img, base), 0.45, 0)  # duller, like a real room


def _tex_wood(rng, w, h):
    y = np.arange(h)[:, None]
    x = np.arange(w)[None, :]
    g = 120 + 14 * np.sin(y / 3.0 + 4 * np.sin(x / 40.0)) + rng.normal(0, 8, (h, w))
    g = np.clip(g, 0, 255).astype(np.uint8)
    return cv2.merge([g // 2, (g * 0.7).astype(np.uint8), g])


def _tex_plain(color, w=64, h=64):
    return np.full((h, w, 3), color, np.uint8)


def _quad(o, u, v, tex, normal=None, shade=1.0):
    return {"o": np.asarray(o, float), "u": np.asarray(u, float), "v": np.asarray(v, float),
            "tex": tex, "n": None if normal is None else np.asarray(normal, float), "shade": shade}


def _box(center, size, tex_fn, shades=(1.0, 0.8, 0.65, 0.85, 1.1)):
    """Five visible faces of a box (no bottom). Textures come from tex_fn(face_index)."""
    c = np.asarray(center, float)
    sx, sy, sz = (s / 2 for s in size)
    X, Y, Z = np.eye(3)
    faces = [
        (c + [-sx, sy, sz], 2 * sx * X, -2 * sy * Y, Z),    # +z front
        (c + [sx, sy, sz], -2 * sz * Z, -2 * sy * Y, X),    # +x right
        (c + [sx, sy, -sz], -2 * sx * X, -2 * sy * Y, -Z),  # -z back
        (c + [-sx, sy, -sz], 2 * sz * Z, -2 * sy * Y, -X),  # -x left
        (c + [-sx, sy, -sz], 2 * sx * X, 2 * sz * Z, Y),    # +y top
    ]
    return [_quad(o, u, v, tex_fn(i), n, shades[i]) for i, (o, u, v, n) in enumerate(faces)]


def make_scene(obj="textured", room="clutter", seed=0):
    """obj: textured, plain or shiny. room: clutter or plain."""
    rng = np.random.default_rng(seed)
    if obj == "textured":
        def tex(i):
            t = _tex_clutter(rng, 256, 256, base=110, n=25)
            return cv2.addWeighted(t, 0.6, _tex_blocks(rng, 256, 256, (16, 16)), 0.4, 0)
    else:
        grey = (175, 178, 182) if obj == "plain" else (200, 200, 205)

        def tex(i):
            return _tex_plain(grey)
    quads = _box((0, 0.12, 0), (0.30, 0.24, 0.22), tex)
    quads += _box((0.06, 0.29, -0.03), (0.10, 0.10, 0.10), tex)  # a boss on top, so the part is not symmetric
    S = 3.0  # half size of the room
    if room == "clutter":
        wall = [_tex_clutter(rng, 512, 256, base=int(rng.integers(120, 200))) for _ in range(4)]
        floor = _tex_wood(rng, 512, 512)
    else:
        wall = [_tex_plain((215, 215, 215))] * 4
        floor = _tex_plain((225, 225, 222))
    X, Y, Z = np.eye(3)
    hgt = 2.4
    quads += [
        _quad((-S, -0.8 + hgt, -S), 2 * S * X, -hgt * Y, wall[0], Z),
        _quad((S, -0.8 + hgt, -S), 2 * S * Z, -hgt * Y, wall[1], -X),
        _quad((S, -0.8 + hgt, S), -2 * S * X, -hgt * Y, wall[2], -Z),
        _quad((-S, -0.8 + hgt, S), -2 * S * Z, -hgt * Y, wall[3], X),
        _quad((-0.7, 0.0, -0.5), 1.4 * X, 1.0 * Z, floor, Y),          # table top
        _quad((-S, -0.8, -S), 2 * S * X, 2 * S * Z, wall[0][:, ::-1].copy(), Y, 0.6),  # floor
    ]
    return {"quads": quads, "shiny": obj == "shiny", "center": np.array([0.0, 0.15, 0.0])}


def look_rotation(cam, target, yaw_off=0.0, pitch_off=0.0, roll=0.0):
    """World to camera rotation (OpenCV camera: x right, y down, z forward), angles in degrees."""
    f = target - cam
    f = f / np.linalg.norm(f)
    up = np.array([0.0, 1.0, 0.0])
    r = np.cross(f, up)
    r /= np.linalg.norm(r)
    d = np.cross(f, r)
    R = np.stack([r, d, f])  # rows: camera axes in world
    off = cv2.Rodrigues(np.array([math.radians(-pitch_off), math.radians(yaw_off), 0.0]))[0]
    rz = cv2.Rodrigues(np.array([0.0, 0.0, math.radians(roll)]))[0]
    return rz @ off @ R


def arkit_pose(R, cam):
    """4x4 camera to world, camera x right, y up, looking along -z."""
    P = np.eye(4)
    P[:3, :3] = R.T @ np.diag([1.0, -1.0, -1.0])
    P[:3, 3] = cam
    return P


def render(scene, R, cam, f, size=(W, H), near=0.05):
    w, h = size
    K = np.array([[f, 0, w / 2], [0, f, h / 2], [0, 0, 1.0]])
    img = np.full((h, w, 3), 60, np.uint8)
    order = sorted(scene["quads"], key=lambda q: -np.linalg.norm(q["o"] + (q["u"] + q["v"]) / 2 - cam))
    for q in order:
        if q["n"] is not None and np.dot(q["n"], cam - q["o"]) <= 0:
            continue
        corners = np.stack([q["o"], q["o"] + q["u"], q["o"] + q["u"] + q["v"], q["o"] + q["v"]])
        pc = (R @ (corners - cam).T).T
        poly = _clip_near(pc, near)
        if len(poly) < 3:
            continue
        uv = (K @ poly.T).T
        uv = uv[:, :2] / uv[:, 2:]
        if uv[:, 0].max() < 0 or uv[:, 0].min() > w or uv[:, 1].max() < 0 or uv[:, 1].min() > h:
            continue
        tex = q["tex"]
        th, tw = tex.shape[:2]
        Hm = K @ np.column_stack([R @ q["u"] / tw, R @ q["v"] / th, R @ (q["o"] - cam)])
        warped = cv2.warpPerspective(tex, Hm, (w, h), flags=cv2.INTER_LINEAR)
        mask = np.zeros((h, w), np.uint8)
        cv2.fillConvexPoly(mask, np.round(np.clip(uv, -1e4, 1e4) * 16).astype(np.int32), 255, shift=4)
        m = mask > 0
        if q["shade"] != 1.0:
            warped = cv2.convertScaleAbs(warped, alpha=q["shade"])
        img[m] = warped[m]
        if scene["shiny"] and q["n"] is not None and q["shade"] >= 0.65 and np.abs(q["n"][1]) < 0.5:
            # Specular blob: where the mirror of a light above the camera would land on the face.
            cen = corners.mean(0)
            to_cam = cam - cen
            s = np.dot(to_cam / np.linalg.norm(to_cam), q["n"])
            if s > 0.6:
                p = (K @ (R @ (cen - cam)))
                p = p[:2] / p[2]
                spot = np.zeros((h, w), np.float32)
                cv2.circle(spot, (int(p[0]), int(p[1]) - 10), int(25 * s), 1.0, -1)
                spot = cv2.GaussianBlur(spot, (0, 0), 6) * (mask > 0)
                img[:] = np.clip(img + spot[..., None] * 255 * s, 0, 255).astype(np.uint8)
    return img


def _clip_near(pc, near):
    out = []
    n = len(pc)
    for i in range(n):
        a, b = pc[i], pc[(i + 1) % n]
        if a[2] >= near:
            out.append(a)
        if (a[2] >= near) != (b[2] >= near):
            s = (near - a[2]) / (b[2] - a[2])
            out.append(a + s * (b - a))
    return np.array(out)


def degrade(img, rng, shake_px=0.0, rs_px=0.0, gain=1.0, noise=0.0, jpeg=None):
    """Motion blur, rolling shutter skew, exposure gain, sensor noise and JPEG."""
    out = img
    if shake_px > 0.5:
        k = int(round(shake_px)) | 1
        ker = np.zeros((k, k), np.float32)
        ker[k // 2, :] = 1.0 / k
        out = cv2.filter2D(out, -1, ker)
    if abs(rs_px) > 0.5:
        h, w = out.shape[:2]
        mx = (np.arange(w)[None, :] + rs_px * (np.arange(h)[:, None] / h - 0.5)).astype(np.float32)
        my = np.repeat(np.arange(h, dtype=np.float32)[:, None], w, 1)
        out = cv2.remap(out, np.broadcast_to(mx, (h, w)).copy(), my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    if gain != 1.0 or noise > 0:
        f = out.astype(np.float32) * gain
        if noise > 0:
            f += rng.normal(0, noise, f.shape).astype(np.float32)
        out = np.clip(f, 0, 255).astype(np.uint8)
    if jpeg:
        out = cv2.imdecode(cv2.imencode(".jpg", out, [cv2.IMWRITE_JPEG_QUALITY, jpeg])[1], cv2.IMREAD_COLOR)
    return out


# Scenario knobs. Angles in degrees, speeds in degrees per second, 1 frame per second.
BASE = dict(obj="textured", room="clutter", laps=1.0, speed=10.0, speed_jitter=0.0, radius=0.75,
            elev=10.0, elev_swing=0.0, yaw_off=0.0, pitch_off=0.0, roll=0.0, shake=0.0,
            focal=0.8, rs=0.0, ae=0.0, noise=0.0, jpeg=None, pan=None, jumps=(), blind=(),
            size=(W, H))

SCENARIOS = {
    "clean": {},
    "handheld": dict(shake=2.0, speed_jitter=4.0, rs=6.0, ae=0.15, noise=3.0, jpeg=75),
    "off_centre": dict(yaw_off=12.0, pitch_off=-8.0, shake=1.0),
    "looking_down": dict(elev=35.0, shake=1.0),
    "crooked_roll": dict(roll=15.0, shake=1.0),
    "up_and_down": dict(elev_swing=20.0, shake=1.0),
    "focal_1.1": dict(focal=1.1, shake=1.0),
    "focal_0.6": dict(focal=0.6, shake=1.0),
    "fast_steps": dict(jumps=((8, 35.0), (16, 45.0), (20, 70.0)), laps=1.2),
    "pan_in_place": dict(pan=(10, 4, 10.0), shake=1.0),
    "lost_turning": dict(blind=(12, 13, 14), shake=1.0),
    "plain_object": dict(obj="plain", shake=1.0),
    "shiny_object": dict(obj="shiny", shake=1.0),
    "plain_everything": dict(obj="plain", room="plain", laps=0.5),
    "two_laps_handheld": dict(laps=2.0, shake=2.0, speed_jitter=4.0, rs=6.0, ae=0.15, noise=3.0, jpeg=75),
}


def scenario(name, seed=1, **over):
    """Yield (frame_bgr, t, truth) for one scan. truth has azimuth_deg, pose (ARKit 4x4), focal_px."""
    p = {**BASE, **SCENARIOS.get(name, {}), **over}
    rng = np.random.default_rng(seed)
    scene = make_scene(p["obj"], p["room"], seed)
    w, h = p["size"]
    f = p["focal"] * w
    total = 360.0 * p["laps"]
    az, i, gain = 0.0, 0, 1.0
    jumps = dict(p["jumps"])
    pan_start, pan_len, pan_rate = p["pan"] if p["pan"] else (-1, 0, 0.0)
    pan = 0.0
    prev_rate = 0.0
    while az <= total + 1e-6:
        elev = p["elev"] + p["elev_swing"] * math.sin(math.radians(az) * 2)
        r = p["radius"] + p["shake"] * 0.01 * rng.normal()
        th, el = math.radians(az), math.radians(elev)
        target = scene["center"]
        cam = target + r * np.array([math.sin(th) * math.cos(el), math.sin(el), math.cos(th) * math.cos(el)])
        cam = cam + p["shake"] * 0.005 * rng.normal(size=3)
        R = look_rotation(cam, target,
                          yaw_off=p["yaw_off"] + pan + p["shake"] * rng.normal(),
                          pitch_off=p["pitch_off"] + p["shake"] * 0.7 * rng.normal(),
                          roll=p["roll"] + p["shake"] * 1.5 * rng.normal())
        img = render(scene, R, cam, f, (w, h))
        if i in p["blind"]:
            img = np.full_like(img, 30) + rng.integers(0, 6, img.shape, dtype=np.uint8)  # hand over the lens
        if p["ae"]:
            gain = float(np.clip(gain * math.exp(p["ae"] * rng.normal()), 0.7, 1.35))
        img = degrade(img, rng, shake_px=p["shake"] * 1.5 * abs(rng.normal()), rs_px=p["rs"] * prev_rate / 10.0,
                      gain=gain, noise=p["noise"], jpeg=p["jpeg"])
        yield img, float(i), {"azimuth_deg": az, "pose": arkit_pose(R, cam), "focal_px": f, "camera": cam}
        # Advance to the next frame.
        i += 1
        if pan_start <= i < pan_start + pan_len:
            pan += pan_rate * (1 if i < pan_start + pan_len / 2 else -1)  # turn away then back, feet still
            prev_rate = pan_rate
            continue
        step = jumps.get(i, p["speed"] + p["speed_jitter"] * rng.normal())
        step = max(step, 0.5)
        prev_rate = step
        az += step
