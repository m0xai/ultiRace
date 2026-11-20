import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k  # noqa: E402


def build():
    """Glacier: round bubble car, ice blue with white accents, domed glass, skirts."""
    P = k.palette("#6fd0f5", "#f2f8ff")
    S = [
        dict(y=-1.95, w=0.80, zb=0.42, zt=0.92, p=2.4, top=0.9),
        dict(y=-1.60, w=0.98, zb=0.32, zt=1.05, p=2.6, top=0.88),
        dict(y=-0.30, w=1.02, zb=0.30, zt=1.08, p=2.8, top=0.86),
        dict(y=1.10, w=0.98, zb=0.32, zt=0.95, p=2.6, top=0.88),
        dict(y=1.85, w=0.80, zb=0.40, zt=0.74, p=2.4, top=0.9),
        dict(y=2.05, w=0.55, zb=0.48, zt=0.64, p=2.2, top=0.9),
    ]
    body = k.loft("Body", S, [P["Paint"]], ring=28)
    C = [
        dict(y=-1.30, w=0.78, zb=0.95, zt=1.0, p=2.4, top=0.9),
        dict(y=-0.90, w=0.84, zb=0.95, zt=1.50, p=2.4, top=0.7),
        dict(y=-0.10, w=0.86, zb=0.95, zt=1.62, p=2.4, top=0.68),
        dict(y=0.60, w=0.84, zb=0.95, zt=1.45, p=2.4, top=0.72),
        dict(y=1.00, w=0.78, zb=0.92, zt=0.98, p=2.4, top=0.9),
    ]
    dome = k.cabin("Dome", C, P, roof_from=0.93)
    wheels = k.four_wheels(0.88, 1.25, -1.25, 0.42, 0.42, 0.38, 0.38, P, rim="Accent", spokes=4)
    k.cut_arches(body, wheels)
    k.finalize_body(body)
    parts = k.standard_details(P, front=(0.45, 1.92, 0.66), rear=(0.55, -1.92, 0.78), mirror=(0.86, 0.95, 1.05), bumper_w=1.3, bumper_z=0.5, doors=dict(x=1.02, z0=0.48, z1=0.98, seams=[0.72, -0.62], handles=[-0.46]))
    fins = [k.rounded_box("fin", (0.06, 0.6, 0.32), (0, -1.45, 1.15), P["Accent"], bevel=0.02)]
    skirt = [k.rounded_box("skirt", (0.08, 1.4, 0.12), (0.99, 0, 0.42), P["Accent"], bevel=0.04)]
    skirt += k.mirror_x(skirt)
    k.join(body, [dome] + parts + fins + skirt)


k.run(build)
