import os, sys, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit as k

C = k.hexcol("#F5C518")


def build():
    """Bolt: low yellow wedge, big rear wing, side intakes."""
    parts = [
        k.wedge("chassis", (1.9, 3.9, 0.55), (0, 0, 0.55), C, front_drop=0.55),
        k.box("cabin", (1.3, 1.3, 0.38), (0, -0.35, 0.98), k.GLASS, taper=(0.75, 0.6), material="Glass"),
        k.box("wing", (2.0, 0.42, 0.06), (0, -1.85, 1.35), k.shade(C, 0.35), bevel=0.02),
        k.box("wing_l", (0.08, 0.3, 0.45), (-0.75, -1.8, 1.08), k.shade(C, 0.35), bevel=0.01),
        k.box("wing_r", (0.08, 0.3, 0.45), (0.75, -1.8, 1.08), k.shade(C, 0.35), bevel=0.01),
        k.box("intake_l", (0.12, 0.8, 0.22), (-0.98, -0.3, 0.6), (0.05, 0.05, 0.05, 1), bevel=0.02),
        k.box("intake_r", (0.12, 0.8, 0.22), (0.98, -0.3, 0.6), (0.05, 0.05, 0.05, 1), bevel=0.02),
    ]
    k.body_from(parts)
    k.wheels(track=1.75, front_y=1.25, rear_y=-1.25, radius=0.36, rear_radius=0.42)


k.run(build)
