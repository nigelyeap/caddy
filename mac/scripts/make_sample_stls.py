#!/usr/bin/env python3
"""Writes sample STL files for the 3D viewer. Python stdlib only.

usage: make_sample_stls.py [out_dir]

Files: cup.stl, block.stl, sphere.stl, cube_ascii.stl, big_1m.stl (about 1M triangles, 50 MB),
broken_truncated.stl and broken_text.stl. Sizes are in mm with z up.
"""
import math
import os
import struct
import sys
import tempfile


def write_binary(path, tris):
    with open(path, "wb") as f:
        f.write(b"sample".ljust(80, b" "))
        f.write(struct.pack("<I", len(tris)))
        rec = struct.Struct("<12fH")
        for a, b, c in tris:
            f.write(rec.pack(0, 0, 0, *a, *b, *c, 0))


def write_ascii(path, tris):
    with open(path, "w") as f:
        f.write("solid cube\n")
        for tri in tris:
            f.write("  facet normal 0 0 0\n    outer loop\n")
            for v in tri:
                f.write("      vertex %g %g %g\n" % v)
            f.write("    endloop\n  endfacet\n")
        f.write("endsolid cube\n")


def box(sx, sy, sz):
    p = [((i & 1) * sx, ((i >> 1) & 1) * sy, ((i >> 2) & 1) * sz) for i in range(8)]
    quads = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
    out = []
    for a, b, c, d in quads:
        out += [(p[a], p[b], p[c]), (p[a], p[c], p[d])]
    return out


def sphere(r, rings, segs):
    def pt(i, j):
        if i == 0:
            return (0.0, 0.0, 2 * r)
        if i == rings:
            return (0.0, 0.0, 0.0)
        th, ph = i / rings * math.pi, (j % segs) / segs * 2 * math.pi
        return (r * math.sin(th) * math.cos(ph), r * math.sin(th) * math.sin(ph), r + r * math.cos(th))

    out = []
    for i in range(rings):
        for j in range(segs):
            a, b, c, d = pt(i, j), pt(i + 1, j), pt(i + 1, j + 1), pt(i, j + 1)
            if i != 0:
                out.append((a, b, d))
            if i != rings - 1:
                out.append((b, c, d))
    return out


def cup(r_out=40, r_in=36, h=96, floor=4, segs=96):
    """A closed, watertight cup: outer wall, rim, inner wall, inner floor, base."""
    def ring(r, z):
        return [(r * math.cos(2 * math.pi * k / segs), r * math.sin(2 * math.pi * k / segs), z) for k in range(segs)]

    ob, ot, it, ib = ring(r_out, 0), ring(r_out, h), ring(r_in, h), ring(r_in, floor)
    out = []
    for k in range(segs):
        n = (k + 1) % segs
        out += [(ob[k], ob[n], ot[n]), (ob[k], ot[n], ot[k])]   # outer wall
        out += [(ot[k], ot[n], it[n]), (ot[k], it[n], it[k])]   # rim
        out += [(it[k], it[n], ib[n]), (it[k], ib[n], ib[k])]   # inner wall
        out.append(((0, 0, floor), ib[k], ib[n]))               # inner floor
        out.append(((0, 0, 0), ob[n], ob[k]))                   # base
    return out


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(tempfile.gettempdir(), "cad_viewer_samples")
    os.makedirs(out, exist_ok=True)
    write_binary(os.path.join(out, "cup.stl"), cup())
    write_binary(os.path.join(out, "block.stl"), box(40, 30, 20))
    write_binary(os.path.join(out, "sphere.stl"), sphere(25, 48, 96))
    write_ascii(os.path.join(out, "cube_ascii.stl"), box(20, 20, 20))
    big = os.path.join(out, "big_1m.stl")
    if not os.path.exists(big):
        write_binary(big, sphere(60, 708, 708))   # 1,001,112 triangles
    with open(os.path.join(out, "block.stl"), "rb") as f:
        data = f.read()
    with open(os.path.join(out, "broken_truncated.stl"), "wb") as f:
        f.write(data[:300])
    with open(os.path.join(out, "broken_text.stl"), "w") as f:
        f.write("This is not a shape file.\n")
    print(out)


if __name__ == "__main__":
    main()
