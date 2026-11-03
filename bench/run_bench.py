"""Bench test: synthetic scans -> clean -> scripted edit -> printable STL.

Usage: uv run python run_bench.py
Writes synthetic/ (inputs and ground truth), out/ (cleaned and edited STLs, bench.log) and REPORT.md.
Real scans in scans/ are picked up too. Put the real longest side in the name, e.g. dino__120mm.ply.
"""
import datetime
import json
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import manifold3d as m3d
import numpy as np
import trimesh

from clean import check, clean, from_manifold, load
from edit import MODEL, edit, seat
from edit_cases import CASES  # edit instructions, accepted reply kinds, canned replies, shape checks

HERE = Path(__file__).parent
SYN, OUT, SCANS = HERE / "synthetic", HERE / "out", HERE / "scans"
DIM_TOL = 0.02  # max allowed error per bbox axis vs ground truth
EDIT_OBJECTS = ("toy_light", "mug_light", "block_light")  # edits run on these only, to keep live cost down


# ---------- synthetic ground truth shapes (mm) ----------

def toy():
    s = m3d.Manifold.sphere
    body = s(20, 64).scale((1, 0.85, 1.2)).translate((0, 0, 24))
    head = s(14, 64).translate((0, 0, 58))
    ears = s(5.5, 32).translate((-10, 0, 70)) + s(5.5, 32).translate((10, 0, 70))
    feet = s(7, 32).scale((1, 1.4, 0.6)).translate((-9, -4, 4)) + s(7, 32).scale((1, 1.4, 0.6)).translate((9, -4, 4))
    arms = s(6, 32).scale((1.8, 1, 1)).translate((-20, 0, 30)) + s(6, 32).scale((1.8, 1, 1)).translate((20, 0, 30))
    return body + head + ears + feet + arms


def mug():
    c = m3d.Manifold.cylinder
    cavity = c(90, 36, circular_segments=96).translate((0, 0, 6))
    handle = m3d.Manifold.revolve(m3d.CrossSection.circle(4.5, 32).translate((18, 0)), 96)
    handle = handle.rotate((90, 0, 0)).translate((40, 0, 48))
    return c(90, 40, circular_segments=96) + handle - cavity


def block():
    c = m3d.Manifold.cube
    hole = m3d.Manifold.cylinder(20, 4, circular_segments=48).translate((15, 20, -5))
    return c((60, 40, 10)) + c((15, 40, 35)).translate((45, 0, 0)) - hole


def roughen(gt, seed, heavy):
    """Fake the defects a cheap handheld scan has."""
    rng = np.random.default_rng(seed)
    m = gt.copy()
    size = m.extents.max()
    m.vertices += rng.normal(0, 0.003 * size if heavy else 0.0015 * size, m.vertices.shape)  # noise
    keep = np.ones(len(m.faces), bool)
    for f in rng.choice(len(m.faces), 5 if heavy else 2, replace=False):  # holes
        keep &= np.linalg.norm(m.triangles_center - m.triangles_center[f], axis=1) > (6 if heavy else 3)
    if heavy:  # missing bottom: the scanner never saw the underside
        keep &= m.triangles_center[:, 2] > m.bounds[0, 2] + 1.0
    m.update_faces(keep)
    m.remove_unreferenced_vertices()
    parts = [m]
    for _ in range(8 if heavy else 3):  # floaters: dust, table, fingers
        d = rng.normal(size=3)
        p = m.bounds.mean(0) + d / np.linalg.norm(d) * (0.6 * size + rng.uniform(5, 20))
        parts.append(trimesh.creation.icosphere(1, rng.uniform(1, 4)).apply_translation(p))
    m = trimesh.util.concatenate(parts)
    if heavy:  # non-manifold fins: a third face hanging off existing edges
        edges = m.edges_unique[rng.choice(len(m.edges_unique), 15, replace=False)]
        tip = m.vertices[edges].mean(1) + rng.normal(0, 2, (15, 3))
        n = len(m.vertices)
        m = trimesh.Trimesh(np.vstack([m.vertices, tip]),
                            np.vstack([m.faces, np.column_stack([edges, n + np.arange(15)])]), process=False)
        m.vertices *= 0.001  # wrong units: phone scanner apps export metres
    return m


def build_synthetic():
    SYN.mkdir(exist_ok=True)
    cases = []
    for i, (name, fn) in enumerate([("toy", toy), ("mug", mug), ("block", block)]):
        gt = from_manifold(fn().refine_to_length(2.0))  # dense like a scan
        gt.apply_translation(-gt.bounds[0])
        gt.export(SYN / f"{name}_gt.stl")
        for heavy, ext in ((False, "obj"), (True, "ply")):
            tag = f"{name}_{'heavy' if heavy else 'light'}"
            roughen(gt, seed=i * 10 + heavy, heavy=heavy).export(SYN / f"{tag}.{ext}")
            cases.append({"name": tag, "path": SYN / f"{tag}.{ext}", "gt": gt,
                          "longest_mm": float(gt.extents.max())})
    for p in sorted(SCANS.glob("*")):
        if p.suffix.lower() in (".ply", ".obj", ".stl"):
            mm = re.search(r"__(\d+(?:\.\d+)?)mm", p.stem)
            cases.append({"name": f"scan:{p.stem}", "path": p, "gt": None,
                          "longest_mm": float(mm.group(1)) if mm else None})
    return cases


