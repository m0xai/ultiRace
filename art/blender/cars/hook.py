import os, sys, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit as k

C = k.hexcol("#3DBB5A")
Y = k.hexcol("#F2C230")


def build():
    """Hook: green car with a yellow crane arm and hook on the back."""
    parts = [
        k.box("chassis", (1.95, 3.8, 0.6), (0, 0, 0.65), C, bevel=0.08),
        k.box("cabin", (1.5, 1.3, 0.55), (0, 0.55, 1.2), k.GLASS, taper=(0.8, 0.7), material="Glass"),
        k.box("base", (0.6, 0.6, 0.35), (0, -1.0, 1.12), Y, bevel=0.05),
        k.box("arm", (0.28, 0.28, 1.8), (0, -1.45, 1.95), Y, rot=(math.radians(-35), 0, 0), bevel=0.04),
        k.box("boom", (0.22, 1.1, 0.22), (0, -1.75, 2.75), Y, bevel=0.03),
        k.cyl("cable", 0.03, 0.7, (0, -2.25, 2.35), (0.1, 0.1, 0.1, 1), verts=6, bevel=0),
        k.box("hook", (0.3, 0.12, 0.25), (0, -2.25, 1.95), (0.15, 0.15, 0.16, 1), bevel=0.03),
    ]
    k.body_from(parts)
    k.wheels(track=1.75, radius=0.38)


k.run(build)
