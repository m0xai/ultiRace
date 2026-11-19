import os, sys, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit as k

C = k.hexcol("#7FD3F5")


def build():
    """Glacier: rounded ice-blue body, dome cabin, frosty fins."""
    parts = [
        k.ball("shell", 1.0, (0, 0, 0.72), C, scale=(1.0, 1.95, 0.52), segs=16, rings=10),
        k.ball("dome", 0.7, (0, -0.15, 1.15), k.GLASS, scale=(0.95, 1.35, 0.6), segs=14, rings=8, material="Glass"),
        k.box("skirt", (1.9, 3.5, 0.25), (0, 0, 0.45), k.shade(C, 0.7), bevel=0.1),
        k.box("fin", (0.08, 0.8, 0.35), (0, -1.4, 1.2), (0.92, 0.97, 1.0, 1), taper=(1, 0.4), bevel=0.02),
    ]
    k.body_from(parts)
    k.wheels(track=1.7, radius=0.37)


k.run(build)