# ---------- bench ----------

def run_case(case, logf):
    row = {"name": case["name"]}
    t = time.time()
    try:
        raw = load(case["path"])
        row["raw"] = {"faces": len(raw.faces), "parts": len(raw.split(only_watertight=False)),
                      "watertight": bool(raw.is_watertight), "extent_max": round(float(raw.extents.max()), 4)}
        mesh, log = clean(raw, case["longest_mm"])
    except Exception as e:
        row["clean_error"] = f"{type(e).__name__}: {e}"
        print(f"[{case['name']}] clean failed: {row['clean_error']}", file=logf)
        return row, None
    row["clean_s"] = round(time.time() - t, 1)
    row.update(check(mesh))
    if case["gt"] is not None:
        gt = case["gt"]
        row["dim_err"] = float(np.max(np.abs(mesh.extents - gt.extents) / gt.extents))
        row["vol_err"] = float(abs(mesh.volume - gt.volume) / gt.volume)
    row["pass"] = (row["watertight"] and row["manifold"] and row["volume_mm3"] > 0
                   and row["components"] == 1 and row.get("dim_err", 0) <= DIM_TOL)
    safe = case["name"].replace(":", "_")
    mesh.export(OUT / f"{safe}_clean.stl")
    print(f"[{case['name']}]\n  " + "\n  ".join(log), file=logf)
    return row, mesh


def run_edit(name, mesh, idx, model):
    instruction, kinds, _, ok = CASES[idx]
    r = edit(mesh, instruction, model=model)
    res = {"object": name, "instruction": instruction, "source": r["source"], "kind": r["kind"],
           "message": r["message"], "error": r["error"], "script": r["script"], "attempts": r["attempts"],
           "usage": r["usage"], "seconds": r["seconds"], "cost_usd": r["cost_usd"], "checks": r["checks"]}
    res["printable"] = r["kind"] != "edit" or r["checks"]["printable"]
    res["did_it"] = r["kind"] in kinds and (r["kind"] != "edit" or bool(ok(seat(mesh), r["result"])))
    if r["result"] is not None:
        r["result"].export(OUT / f"{name.replace(':', '_')}_edit{idx + 1}.stl")
    return res


def yn(b):
    return "yes" if b else "**NO**"


