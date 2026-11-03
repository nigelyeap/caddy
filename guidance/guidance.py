"""Scan guidance engine for CAD Training.

Feed it about one frame per second. It checks blur, lighting, tracking,
scan speed and how far around the object the student has walked.

Calibration note: every threshold below was tuned on synthetic frames
and four short public phone clips (see QUALITY_NOTES.md). Real cameras
differ in noise, sharpening, exposure and field of view. Run calibrate.py
on a few good and bad videos and move these knobs until the warnings
match what you see.
"""

import math

import cv2
import numpy as np

# Frames are shrunk to this width before any check, so scores do not
# depend on camera resolution.
PROC_WIDTH = 640

# Blur: variance of the Laplacian. Below BLUR_MIN the frame counts as
# blurry. A plain object on a plain table scores low even when sharp, so a
# frame is only called blurry if it is also well below this session's
# recent sharp frames (BLUR_REL), or below the hard floor BLUR_FLOOR.
BLUR_MIN = 60.0
BLUR_REL = 0.45
BLUR_FLOOR = 12.0

# Light: mean grey level 0..255 and share of clipped pixels in percent.
DARK_MEAN = 50.0
BRIGHT_MEAN = 205.0
# A white object on a white table is bright but fine. Too bright also
# needs this share of blown out pixels.
BRIGHT_CLIP_PCT = 10.0
CLIP_LEVEL = 250
GLARE_PCT = 4.0

# Tracking: ORB features matched to the last tracked frame with a ratio
# test, then checked against the camera motion model. Tracking is ok when
# at least MIN_MATCHES matches agree with the motion. match_ratio is good
# matches over keypoints, kept for the log and for calibration.
ORB_FEATURES = 1000
# Plain or shiny objects give few corners. Below this many keypoints the
# detector runs again with a lower contrast threshold.
ORB_RETRY_BELOW = 300
LOWE_RATIO = 0.75
MATCH_RATIO_MIN = 0.06
MIN_MATCHES = 15
MIN_INLIER_FRAC = 0.6  # share of matches that must agree on one motion
MAX_TILT_DEG = 75  # steepest look-down we accept. Objectron phones looked down 20 to 77 degrees.
# After this many failed frames in a row, give up on the old reference
# frame and start tracking again from the current one.
RELOCK_FRAMES = 4

# Motion: assumed focal length as a share of the LONG side of the image.
# A phone main camera sits near 0.83 in portrait and landscape (measured
# 0.80 to 0.84 on four iPhone clips). Webcams sit between 0.6 and 0.8.
# A wrong value scales every angle by roughly the same factor. The engine
# corrects it itself once the student closes a loop.
FOCAL_FRAC = 0.8
# Below this median pixel shift the camera is treated as still.
MIN_PARALLAX_PX = 1.5
# Matches that miss the motion model by more than this many pixels are outliers.
INLIER_PX = 2.0
SPEED_MAX_DEG_S = 20.0

# Panning: the camera turned at least PAN_MIN_DEG but the scene shows
# almost no parallax, so the student turned on the spot instead of walking.
PAN_MIN_DEG = 4.0
PAN_PARALLAX = 0.08

# Keyframes for relocking and loop closure, one every this many degrees.
KEYFRAME_DEG = 20.0

# Depth checks, only used when a depth map is supplied. Metres.
NEAR_M = 0.20
FAR_M = 1.5

# Elevation bands for the upper and lower rings, degrees above the
# object's centre. Only measured when a pose is supplied.
RING_EDGES = (15.0, 45.0)

# Warnings: show after this many bad frames in a row, then keep showing
# until the problem has been gone for this many seconds.
WARN_ON_FRAMES = 2
WARN_HOLD_S = 3.0

