#!/usr/bin/env python3
"""Track layout generator: turtle paths (straights + arcs) → map control points.

Each layout is a list of pieces: ("S", length) straight, ("S?",) straight whose length is solved
so the loop closes, ("A", radius, degrees) arc (+ = left, − = right). Headings must sum to
±360° (or 0° for a figure-8 lobe, which is mirrored). Points are emitted every ≤ 18 m on
straights and every ≤ 14 m on arcs: even spacing keeps the Catmull-Rom spline from
overshooting where straights meet arcs (that made 5 m kinks).

  python3 scripts/trackgen.py            # rewrite gamedata/maps/{sunny,frosty,neon}.json points
  python3 scripts/trackgen.py --print    # only print lengths / piece positions

Then: go test ./internal/track/ && make fixtures sync test.
"""
import json
import math
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

LAYOUTS = {
    # Sunny: long straight, fast right, chicane, hairpin, esses (flat, 20 m). Pieces found by a
    # constrained search (closes, 1100-1500 m, no overlap, max tight-corner degrees).
    "sunny": dict(width=20, start_heading=0.0, pieces=[
        ("S", 193.0), ("A", 69.6, -60.4), ("S?",), ("A", 38.8, 48.4), ("A", 47.5, -38.9), ("S", 62.2),
        ("A", 36.5, -160.9), ("S", 137.0), ("A", 63.8, 69.4), ("A", 47.8, -79.9), ("S?",), ("A", 50.6, -137.8),
    ]),
    # Frosty: climbs to a snowy crest and back, two ramps, a hairpin, tight right-left sequence
    "frosty": dict(width=19, start_heading=0.0, pieces=[
        ("S", 168.9), ("A", 56.6, -62.7), ("S", 75.2), ("A", 40.0, -84.4), ("A", 45.0, 73.4), ("S?",),
        ("A", 38.6, -143.0), ("S", 128.1), ("A", 50.7, 42.8), ("A", 48.9, -69.9), ("S?",), ("A", 75.5, -116.2),
    ]),
    # Neon: figure-8; this lobe (x > 0) is mirrored for the other one, flyover at the crossing.
    # Hand-placed: chicane on the top run, hairpin at the far end, kink on the way back.
    "neon": dict(width=20, lobe_points=[
        (0, 0), (55, 40), (105, 66), (152, 64), (200, 86), (248, 66), (282, 52), (314, 32),
        (322, 2), (306, -24), (270, -36), (222, -40), (178, -58), (128, -60), (78, -44), (34, -22),
    ]),
}


def walk(pieces, h0, free):
    """Returns the polyline [(x, z, heading_deg, kind)] for given free straight lengths."""
    x, z, h = 0.0, 0.0, h0
    out = [(x, z, h, "S")]
    fi = 0
    for p in pieces:
        if p[0] in ("S", "S?"):
            L = p[1] if p[0] == "S" else free[fi]
            if p[0] == "S?":
                fi += 1
            n = max(1, math.ceil(L / 18.0))
            for k in range(1, n + 1):
                t = L * k / n
                out.append((x + math.cos(math.radians(h)) * t, z + math.sin(math.radians(h)) * t, h, "S"))
            x, z = out[-1][0], out[-1][1]
        else:
            R, deg = p[1], p[2]
            n = max(2, math.ceil(R * math.radians(abs(deg)) / 14.0))
            sgn = 1 if deg > 0 else -1
            # centre of the turn
            cx = x + math.cos(math.radians(h + 90 * sgn)) * R
            cz = z + math.sin(math.radians(h + 90 * sgn)) * R
            a0 = math.radians(h - 90 * sgn)
            for k in range(1, n + 1):
                a = a0 + math.radians(deg) * k / n
                out.append((cx + math.cos(a) * R, cz + math.sin(a) * R, h + deg * k / n, "A"))
            x, z, h = out[-1][0], out[-1][1], h + deg
    return out


def solve(lay):
    pieces, h0 = lay["pieces"], lay["start_heading"]
    nfree = sum(1 for p in pieces if p[0] == "S?")
    assert nfree == 2, "need exactly two free straights"
    # end displacement is affine in the free lengths: d(L) = d0 + L1·u1 + L2·u2
    d0 = walk(pieces, h0, [0, 0])[-1]
    d1 = walk(pieces, h0, [1, 0])[-1]
    d2 = walk(pieces, h0, [0, 1])[-1]
    u1 = (d1[0] - d0[0], d1[1] - d0[1])
    u2 = (d2[0] - d0[0], d2[1] - d0[1])
    if lay.get("lobe"):
        target = (0.0, 0.0)  # back to the crossing
    else:
        target = (0.0, 0.0)
    rx, rz = target[0] - d0[0], target[1] - d0[1]
    det = u1[0] * u2[1] - u1[1] * u2[0]
    L1 = (rx * u2[1] - rz * u2[0]) / det
    L2 = (u1[0] * rz - u1[1] * rx) / det
    if L1 < 15 or L2 < 15:
        raise SystemExit(f"layout does not close with positive straights: {L1:.1f}, {L2:.1f}")
    return [L1, L2], walk(pieces, h0, [L1, L2])


def length(poly):
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(poly, poly[1:]))


def build(map_id):
    lay = LAYOUTS[map_id]
    if "lobe_points" in lay:
        free = [0.0, 0.0]
        lobe = [(x, z, 0.0, "A") for (x, z) in lay["lobe_points"]]
        pts = lobe + [(-x, z, 0.0, k) for (x, z, h, k) in lobe]
    else:
        free, poly = solve(lay)
        pts = poly[:-1]  # last point == first
    L = length(pts + [pts[0]])
    out, s = [], 0.0
    prev = pts[0]
    total = L
    for i, (x, z, h, kind) in enumerate(pts):
        if i > 0:
            s += math.hypot(x - prev[0], z - prev[1])
        prev = (x, z)
        f = s / total
        if map_id == "frosty":
            y = 15.0 - 15.0 * math.cos(2 * math.pi * f)  # climb to the 30 m crest and back
        elif map_id == "neon":
            y = 10.0 * abs(1 - 2 * f)  # 10 m at the start crossing (flyover), 0 at the middle one
        else:
            y = 0.0
        bank = 0.12 if (kind == "A" and map_id == "frosty") else 0.0
        out.append([round(x, 2), round(y, 2), round(z, 2), lay["width"], bank])
    return out, L, free


def main():
    only_print = "--print" in sys.argv
    for map_id in LAYOUTS:
        pts, L, free = build(map_id)
        print(f"{map_id}: {len(pts)} points, polyline length {L:.1f} m, free straights {free[0]:.1f} / {free[1]:.1f} m")
        if only_print:
            continue
        path = os.path.join(ROOT, "gamedata", "maps", f"{map_id}.json")
        m = json.load(open(path))
        m["points"] = pts
        with open(path, "w") as f:
            f.write("{\n")
            f.write(f'  "id": {json.dumps(m["id"])},\n  "name": {json.dumps(m["name"])},\n  "theme": {json.dumps(m["theme"])},\n')
            f.write('  "points": [\n')
            f.write(",\n".join("    " + json.dumps(p) for p in pts))
            f.write("\n  ],\n")
            f.write(f'  "ramps": {json.dumps(m.get("ramps", []))}\n}}\n')


if __name__ == "__main__":
    main()
