import os, sys, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit as k

C = k.hexcol("#8A8F98")
O = k.hexcol("#E8772E")


def build():
    """Rhino: wide boxy truck, grey with orange, bull bar, raised stance."""
    parts = [
        k.box("chassis", (2.15, 3.9, 0.8), (0, 0, 0.95), C, bevel=0.1),
        k.box("cab", (1.95, 1.6, 0.75), (0, 0.45, 1.7), O, bevel=0.1),
        k.box("window", (1.8, 0.1, 0.45), (0, 1.26, 1.75), k.GLASS, bevel=0.02, material="Glass"),
        k.box("bed", (1.9, 1.5, 0.15), (0, -1.1, 1.42), k.shade(C, 0.6), bevel=0.03),
        k.box("bar", (2.3, 0.18, 0.18), (0, 2.05, 0.95), (0.12, 0.12, 0.13, 1), bevel=0.04),
        k.box("bar_v1", (0.16, 0.16, 0.7), (-0.6, 2.02, 0.95), (0.12, 0.12, 0.13, 1), bevel=0.03),
        k.box("bar_v2", (0.16, 0.16, 0.7), (0.6, 2.02, 0.95), (0.12, 0.12, 0.13, 1), bevel=0.03),
        k.box("stripe", (2.17, 1.0, 0.12), (0, 1.0, 1.15), O, bevel=0.02),
    ]
    k.body_from(parts)
    k.wheels(track=1.95, front_y=1.3, rear_y=-1.3, radius=0.5, width=0.42)


k.run(build)