# Most important first. The app shows the first warning only, so fix the
# cause (light, blur) before the effect (lost tracking).
# Written for 8 to 14 year olds: say what is wrong, then what to do.
MESSAGES = {
    "dark": "Too dark. Turn on a light.",
    "bright": "Too bright. Turn away from the window or lamp.",
    "blur": "Blurry picture. Hold the camera steady.",
    "tracking": "Lost the object. Point the camera at it and step back to where you were.",
    "speed": "Too fast. Walk around more slowly.",
    "panning": "Walk around the object. Do not just turn the camera.",
    "too_close": "Too close. Take a step back.",
    "too_far": "Too far away. Move closer to the object.",
    "glare": "Shiny spot on the object. Tilt the camera a little.",
}

_UP = np.array([0.0, -1.0, 0.0])  # world up in OpenCV camera axes (y points down)


def _gray(frame_bgr):
    if not isinstance(frame_bgr, np.ndarray) or frame_bgr.dtype != np.uint8:
        raise ValueError("frame_bgr must be a uint8 numpy array")
    if frame_bgr.ndim == 3 and frame_bgr.shape[2] == 3:
        g = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
    elif frame_bgr.ndim == 2:
        g = frame_bgr
    else:
        raise ValueError("frame_bgr must be HxWx3 BGR or HxW grey")
    h, w = g.shape
    if w != PROC_WIDTH:
        g = cv2.resize(g, (PROC_WIDTH, round(h * PROC_WIDTH / w)), interpolation=cv2.INTER_AREA)
    return g


# ---------- Two-view motion ----------

def _skew(t):
    return np.array([[0, -t[2], t[1]], [t[2], 0, -t[0]], [-t[1], t[0], 0]])


def _rot(w):
    return cv2.Rodrigues(np.asarray(w, dtype=float).reshape(3, 1))[0]


def _sampson(R, t, x0, x1):
    """Signed Sampson distance of each match, in normalised image units."""
    E = _skew(t) @ R
    Ex0 = x0 @ E.T
    Etx1 = x1 @ E
    num = np.einsum("ni,ni->n", x1, Ex0)
    den = Ex0[:, 0] ** 2 + Ex0[:, 1] ** 2 + Etx1[:, 0] ** 2 + Etx1[:, 1] ** 2
    return num / np.sqrt(np.maximum(den, 1e-18))


def _seeds(x0, x1, v, s, keep=3):
    """Starting motions for the robust fit: turns about the vertical v from -90 to 90 degrees.

    For each turn angle the best translation direction has a closed form
    (the epipolar constraint is linear in t once R is fixed), so off-centre
    framing and sideways drift are allowed. The local minima of the cost
    curve become seeds. A narrow lens mixes up turning with sliding
    sideways, which gives two minima, so more than one seed is kept. The
    grid uses a wide robust scale so a 1 degree step does not skip the true
    minimum.
    """
    ths = np.radians(np.r_[np.arange(-90, 0, 1.0), np.arange(1, 91, 1.0)])
    Rs = np.array([_rot(v * th) for th in ths])
    Rx0 = np.einsum("kij,nj->kni", Rs, x0)
    M = np.cross(Rx0, x1[None])  # t . (R x0 x x1) = 0 for every match
    w = np.ones(M.shape[:2])
    for _ in range(2):  # reweight once to shrug off outliers
        A = np.einsum("kn,kni,knj->kij", w, M, M)
        t = np.linalg.eigh(A)[1][:, :, 0]
        alg = np.einsum("kni,ki->kn", M, t)
        w = 1.0 / (1.0 + (alg / (6 * s)) ** 2)
    costs = np.array([np.log1p((_sampson(R, tt, x0, x1) / (6 * s)) ** 2).sum() for R, tt in zip(Rs, t)])
    mins = [i for i in range(len(costs)) if costs[i] <= costs[max(i - 1, 0)] and costs[i] <= costs[min(i + 1, len(costs) - 1)]]
    mins.sort(key=lambda i: costs[i])
    return [(Rs[i], t[i]) for i in mins[:keep]]


