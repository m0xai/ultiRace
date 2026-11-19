import os, sys, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit as k

C = k.hexcol("#F2F4F8")


def build():
    """Phantom: sleek white low body, long glass canopy, twin tail fins."""
    parts = [
        k.wedge("chassis", (1.85, 4.0, 0.5), (0, 0, 0.5), C, front_drop=0.45, bevel=0.1, segs=3),
        k.box("canopy", (1.2, 2.0, 0.42), (0, -0.2, 0.95), k.GLASS, taper=(0.7, 0.75), bevel=0.1, segs=2, material="Glass"),
        k.box("fin_l", (0.07, 0.9, 0.6), (-0.55, -1.6, 1.0), (0.75, 0.8, 0.95, 1), taper=(1, 0.35), bevel=0.02),
        k.box("fin_r", (0.07, 0.9, 0.6), (0.55, -1.6, 1.0), (0.75, 0.8, 0.95, 1), taper=(1, 0.35), bevel=0.02),
        k.box("glow", (1.6, 0.1, 0.08), (0, -2.0, 0.6), (0.6, 0.85, 1.0, 1), bevel=0.02),
    ]
    k.body_from(parts)
    k.wheels(track=1.7, radius=0.36)


k.run(build)
