import os, sys, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit as k

C = k.hexcol("#A6E22E")


def build():
    """Goo: lime tanker, cab up front, big rounded tank, drippy blobs."""
    parts = [
        k.box("frame", (1.9, 3.9, 0.3), (0, 0, 0.55), (0.2, 0.22, 0.2, 1), bevel=0.05),
        k.box("cab", (1.85, 1.1, 0.95), (0, 1.35, 1.15), C, bevel=0.12),
        k.box("window", (1.6, 0.08, 0.4), (0, 1.92, 1.35), k.GLASS, bevel=0.02, material="Glass"),
        k.cyl("tank", 0.82, 2.5, (0, -0.55, 1.42), k.shade(C, 0.85), rot=(math.pi / 2, 0, 0), verts=16, bevel=0.12, segs=2),
        k.ball("blob1", 0.22, (-0.5, -0.4, 2.2), C, segs=8, rings=6),
        k.ball("blob2", 0.16, (0.35, -1.2, 2.18), C, segs=8, rings=6),
    ]
    k.body_from(parts)
    k.wheels(track=1.75, radius=0.4, width=0.36)


k.run(build)