def write_report(rows, edits, source, elapsed, model=MODEL, hard=()):
    lines = [
        "# Bench test: scan to printable STL",
        "",
        f"Run {datetime.datetime.now():%Y-%m-%d %H:%M}, {elapsed:.0f} s total. Regenerate with `uv run python run_bench.py`.",
        "",
    ]
    if source == "canned":
        lines += ["> **LLM EXERCISED: NO.** ANTHROPIC_API_KEY was not set, so every edit used a hand-written",
                  "> canned reply from `edit_cases.py`. The edit numbers below test the parser, sandbox, helpers and",
                  "> checks. They say nothing about how often Claude writes a working script.", ""]
    else:
        lines += [f"> **LLM EXERCISED: YES.** Edit scripts were written live by `{model}` in this run.", ""]
    lines += ["## Clean step", "",
              f"Pass means watertight, manifold, positive volume, one part, and every bbox axis within {DIM_TOL:.0%} of ground truth.", "",
              "| object | raw faces | raw parts | raw longest | watertight | manifold | volume mm3 | parts | dim err | vol err | faces out | pass |",
              "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if "clean_error" in r:
            lines.append(f"| {r['name']} | | | | | | | | | | | **FAIL**: {r['clean_error']} |")
            continue
        de = f"{r['dim_err']:.2%}" if "dim_err" in r else "n/a"
        ve = f"{r['vol_err']:.2%}" if "vol_err" in r else "n/a"
        lines.append(f"| {r['name']} | {r['raw']['faces']} | {r['raw']['parts']} | {r['raw']['extent_max']} | "
                     f"{yn(r['watertight'])} | {yn(r['manifold'])} | {r['volume_mm3']:.0f} | {r['components']} | "
                     f"{de} | {ve} | {r['faces']} | {yn(r['pass'])} |")
    lines += ["", "Raw longest is in file units. The heavy files are in metres on purpose.", ""]
    if hard:
        lines += ["### Real-scan failure modes (synth_hard.py, clean only)", "",
                  "Pass means printable, the right part count, and dims within 2% (5% when no size is given).", "",
                  "| case | result | dim err | vol err | quality | s | notes |", "|---|---|---|---|---|---|---|"]
        for h in hard:
            note = "; ".join(h["fails"]) + (f" (known limit: {h['known']})" if h["known"] else "")
            lines.append(f"| {h['name']} | {h['verdict']} | {h['dim_err']:.2%} | {h['vol_err']:.2%} | "
                         f"{h['quality']} | {h['seconds']} | {note} |")
        lines.append("")
    lines += ["## Edit step", "",
              f"Objects: {', '.join(EDIT_OBJECTS)}. Did it = the reply kind was one we accept (edit, question or polite no)",
              "and, for an edit, the shape changed the way the instruction asked (checked from size, volume and hole count).",
              f"Printable = watertight, manifold, positive volume, one part, fits a 250 mm bed. Got = reply kinds seen.",
              "Tokens are input + cache read / output, averaged per object. Cost uses the prices in `edit.py`.", "",
              "| # | instruction | want | got | did it | tries | tokens in/out | s | $ |",
              "|---|---|---|---|---|---|---|---|---|"]
    for i, (ins, kinds, _, _) in enumerate(CASES):
        es = [e for e in edits if e["instruction"] == ins]
        if not es:
            continue
        n = len(es)
        tin = sum(e["usage"]["input"] + e["usage"]["cache_read"] + e["usage"]["cache_write"] for e in es) / n
        tout = sum(e["usage"]["output"] for e in es) / n
        got = "/".join(sorted({e["kind"] for e in es}))
        lines.append(f"| {i + 1} | {ins.replace('|', '/')} | {'/'.join(sorted(kinds))} | {got} | "
                     f"{sum(e['did_it'] and e['printable'] for e in es)}/{n} | {sum(e['attempts'] for e in es) / n:.1f} | "
                     f"{tin:.0f}/{tout:.0f} | {sum(e['seconds'] for e in es) / n:.1f} | {sum(e['cost_usd'] for e in es) / n:.4f} |")
    fails = [e for e in edits if not (e["did_it"] and e["printable"])]
    total_cost = sum(e["cost_usd"] for e in edits)
    secs = sorted(e["seconds"] for e in edits) or [0]
    lines += ["", f"Overall: {sum(e['did_it'] and e['printable'] for e in edits)}/{len(edits)} edits did the job and stayed printable.",
              f"Total edit cost ${total_cost:.3f}, median {secs[len(secs) // 2]:.1f} s per edit, slowest {secs[-1]:.1f} s.", ""]
    if fails:
        lines += ["Failures:", ""]
        for e in fails:
            why = e["error"] or (f"checks {json.dumps(e.get('checks'))}" if not e["printable"] else
                                 f"got {e['kind']}: {e['message']}" if e["kind"] != "edit" else "shape check failed")
            lines.append(f"- {e['object']} / {e['instruction']}: {why}")
        lines.append("")
    lines += ["Scripts, repair logs and errors are in `out/bench.log`. Meshes are in `out/`.", ""]
    report = HERE / "REPORT.md"
    keep = ""
    if report.exists():  # the hand-written verdict survives reruns
        old = report.read_text()
        keep = old[old.index("## Verdict"):] if "## Verdict" in old else ""
    report.write_text("\n".join(lines) + "\n" + (keep or "## Verdict\n\nNot written yet.\n"))


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=MODEL, help="edit model, e.g. claude-haiku-5-5 for the cheap run")
    model = ap.parse_args().model
    OUT.mkdir(exist_ok=True)
    t0 = time.time()
    cases = build_synthetic()
    with open(OUT / "bench.log", "w") as logf:
        rows, meshes = [], {}
        for c in cases:
            row, mesh = run_case(c, logf)
            rows.append(row)
            if mesh is not None:
                meshes[c["name"]] = mesh
            print(f"clean {c['name']:<14} {'PASS' if row.get('pass') else 'FAIL'} {row.get('dim_err', '')}")
        from synth_hard import run_hard  # real-scan failure modes, clean step only
        hard = run_hard(logf)
        for h in hard:
            print(f"clean {h['name']:<24} {h['verdict']} {'; '.join(h['fails'])}")
        jobs = [(n, m, i, model) for n, m in meshes.items() if n in EDIT_OBJECTS for i in range(len(CASES))]
        with ThreadPoolExecutor(4) as ex:
            edits = list(ex.map(lambda j: run_edit(*j), jobs))
        for e in edits:
            print(f"\n--- {e['object']} / {e['instruction']} [{e['source']}] kind={e['kind']} did_it={e['did_it']} "
                  f"printable={e['printable']} attempts={e['attempts']} s={e['seconds']} usage={e['usage']} "
                  f"error={e['error']} message={e['message']}\n{e['script']}", file=logf)
    source = "claude" if any(e["source"] == "claude" for e in edits) else "canned"
    for i, (ins, *_) in enumerate(CASES):
        es = [e for e in edits if e["instruction"] == ins]
        print(f"edit {i + 1:>2} {ins[:50]:<50} ok {sum(e['did_it'] and e['printable'] for e in es)}/{len(es)} "
              f"kinds {sorted({e['kind'] for e in es})}")
    print(f"edit cost ${sum(e['cost_usd'] for e in edits):.3f}  model {model}")
    print("LLM EXERCISED: " + ("YES" if source == "claude" else
                               "NO (no ANTHROPIC_API_KEY, canned replies from edit_cases.py)"))
    write_report(rows, edits, source, time.time() - t0, model, hard)
    print(f"wrote {HERE / 'REPORT.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
