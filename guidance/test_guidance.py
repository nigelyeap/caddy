"""Synthetic checks for guidance.py. Run: uv run python test_guidance.py"""

import json
import math
import time

import cv2
import numpy as np

import guidance as g
import synth

W, H = 640, 480
RNG = np.random.default_rng(0)


def texture(seed, w=W, h=H, cells=(80, 60)):
    # Blocky random texture: lots of corners for ORB.
    small = np.random.default_rng(seed).integers(0, 256, (cells[1], cells[0], 3), dtype=np.uint8)
    return cv2.resize(small, (w, h), interpolation=cv2.INTER_NEAREST)


def render_box(theta_deg, faces, radius=3.2):
    """Camera orbits a textured 2x2x2 box at the origin, looking at its centre."""
    th = math.radians(theta_deg)
    C = np.array([radius * math.sin(th), 0.0, -radius * math.cos(th)])
    fwd = -C / np.linalg.norm(C)
    down = np.array([0.0, 1.0, 0.0])
    Rcw = np.stack([np.cross(down, fwd), down, fwd])
    f = g.FOCAL_FRAC * W
    K = np.array([[f, 0, W / 2], [0, f, H / 2], [0, 0, 1]])
    img = np.full((H, W, 3), 90, np.uint8)
    for corners, normal, tex in faces:
        if np.dot(normal, C - corners.mean(0)) <= 0:
            continue  # back face
        pc = (Rcw @ (corners - C).T).T
        uv = (K @ pc.T).T
        uv = (uv[:, :2] / uv[:, 2:]).astype(np.float32)
        th_, tw = tex.shape[:2]
        src = np.float32([[0, 0], [tw, 0], [tw, th_], [0, th_]])
        Hm = cv2.getPerspectiveTransform(src, uv)
        warped = cv2.warpPerspective(tex, Hm, (W, H))
        mask = cv2.warpPerspective(np.full((th_, tw), 255, np.uint8), Hm, (W, H)) > 0
        img[mask] = warped[mask]
    return img


def box_faces():
    faces = []
    for i, (n, right) in enumerate([((0, 0, -1), (1, 0, 0)), ((1, 0, 0), (0, 0, 1)),
                                    ((0, 0, 1), (-1, 0, 0)), ((-1, 0, 0), (0, 0, -1))]):
        n, r = np.array(n, float), np.array(right, float)
        down = np.array([0.0, 1.0, 0.0])
        c = n  # face centre on a 2x2x2 box
        corners = np.stack([c - r - down, c + r - down, c + r + down, c - r + down])
        faces.append((corners, n, texture(100 + i, 400, 400, (40, 40))))
    return faces


def test_sharp_ok():
    r = g.Session().update(texture(1), 0.0)
    assert r["blur"]["ok"] and r["light"]["ok"] and r["tracking"]["ok"], r
    json.dumps(r)


def test_blur():
    r = g.Session().update(cv2.GaussianBlur(texture(1), (31, 31), 8), 0.0)
    assert not r["blur"]["ok"], r["blur"]


def test_dark():
    r = g.Session().update((texture(1) * 0.15).astype(np.uint8), 0.0)
    assert r["light"]["issue"] == "dark", r["light"]


def test_overexposed():
    img = np.clip(texture(1).astype(int) * 3 + 60, 0, 255).astype(np.uint8)
    r = g.Session().update(img, 0.0)
    assert r["light"]["issue"] == "bright", r["light"]


def test_glare():
    img = (texture(1) * 0.6).astype(np.uint8)
    cv2.circle(img, (320, 240), 90, (255, 255, 255), -1)  # about 8 percent of the frame
    r = g.Session().update(img, 0.0)
    assert r["light"]["issue"] == "glare", r["light"]


def test_tracking_loss_and_debounce():
    s = g.Session()
    s.update(texture(1), 0.0)
    r1 = s.update(texture(2), 1.0)
    assert not r1["tracking"]["ok"] and r1["tracking"]["match_ratio"] < 0.05, r1["tracking"]
    assert g.MESSAGES["tracking"] not in r1["warnings"], "one bad frame should not warn yet"
    r2 = s.update(texture(3), 2.0)
    assert g.MESSAGES["tracking"] in r2["warnings"], r2
    # Back on track: the warning holds for WARN_HOLD_S, then clears.
    ref = texture(1)  # the reference frame is still the last tracked one
    r3 = s.update(ref, 3.0)
    assert r3["tracking"]["ok"] and g.MESSAGES["tracking"] in r3["warnings"], r3
    r4 = s.update(ref, 2.0 + g.WARN_HOLD_S + 0.1)
    assert g.MESSAGES["tracking"] not in r4["warnings"], r4


def test_same_frame_tracks():
    s = g.Session()
    s.update(texture(1), 0.0)
    r = s.update(texture(1), 1.0)
    assert r["tracking"]["ok"] and r["tracking"]["match_ratio"] > 0.8, r["tracking"]
    assert r["speed"]["value"] == 0.0


def test_orbit_coverage():
    s, faces = g.Session(), box_faces()
    pcts = []
    for i in range(19):  # 0 to 180 degrees, 10 degrees per second
        r = s.update(render_box(i * 10.0, faces), float(i))
        assert r["tracking"]["ok"], (i, r["tracking"])
        pcts.append(r["coverage"]["pct"])
    est = abs(r["orbit"]["angle_deg"])
    print(f"  orbit: true 180 deg, estimated {est:.1f} deg, coverage {pcts[-1]:.1f} percent")
    assert all(b >= a for a, b in zip(pcts, pcts[1:])), pcts
    assert 150 <= est <= 210, est
    assert 40 <= pcts[-1] <= 60, pcts[-1]
    assert r["speed"]["ok"] and 5 < r["speed"]["value"] < 15, r["speed"]
    assert sum(v > 0.9 for v in r["coverage"]["sectors"]) >= 5, r["coverage"]


