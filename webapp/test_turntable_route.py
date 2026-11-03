"""Turntable .txt/.csv routing and kid messages. No server needed.
Run: uv run --project webapp python webapp/test_turntable_route.py"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

os.environ.pop("CAD_KEY_STDIN", None)
sys.path.insert(0, str(Path(__file__).parent))
import app  # noqa: E402
import processing  # noqa: E402

d = Path(tempfile.mkdtemp())


def scan_error(path):
    """Run the scan step on a file. Return the kid message, or None if it worked."""
    try:
        processing.clean_scan(str(path), str(d / "out.stl"))
        return None
    except Exception as e:
        return app._friendly_scan(e)[0]


# A real scan from the importer's own sample maker comes out as a printable STL, not the sample cup.
good = d / "cyl.txt"
subprocess.run(["uv", "run", "--project", str(processing.BENCH), "python", str(processing.BENCH / "turntable.py"),
                "--make-sample", "cylinder", str(good)], check=True)
assert scan_error(good) is None
tris = processing._read_stl(d / "out.stl")
assert len(tris) > 100 and abs(tris[..., 2].min()) < 0.01, (len(tris), tris[..., 2].min())
assert (tris[..., 2].max() - tris[..., 2].min()) > 1, "should be mm, not cm"
assert len(tris) != len(processing._cup()), "got the sample cup"

# The same file as .csv takes the same route.
csv = d / "cyl.csv"
csv.write_bytes(good.read_bytes())
assert scan_error(csv) is None

# Bad files give the matching kid message.
(d / "empty.txt").write_text("")
(d / "junk.csv").write_text("hello\nthis is not a scan\n")
for name in ("empty.txt", "junk.csv"):
    msg = scan_error(d / name)
    assert msg == app.SCAN_HINTS["no readable points"], (name, msg)

# Each importer phrase maps to its message. Anything else gets the plain fallback.
for key, msg in app.SCAN_HINTS.items():
    assert app._friendly_scan(RuntimeError(f"turntable: {key} (detail)"))[0] == msg
    assert "—" not in msg and ";" not in msg, msg
assert app._friendly_scan(RuntimeError("boom"))[0] == "The scan could not be turned into a shape."

# Only videos fall back to the sample cup.
assert {".txt", ".csv"} <= processing.TURNTABLE_EXT and not processing.TURNTABLE_EXT & processing.MESH_EXT
print("ok")
