import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k  # noqa: E402


def build():
    """Volt: faceted purple wedge, angular canopy, two antennas with glowing tips."""
    P = k.palette("#8e5cf0", "#ffe14a")
    S = [
        dict(y=-2.05, w=0.92, zb=0.36, zt=0.98, p=1.7, top=0.85),
        dict(y=-1.40, w=1.02, zb=0.30, zt=1.00, p=1.8, top=0.85),
        dict(y=0.40, w=1.00, zb=0.30, zt=0.92, p=1.8, top=0.85),
        dict(y=1.40, w=0.95, zb=0.32, zt=0.74, p=1.8, top=0.88),
        dict(y=2.15, w=0.70, zb=0.38, zt=0.48, p=1.6, top=0.9),
    ]
    body = k.loft("Body", S, [P["Paint"]], ring=16)
    C = [
        dict(y=-1.10, w=0.74, zb=0.86, zt=0.98, p=1.8, top=0.85),
        dict(y=-0.70, w=0.76, zb=0.86, zt=1.36, p=1.9, top=0.62),
        dict(y=0.10, w=0.76, zb=0.86, zt=1.38, p=1.9, top=0.62),
        dict(y=0.85, w=0.72, zb=0.82, zt=0.90, p=1.8, top=0.85),
    ]
    canopy = k.cabin("Canopy", C, P, roof_from=0.9)
    wheels = k.four_wheels(0.88, 1.3, -1.3, 0.37, 0.39, 0.36, 0.40, P, spokes=3)
    k.cut_arches(body, wheels)
    k.finalize_body(body)
    tip = k.glow("Tip", "#ffe14a", 6.0)
    parts = k.standard_details(P, front=(0.5, 2.0, 0.55), rear=(0.62, -2.04, 0.8), mirror=(0.86, 0.7, 0.98), bumper_w=1.4, bumper_z=0.45, doors=dict(x=1.0, z0=0.42, z1=0.86, seams=[0.82, -0.6], handles=[-0.44]))
    ants = [k.tube("ant", (0.55, -1.55, 0.95), (0.62, -1.75, 2.35), 0.025, P["Trim"]),
            k.blob("ant_tip", 0.09, (0.62, -1.75, 2.42), tip)]
    ants += k.mirror_x(ants)
    stripes = [k.rounded_box("bolt_stripe", (0.08, 1.6, 0.04), (0.98, 0.0, 0.7), P["Accent"], bevel=0.01, rot=(0, 0, 0))]
    stripes += k.mirror_x(stripes)
    k.join(body, [canopy] + parts + ants + stripes)


k.run(build)
