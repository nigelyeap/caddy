"""Time and memory benchmark for clean.py on big scan-like meshes.

Usage:
  uv run python perf.py                     # 100k, 500k, 1M, 2M faces with ./clean.py
  uv run python perf.py --sizes 100k,1M --clean /path/to/old/clean.py
Inputs are cached in out/perf/. Each run is its own process so peak memory is per run.
"""
import argparse
import importlib.util
import json
import resource
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).parent
CACHE = HERE / "out" / "perf"
SIZES = {"100k": 100_000, "500k": 500_000, "1M": 1_000_000, "2M": 2_000_000}


def make_input(n_faces):
    """A noisy toy scan with holes and floaters, about n_faces triangles, in mm."""
    path = CACHE / f"toy_{n_faces}.ply"
    if path.exists():
        return path
    from clean import from_manifold
    from run_bench import roughen, toy
    gt_m = toy()
    # Faces scale with 1 / edge^2. Calibrate on a coarse refine, then refine once more.
    edge = 2.0 * (gt_m.refine_to_length(2.0).num_tri() / n_faces) ** 0.5
    edge *= (gt_m.refine_to_length(edge).num_tri() / n_faces) ** 0.5
    gt = from_manifold(gt_m.refine_to_length(edge))
    gt.apply_translation(-gt.bounds[0])
    CACHE.mkdir(parents=True, exist_ok=True)
    roughen(gt, seed=7, heavy=False).export(path)
    return path


def run_one(clean_path, src):
    """Child process: load, clean, print one JSON line."""
    spec = importlib.util.spec_from_file_location("clean_under_test", clean_path)
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(Path(clean_path).parent))
    spec.loader.exec_module(mod)
    t0 = time.perf_counter()
    mesh = mod.load(src)
    t1 = time.perf_counter()
    stages = []
    kw = {}
    if "progress" in mod.clean.__code__.co_varnames:
        last = [t1, "start"]

        def progress(frac, msg):  # time since the last message belongs to the last message's stage
            now = time.perf_counter()
            stages.append((last[1], round(now - last[0], 2)))
            last[:] = [now, msg]
        kw["progress"] = progress
    out, log = mod.clean(mesh, 100.0, **kw)
    t2 = time.perf_counter()
    print("\n".join(log), file=sys.stderr)
    print(json.dumps({"faces_in": len(mesh.faces), "faces_out": len(out.faces), "load_s": round(t1 - t0, 2),
                      "clean_s": round(t2 - t1, 2), "watertight": bool(out.is_watertight),
                      "peak_mb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 2**20),  # bytes on macOS
                      "stages": stages}))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sizes", default="100k,500k,1M,2M")
    ap.add_argument("--clean", default=str(HERE / "clean.py"))
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--log", action="store_true", help="print the clean log after each run")
    a = ap.parse_args()
    print(f"clean module: {a.clean}")
    for s in a.sizes.split(","):
        src = make_input(SIZES[s])
        try:
            r = subprocess.run([sys.executable, __file__, "_one", a.clean, str(src)],
                               capture_output=True, text=True, timeout=a.timeout, cwd=HERE)
            res = json.loads(r.stdout.strip().splitlines()[-1]) if r.returncode == 0 else {"error": r.stderr[-300:]}
            if a.log:
                print(r.stderr)
        except subprocess.TimeoutExpired:
            res = {"error": f"timeout after {a.timeout} s"}
        print(f"{s:>5}: {json.dumps(res)}", flush=True)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "_one":
        run_one(sys.argv[2], sys.argv[3])
    else:
        main()