def test_fast_orbit_warns():
    s, faces = g.Session(), box_faces()
    for i in range(4):
        r = s.update(render_box(i * 30.0, faces), float(i))
    assert g.MESSAGES["speed"] in r["warnings"] or g.MESSAGES["tracking"] in r["warnings"], r


def _orbit_poses(n, step=10.0, elev=10.0, radius=0.6, turn_only=False):
    """ARKit style camera to world poses walking round a part at the origin."""
    for i in range(n):
        th, el = math.radians(i * step), math.radians(elev)
        cam = radius * np.array([math.sin(th) * math.cos(el), math.sin(el), math.cos(th) * math.cos(el)])
        if turn_only:  # feet still, only the phone turns
            cam = np.array([0.0, 0.2, radius])
            target = cam + np.array([-math.sin(th), -0.3, -math.cos(th)])
        else:
            target = np.zeros(3)
        yield synth.arkit_pose(synth.look_rotation(cam, target), cam)


def test_pose_orbit():
    s = g.Session()
    for i, pose in enumerate(_orbit_poses(10, elev=30.0)):
        r = s.update(texture(1), float(i), pose=pose)
    json.dumps(r)
    assert abs(abs(r["orbit"]["angle_deg"]) - 90) < 1.0, r["orbit"]
    assert 20 <= r["coverage"]["pct"] <= 30, r["coverage"]
    rings = r["coverage"]["rings"]
    assert sum(rings["mid"]) > 0 and sum(rings["low"]) == 0, rings
    assert abs(r["orbit"]["elevation_deg"] - 30) < 2, r["orbit"]
    assert g.MESSAGES["panning"] not in r["warnings"], r["warnings"]


def test_pose_panning_warns():
    s = g.Session()
    for i, pose in enumerate(_orbit_poses(6, turn_only=True)):
        r = s.update(texture(1), float(i), pose=pose)
    assert r["orbit"]["panning"] and g.MESSAGES["panning"] in r["warnings"], r
    assert r["coverage"]["pct"] < 10, r["coverage"]


def test_depth_distance():
    pose = next(_orbit_poses(1))
    for metres, key in ((0.1, "too_close"), (3.0, "too_far")):
        s = g.Session()
        for i in range(3):
            r = s.update(texture(1), float(i), depth=np.full((192, 256), metres, np.float32), pose=pose)
        assert g.MESSAGES[key] in r["warnings"], (metres, r["warnings"])
    s = g.Session()
    mm = np.full((192, 256), 500, np.uint16)  # ARKit depth exported as millimetres
    r = s.update(texture(1), 0.0, depth=mm, pose=pose)
    assert abs(r["orbit"]["distance_m"] - 0.5) < 1e-6, r["orbit"]


def test_white_scene_is_not_too_bright():
    img = (texture(1) * 0.12 + 212).astype(np.uint8)  # white part on a white table, nothing blown out
    r = g.Session().update(img, 0.0)
    assert r["light"]["ok"], r["light"]


def _scan(name, **over):
    s, rows = g.Session(), []
    for img, t, truth in synth.scenario(name, **over):
        r = s.update(img, t)
        rows.append((truth["azimuth_deg"], r))
    json.dumps(rows[-1][1])
    err = rows[-1][1]["orbit"]["angle_deg"] - rows[-1][0]
    print(f"  {name}: true {rows[-1][0]:.0f} deg, error {err:+.1f} deg")
    return rows, err


def test_synth_half_lap():
    rows, err = _scan("clean", laps=0.5)
    assert abs(err) < 8, err
    assert all(r["tracking"]["ok"] for _, r in rows)
    assert 45 <= rows[-1][1]["coverage"]["pct"] <= 60, rows[-1][1]["coverage"]


def test_synth_crooked_and_off_centre():
    for name in ("crooked_roll", "off_centre"):
        _, err = _scan(name, laps=0.5)
        assert abs(err) < 10, (name, err)


def test_synth_panning_warns():
    rows, err = _scan("pan_in_place", laps=0.5)
    assert any(g.MESSAGES["panning"] in r["warnings"] for _, r in rows)
    assert abs(err) < 15, err


def test_synth_loop_fixes_focal_guess():
    # Camera is much wider than the engine assumes. Closing the lap corrects it.
    rows, err = _scan("focal_0.6")
    assert rows[-1][1]["orbit"]["loops_closed"] >= 1, rows[-1][1]["orbit"]
    assert abs(err) < 15, err


def test_synth_lost_turn_recovered():
    # A 70 degree jump loses tracking. Coming back to the start fixes the angle
    # without wrongly changing the focal length.
    rows, err = _scan("fast_steps")
    assert any(not r["tracking"]["ok"] for _, r in rows)
    assert abs(err) < 15, err
    assert abs(rows[-1][1]["orbit"]["focal_frac"] - g.FOCAL_FRAC) < 1e-9


def test_latency_720p():
    for size in ((1280, 720), (720, 1280)):
        s, ms = g.Session(), []
        for i, (img, t, _) in enumerate(synth.scenario("handheld", size=size)):
            if i == 8:
                break
            t0 = time.perf_counter()
            s.update(img, t)
            ms.append((time.perf_counter() - t0) * 1000)
        print(f"  {size[0]}x{size[1]}: median {np.median(ms[1:]):.0f} ms, max {max(ms[1:]):.0f} ms")
        assert np.median(ms[1:]) < 200, ms


def test_reset():
    s = g.Session()
    s.update(texture(1), 0.0)
    s.reset()
    assert s.update(texture(2), 0.0)["tracking"]["ok"]


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
