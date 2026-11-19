import os, sys, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit as k

C = k.hexcol("#8E5CF0")


def build():
    """Volt: angular purple body, faceted cabin, two tall antennas with glowing tips."""
    parts = [
        k.box("chassis", (1.95, 3.8, 0.55), (0, 0, 0.6), C, taper=(0.85, 0.9), bevel=0.02, segs=1),
        k.box("nose", (1.6, 0.9, 0.35), (0, 1.75, 0.5), k.shade(C, 0.75), taper=(0.6, 0.6), bevel=0.02, segs=1),
        k.box("cabin", (1.4, 1.4, 0.5), (0, -0.3, 1.1), k.GLASS, taper=(0.65, 0.55), bevel=0.01, segs=1, material="Glass"),
        k.cyl("ant_l", 0.04, 1.6, (-0.6, -1.5, 1.6), (0.2, 0.2, 0.22, 1), verts=6, bevel=0),
        k.cyl("ant_r", 0.04, 1.6, (0.6, -1.5, 1.6), (0.2, 0.2, 0.22, 1), verts=6, bevel=0),
        k.ball("tip_l", 0.12, (-0.6, -1.5, 2.45), (0.9, 0.95, 0.3, 1), segs=8, rings=6),
        k.ball("tip_r", 0.12, (0.6, -1.5, 2.45), (0.9, 0.95, 0.3, 1), segs=8, rings=6),
    ]
    k.body_from(parts)
    k.wheels(track=1.75, radius=0.37)


k.run(build)