def _cheirality(R, t, x0, x1):
    """Share of matches that land in front of both cameras, with t's sign chosen to suit."""
    a, b = x1, x0 @ R.T
    a11, a12, a22 = (a * a).sum(1), -(a * b).sum(1), (b * b).sum(1)
    r1, r2 = a @ t, -(b @ t)
    det = a11 * a22 - a12 ** 2
    z1 = (a22 * r1 - a12 * r2) / det
    z0 = (a11 * r2 - a12 * r1) / det
    return max(((z0 > 0) & (z1 > 0)).mean(), ((z0 < 0) & (z1 < 0)).mean())


def _refine(R, t, x0, x1, s, iters=10):
    """Robust (Cauchy) Gauss-Newton on rotation and translation direction."""
    for _ in range(iters):
        b1 = np.cross(t, [1.0, 0, 0] if abs(t[0]) < 0.9 else [0, 1.0, 0])
        b1 /= np.linalg.norm(b1)
        b2 = np.cross(t, b1)

        def model(p):
            tn = t + p[3] * b1 + p[4] * b2
            return R @ _rot(p[:3]), tn / np.linalg.norm(tn)

        r = _sampson(R, t, x0, x1)
        w = 1.0 / (1.0 + (r / s) ** 2)
        J = np.empty((len(r), 5))
        for k in range(5):
            dp = np.zeros(5)
            dp[k] = 1e-6
            J[:, k] = (_sampson(*model(dp), x0, x1) - r) / 1e-6
        A = J.T @ (J * w[:, None])
        step = np.linalg.solve(A + 1e-6 * np.trace(A) * np.eye(5) + 1e-12 * np.eye(5), J.T @ (w * r))
        R, t = model(-step)
        if np.abs(step).max() < 1e-7:
            break
    r = _sampson(R, t, x0, x1)
    return R, t, float(np.log1p((r / s) ** 2).sum()), np.abs(r) < 2 * s


def _twist(R, v):
    """Signed rotation angle of R about unit axis v, in degrees (swing-twist split)."""
    w = cv2.Rodrigues(R)[0].ravel()
    ang = np.linalg.norm(w)
    if ang < 1e-12:
        return 0.0
    q_xyz = math.sin(ang / 2) * w / ang
    return math.degrees(2 * math.atan2(float(q_xyz @ v), math.cos(ang / 2)))


def _motion(p0, p1, f, c, v):
    """Camera motion between two views from matched pixels.

    Returns (yaw_deg about v, inlier mask, rotation axis, parallax ratio).
    Fits a general rotation plus translation direction, started from both
    the orbit guess and a RANSAC essential matrix, and keeps the better
    robust fit. The yaw is the part of the rotation about the vertical, so
    hand roll, tilting and up or down steps drop out.
    """
    x0 = np.c_[(p0 - c) / f, np.ones(len(p0))]
    x1 = np.c_[(p1 - c) / f, np.ones(len(p1))]
    s = INLIER_PX / 2 / f
    cands = _seeds(x0, x1, v, s)
    E, _ = cv2.findEssentialMat(p0, p1, focal=f, pp=tuple(c), method=cv2.RANSAC, prob=0.999, threshold=INLIER_PX)
    if E is not None and E.shape == (3, 3):
        _, Re, te, _ = cv2.recoverPose(E, p0, p1, focal=f, pp=tuple(c))
        cands.append((Re, te.ravel()))
    fits = []
    for R, t in cands:
        R, t, cost, inl = _refine(R, t, x0, x1, s)
        # A fit that puts many points behind the camera is a mirror solution.
        if inl.sum():
            cost += 3.0 * inl.sum() * (1.0 - _cheirality(R, t, x0[inl], x1[inl]))
        fits.append((cost, R, t, inl))
    _, R, t, inl = min(fits, key=lambda b: b[0])
    # Panning check: how far do inliers sit from a pure rotation of the camera?
    y = x0[inl] @ R.T
    y = y[:, :2] / y[:, 2:]
    ang = np.linalg.norm(cv2.Rodrigues(R)[0])
    parallax = float(np.median(np.linalg.norm(y - x1[inl, :2], axis=1)) / max(ang, 1e-6)) if inl.sum() else 1.0
    axis = cv2.Rodrigues(R)[0].ravel() / max(ang, 1e-12)
    return -_twist(R, v), inl, axis, ang, parallax


