import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k  # noqa: E402


def build():
    """Hook: green tow truck: cab up front, flat rear deck, yellow crane arm with a hook."""
    P = k.palette("#33b852", "#f5c21b")
    S = [
        dict(y=-2.05, w=0.98, zb=0.42, zt=1.00, p=5, top=0.98),
        dict(y=-1.90, w=1.02, zb=0.38, zt=1.04, p=6, top=0.98),
        dict(y=1.60, w=1.00, zb=0.38, zt=1.06, p=6, top=0.96),
        dict(y=2.10, w=0.90, zb=0.45, zt=0.92, p=4, top=0.94),
    ]
    body = k.loft("Body", S, [P["Paint"]], ring=24)
    C = [
        dict(y=0.10, w=0.94, zb=1.0, zt=1.10, p=5, top=0.95),
        dict(y=0.20, w=0.96, zb=1.0, zt=1.75, p=6, top=0.88),
        dict(y=1.05, w=0.94, zb=1.0, zt=1.72, p=6, top=0.86),
        dict(y=1.55, w=0.90, zb=1.0, zt=1.10, p=5, top=0.94),
    ]
    cab = k.cabin("Cab", C, P, roof_from=0.88)
    wheels = k.four_wheels(0.92, 1.3, -1.3, 0.46, 0.46, 0.40, 0.40, P, spokes=6)
    k.cut_arches(body, wheels)
    k.finalize_body(body)
    Y = P["Accent"]
    parts = k.standard_details(P, front=(0.55, 2.04, 0.8), rear=(0.7, -2.06, 0.85), mirror=(0.98, 1.3, 1.35),
                               grille=(0.6, 2.1, 0.62), bumper_w=1.7, bumper_z=0.52, doors=dict(x=1.02, z0=0.52, z1=1.02, seams=[1.5, 0.22], handles=[0.38]))
    crane = [k.rounded_box("crane_base", (0.55, 0.55, 0.3), (0, -0.9, 1.2), Y, bevel=0.05),
             k.tube("crane_arm", (0, -0.9, 1.3), (0, -1.9, 2.5), 0.12, Y),
             k.tube("crane_tip", (0, -1.9, 2.5), (0, -2.45, 2.45), 0.09, Y),
             k.tube("cable", (0, -2.45, 2.45), (0, -2.45, 1.75), 0.025, P["Trim"]),
             k.tube("hook", (0, -2.45, 1.75), (0, -2.55, 1.6), 0.07, P["Chrome"])]
    beacon = [k.blob("beacon", 0.11, (0, 0.65, 1.82), k.glow("Amber", "#ffa21a"), scale=(1, 1, 0.8))]
    k.join(body, [cab] + parts + crane + beacon)


k.run(build)
