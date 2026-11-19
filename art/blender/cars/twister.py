import os, sys, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit as k

C = k.hexcol("#1FB5A8")


def build():
    """Twister: teal open buggy with roll cage and a big rear fan."""
    D = (0.14, 0.15, 0.16, 1)
    parts = [
        k.box("tub", (1.7, 3.0, 0.5), (0, 0.2, 0.75), C, bevel=0.1),
        k.box("seat", (0.7, 0.6, 0.5), (0, -0.2, 1.15), D, bevel=0.06),
        k.box("cage_l", (0.09, 0.09, 1.0), (-0.55, 0.1, 1.5), D, rot=(math.radians(-12), 0, 0), bevel=0.02),
        k.box("cage_r", (0.09, 0.09, 1.0), (0.55, 0.1, 1.5), D, rot=(math.radians(-12), 0, 0), bevel=0.02),
        k.box("cage_top", (1.2, 0.09, 0.09), (0, 0.0, 2.0), D, bevel=0.02),
        k.cyl("fan_ring", 0.95, 0.18, (0, -1.6, 1.25), k.shade(C, 0.6), rot=(math.pi / 2, 0, 0), verts=18, bevel=0.03),
        k.box("blade1", (1.6, 0.05, 0.2), (0, -1.62, 1.25), D, rot=(0, math.radians(30), 0), bevel=0.01),
        k.box("blade2", (1.6, 0.05, 0.2), (0, -1.62, 1.25), D, rot=(0, math.radians(-60), 0), bevel=0.01),
    ]
    k.body_from(parts)
    k.wheels(track=1.85, radius=0.45, width=0.4)


k.run(build)