def _heading_from_pose(pose):
    # Pose is 4x4 camera-to-world, y up, camera looks along -z (ARKit style).
    fwd = -np.asarray(pose, dtype=float)[:3, 2]
    return math.degrees(math.atan2(fwd[0], fwd[2]))


def _wrap(a):
    return (a + 180.0) % 360.0 - 180.0


class Session:
    def __init__(self, sectors: int = 12):
        self.sectors = sectors
        self._orb = cv2.ORB_create(ORB_FEATURES)
        self._orb_soft = cv2.ORB_create(ORB_FEATURES, fastThreshold=6, edgeThreshold=15)
        self._bf = cv2.BFMatcher(cv2.NORM_HAMMING)
        self.reset()

    def reset(self) -> None:
        self._ref = None  # (keypoints, descriptors, t) of the last tracked frame
        self._fails = 0
        self._angle = 0.0  # accumulated orbit angle in degrees, signed, positive = walking to your right
        self._focal_scale = 1.0  # learned at loop closure
        self._v = _UP.copy()  # vertical axis in camera coordinates, learned from the rotation axes
        self._kfs = []  # keyframes: (keypoints, descriptors, angle, frame index)
        self._segs = []  # covered stretches: [a0, a1, frame index, elevation band or None]
        self._loops = 0
        self._closed = set()  # keyframes already used for a loop closure
        self._gap_n = -1  # last frame where turning may have gone uncounted
        self._n = 0
        self._blur_hist = []
        self._last_pose = None  # (position, heading, t)
        self._ray_A = np.zeros((3, 3))  # least squares centre from the optical axes
        self._ray_b = np.zeros(3)
        self._depth_centres = []
        self._warn = {k: [0, -1e9, False] for k in MESSAGES}  # streak, last bad t, shown

    # ----- coverage -----

    def _mark(self, a0, a1, band=None):
        self._segs.append([a0, a1, self._n, band])

    def _bins(self, band=None):
        bins = np.zeros(360, dtype=bool)
        for a0, a1, _, b in self._segs:
            if band is not None and b != band:
                continue
            lo, hi = sorted((a0, a1))
            idx = np.arange(math.floor(lo), math.floor(hi) + 1) % 360
            bins[idx] = True
        return bins

    def _coverage(self, rings):
        idx = np.arange(360) * self.sectors // 360

        def per(bins):
            return [float(bins[idx == s].mean()) for s in range(self.sectors)]

        bins = self._bins()
        out = {"sectors": per(bins), "pct": float(bins.mean() * 100)}
        # Upper and lower rings need a real pose to know the camera height.
        out["rings"] = {name: per(self._bins(name)) for name in ("low", "mid", "high")} if rings else None
        return out

    # ----- tracking -----

    def _detect(self, gray):
        # Shiny highlights move with the camera, not with the part. Keep
        # features away from blown out pixels so they cannot fake a match.
        mask = cv2.erode((gray < CLIP_LEVEL - 10).astype(np.uint8) * 255, np.ones((9, 9), np.uint8))
        kp, des = self._orb.detectAndCompute(gray, mask)
        if len(kp) < ORB_RETRY_BELOW:
            # Low texture: equalise contrast and lower the corner threshold.
            eq = cv2.createCLAHE(2.0, (8, 8)).apply(gray)
            kp, des = self._orb_soft.detectAndCompute(eq, mask)
        return kp, des

    def _match(self, ref, kp, des):
        kp0, des0 = ref[0], ref[1]
        good = []
        if des is not None and des0 is not None and len(des) >= 2 and len(des0) >= 2:
            for pair in self._bf.knnMatch(des0, des, k=2):
                if len(pair) == 2 and pair[0].distance < LOWE_RATIO * pair[1].distance:
                    good.append(pair[0])
        n_kp = min(len(kp), len(kp0))
        ratio = len(good) / n_kp if n_kp else 0.0
        p0 = np.float32([kp0[m.queryIdx].pt for m in good]).reshape(-1, 2)
        p1 = np.float32([kp[m.trainIdx].pt for m in good]).reshape(-1, 2)
        return ratio, p0, p1

    def _solve(self, p0, p1, shape, learn=True):
        """Yaw between two views, or None if the matches do not agree on one motion."""
        if len(p0) < MIN_MATCHES:
            return None
        h, w = shape
        if np.median(np.linalg.norm(p1 - p0, axis=1)) < MIN_PARALLAX_PX:
            return 0.0, False, len(p0)
        f = FOCAL_FRAC * max(w, h) * self._focal_scale
        yaw, inl, axis, ang, parallax = _motion(p0, p1, f, np.array([w / 2, h / 2]), self._v)
        if inl.sum() < max(MIN_MATCHES, MIN_INLIER_FRAC * len(p0)):
            # Few matches agree. On a blank scene that is noise, so call it lost.
            return None
        panning = math.degrees(ang) >= PAN_MIN_DEG and parallax < PAN_PARALLAX
        if learn and math.degrees(ang) > 3 and not panning:
            # The orbit turns about the vertical. Average the rotation axes to learn
            # how the camera is tilted, so looking down at the part does not skew yaw.
            a = axis if axis @ self._v > 0 else -axis
            if a @ _UP > math.cos(math.radians(MAX_TILT_DEG)):
                self._v = self._v + 0.2 * (a - self._v)
                self._v /= np.linalg.norm(self._v)
        return yaw, panning, int(inl.sum())

    def _track(self, gray, t):
        """Return (match_ratio, ok, yaw_deg or None, dt, panning) against the reference frame."""
        kp, des = self._detect(gray)
        if self._ref is None:
            self._ref = (kp, des, t)
            self._kfs = [(kp, des, self._angle, self._n)]
            return 1.0, True, 0.0, 0.0, False
        t0 = self._ref[2]
        ratio, p0, p1 = self._match(self._ref, kp, des)
        sol = self._solve(p0, p1, gray.shape) if ratio >= MATCH_RATIO_MIN / 2 else None
        if sol is not None:
            self._fails = 0
            self._ref = (kp, des, t)
            return ratio, True, sol[0], t - t0, sol[1]
        # Lost. Try the keyframes nearest the current angle, so a turn made
        # while lost is counted once the student is back on known ground.
        for kkp, kdes, ka, _ in sorted(self._kfs, key=lambda k: abs(k[2] - self._angle))[:3]:
            r2, q0, q1 = self._match((kkp, kdes), kp, des)
            sol = self._solve(q0, q1, gray.shape, learn=False)
            if sol is not None:
                self._fails = 0
                self._ref = (kp, des, t)
                self._gap_n = self._n
                # Return the step that lands the angle where the keyframe says.
                return ratio, True, ka + sol[0] - self._angle, t - t0, False
        self._fails += 1
        if self._fails >= RELOCK_FRAMES:
            # ponytail: a turn made while lost on new ground is never counted.
            # Loop closure fixes it later if the student comes round again.
            self._ref, self._fails = (kp, des, t), 0
            self._gap_n = self._n
        return ratio, False, None, 0.0, False

    def _loop_closure(self, kp, des, shape):
        """When the student comes round to a keyframe from a lap ago, measure the true lap."""
        # A wrong focal length guess can make a full lap read anywhere from
        # about 250 to 480 degrees, so look for the start from 200 degrees on.
        old = [k for k in self._kfs if k[3] not in self._closed and abs(self._angle - k[2]) >= 200]
        cands = []
        for sc in (1.0, 0.75, 1.3):  # the focal length guess may be off either way
            if old:
                k = min(old, key=lambda k: abs(_wrap((self._angle - k[2]) * sc)))
                if k not in cands:
                    cands.append(k)
        for kkp, kdes, ka, kn in cands:
            since = self._angle - ka
            _, q0, q1 = self._match((kkp, kdes), kp, des)
            sol = self._solve(q0, q1, shape, learn=False)
            if sol is None:
                continue
            rel = sol[0]
            # A lap closes near where it started. Demand a strong match, so a
            # look-alike side of a plain or symmetric part does not fake it.
            if abs(rel) > 30 or sol[2] < 2 * MIN_MATCHES:
                continue
            true_since = round((since - rel) / 360) * 360 + rel
            scale = true_since / since
            if not 0.6 < scale < 1.6:
                return
            self._closed.add(kn)
            if self._gap_n >= kn:
                # Tracking was lost on the way round, so the lap reading is
                # short by an unknown turn. Fix the angle, keep the focal length.
                self._angle = ka + true_since
                self._loops += 1
                return
            if self._loops == 0:
                self._focal_scale /= scale  # angles scale with the focal length guess
            for seg in self._segs:  # stretch the coverage marked since that keyframe
                if seg[2] >= kn:
                    seg[0] = ka + (seg[0] - ka) * scale
                    seg[1] = ka + (seg[1] - ka) * scale
            self._kfs = [(a, b, ka + (c - ka) * scale if n >= kn else c, n) for a, b, c, n in self._kfs]
            self._angle = ka + true_since
            self._loops += 1
            return

    # ----- pose path (LiDAR probe or any device with real tracking) -----

    def _pose_step(self, pose, depth, t):
        """Orbit step, elevation band and distance from a 4x4 ARKit camera to world pose."""
        T = np.asarray(pose, dtype=float)
        pos, fwd = T[:3, 3], -T[:3, 2]
        heading = _heading_from_pose(T)
        dist = None
        if depth is not None:
            d = np.asarray(depth, dtype=float)
            if np.issubdtype(np.asarray(depth).dtype, np.integer):
                d = d / 1000.0  # millimetres
            h, w = d.shape[:2]
            win = d[int(h * 0.4):int(h * 0.6) + 1, int(w * 0.4):int(w * 0.6) + 1]
            win = win[np.isfinite(win) & (win > 0.05)]
            if win.size:
                dist = float(np.median(win))
                self._depth_centres.append(pos + fwd * dist)
                self._depth_centres = self._depth_centres[-60:]
        P = np.eye(3) - np.outer(fwd, fwd)
        self._ray_A += P
        self._ray_b += P @ pos
        centre = None
        if self._depth_centres:
            centre = np.median(np.array(self._depth_centres), axis=0)
        elif np.linalg.cond(self._ray_A) < 1e4:
            centre = np.linalg.solve(self._ray_A, self._ray_b)

        step, dt, elev, panning = 0.0, 0.0, None, False
        if self._last_pose is not None:
            ppos, phead, pt = self._last_pose
            dt = t - pt
            turn = -_wrap(heading - phead)
            step = turn
            if centre is not None:
                a0 = math.atan2(ppos[0] - centre[0], ppos[2] - centre[2])
                a1 = math.atan2(pos[0] - centre[0], pos[2] - centre[2])
                walk = _wrap(math.degrees(a1 - a0))
                step = walk
                panning = abs(turn) >= PAN_MIN_DEG and abs(walk) < 0.3 * abs(turn)
        if centre is not None:
            rel = pos - centre
            elev = math.degrees(math.atan2(rel[1], math.hypot(rel[0], rel[2])))
        self._last_pose = (pos, heading, t)
        return step, dt, elev, dist, panning

    # ----- main entry -----

    def update(self, frame_bgr, t, depth=None, pose=None) -> dict:
        gray = _gray(frame_bgr)
        self._n += 1

        blur = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        ref_blur = float(np.percentile(self._blur_hist, 75)) if len(self._blur_hist) >= 3 else None
        self._blur_hist = (self._blur_hist + [blur])[-15:]
        if blur < BLUR_FLOOR:
            blur_ok = False
        elif blur >= BLUR_MIN:
            blur_ok = True
        else:
            # Low score. Blurry only if this scene is usually sharper.
            blur_ok = ref_blur is not None and blur >= BLUR_REL * ref_blur

        mean = float(gray.mean())
        clipped = float((gray >= CLIP_LEVEL).mean() * 100)
        issue = None
        if mean < DARK_MEAN:
            issue = "dark"
        elif mean > BRIGHT_MEAN and clipped > BRIGHT_CLIP_PCT:
            issue = "bright"
        elif clipped > GLARE_PCT:
            issue = "glare"

        ratio, track_ok, yaw, dt, panning = self._track(gray, t)
        measured = yaw is not None

        elev, dist = None, None
        if pose is not None:
            # Real pose wins over the RGB estimate.
            yaw, dt, elev, dist, panning = self._pose_step(pose, depth, t)
            measured = True
        if panning:
            yaw = 0.0  # turning on the spot does not show a new side

        step = yaw if measured else 0.0
        speed = abs(step) / dt if dt > 0 else 0.0
        speed_ok = speed <= SPEED_MAX_DEG_S

        prev = self._angle
        self._angle += step
        if blur_ok and issue is None and measured and (track_ok or pose is not None):
            band = None
            if elev is not None:
                band = "low" if elev < RING_EDGES[0] else "mid" if elev < RING_EDGES[1] else "high"
            self._mark(prev, self._angle, band)
        if pose is None and track_ok and measured:
            kp, des = self._ref[0], self._ref[1]
            if self._kfs and len(self._kfs) < 200 and abs(self._angle - self._kfs[-1][2]) >= KEYFRAME_DEG:
                self._kfs.append((kp, des, self._angle, self._n))
            self._loop_closure(kp, des, gray.shape)

        bad = set()
        if not blur_ok:
            bad.add("blur")
        if issue:
            bad.add(issue)
        if not track_ok:
            bad.add("tracking")
        if not speed_ok:
            bad.add("speed")
        if panning:
            bad.add("panning")
        if dist is not None and dist < NEAR_M:
            bad.add("too_close")
        if dist is not None and dist > FAR_M:
            bad.add("too_far")
        warnings = []
        for key, st in self._warn.items():
            if key in bad:
                st[0] += 1
                st[1] = t
                if st[0] >= WARN_ON_FRAMES:
                    st[2] = True
            else:
                st[0] = 0
                if st[2] and t - st[1] >= WARN_HOLD_S:
                    st[2] = False
            if st[2]:
                warnings.append(MESSAGES[key])

        return {
            "blur": {"score": blur, "ok": bool(blur_ok)},
            "light": {"mean": mean, "clipped_pct": clipped, "ok": issue is None, "issue": issue},
            "tracking": {"match_ratio": float(ratio), "ok": bool(track_ok)},
            "speed": {"value": float(speed), "ok": bool(speed_ok)},
            "coverage": self._coverage(rings=pose is not None),
            "orbit": {
                "angle_deg": float(self._angle),
                "measured": bool(measured),
                "panning": bool(panning),
                "elevation_deg": None if elev is None else float(elev),
                "distance_m": dist,
                "focal_frac": float(FOCAL_FRAC * self._focal_scale),
                "loops_closed": self._loops,
            },
            "warnings": warnings,
            "t": float(t),
        }
