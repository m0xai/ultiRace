import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k  # noqa: E402


def build():
    """Phantom: sleek white GT, long smoked canopy, twin tail fins, cyan glow lines."""
    P = k.palette("#f3f5fa", "#55e6ff")
    cyan = k.glow("Cyan", "#55e6ff", 5.0)
    S = [
        dict(y=-2.15, w=0.80, zb=0.38, zt=0.80, p=3.2, top=0.9),
        dict(y=-1.70, w=0.98, zb=0.28, zt=0.90, p=3.4, top=0.88),
        dict(y=0.00, w=0.98, zb=0.26, zt=0.88, p=3.4, top=0.88),
        dict(y=1.30, w=0.94, zb=0.28, zt=0.72, p=3.4, top=0.9),
        dict(y=2.20, w=0.62, zb=0.34, zt=0.50, p=2.8, top=0.92),
    ]
    body = k.loft("Body", S, [P["Paint"]], ring=28)
    C = [
        dict(y=-1.70, w=0.70, zb=0.80, zt=0.86, p=2.8, top=0.9),
        dict(y=-0.90, w=0.76, zb=0.80, zt=1.22, p=3.0, top=0.7),
        dict(y=0.10, w=0.76, zb=0.80, zt=1.28, p=3.0, top=0.68),
        dict(y=0.90, w=0.72, zb=0.76, zt=0.86, p=2.8, top=0.9),
    ]
    canopy = k.cabin("Canopy", C, P, roof_from=0.96)
    wheels = k.four_wheels(0.85, 1.35, -1.35, 0.40, 0.42, 0.34, 0.38, P, spokes=10)
    k.cut_arches(body, wheels)
    k.finalize_body(body)
    parts = k.standard_details(P, front=(0.45, 2.08, 0.5), rear=(0.6, -2.12, 0.72), mirror=(0.82, 0.75, 0.92), bumper_w=1.2, bumper_z=0.4)
    fins = [k.rounded_box("fin", (0.05, 0.75, 0.36), (0.42, -1.8, 0.98), P["Paint"], bevel=0.025, rot=(-0.35, 0.12, 0))]
    fins += k.mirror_x(fins)
    glow = [k.rounded_box("glow_side", (0.03, 2.6, 0.04), (0.985, 0.0, 0.55), cyan, bevel=0.01, segs=1)]
    glow += k.mirror_x(glow)
    glow.append(k.rounded_box("glow_rear", (1.3, 0.03, 0.05), (0, -2.15, 0.62), cyan, bevel=0.01, segs=1))
    k.join(body, [canopy] + parts + fins + glow)


k.run(build)
