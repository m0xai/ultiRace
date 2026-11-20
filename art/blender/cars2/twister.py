import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k  # noqa: E402


def build():
    """Twister: teal dune buggy: small tub, roll cage, big caged fan at the back, knobby tyres."""
    P = k.palette("#18b8a8", "#ff6b3d")
    S = [
        dict(y=-1.40, w=0.80, zb=0.45, zt=0.95, p=3, top=0.85),
        dict(y=-0.60, w=0.86, zb=0.40, zt=1.00, p=3.2, top=0.85),
        dict(y=1.20, w=0.82, zb=0.42, zt=0.90, p=3.2, top=0.86),
        dict(y=1.95, w=0.62, zb=0.50, zt=0.72, p=2.8, top=0.9),
    ]
    body = k.loft("Body", S, [P["Paint"]], ring=24)
    k.finalize_body(body)
    T = P["Trim"]
    cage = [k.tube("c1", (-0.6, -0.5, 0.95), (-0.45, -0.2, 1.85), 0.05, T), k.tube("c2", (0.6, -0.5, 0.95), (0.45, -0.2, 1.85), 0.05, T),
            k.tube("c3", (-0.45, -0.2, 1.85), (0.45, -0.2, 1.85), 0.05, T), k.tube("c4", (-0.45, -0.2, 1.85), (-0.55, 0.75, 0.95), 0.05, T),
            k.tube("c5", (0.45, -0.2, 1.85), (0.55, 0.75, 0.95), 0.05, T)]
    seat = [k.rounded_box("seat", (0.6, 0.5, 0.55), (0, -0.25, 1.2), P["Accent"], bevel=0.08)]
    ring = k.lathe("fan_ring", [(0.95, -0.12), (1.05, -0.1), (1.05, 0.1), (0.95, 0.12)], [0, 0, 0], [P["Accent"]], segments=32)
    ring.rotation_euler = (0, 0, math.pi / 2)
    ring.location = (0, -1.65, 1.35)
    blades = [k.rounded_box("blade", (0.18, 0.04, 0.9), (0, -1.66, 1.35), T, bevel=0.02, rot=(0, a, 0)) for a in (0.0, 1.05, 2.1)]
    hub = [k.disc("fan_hub", 0.16, 0.2, (0, -1.66, 1.35), P["Chrome"], axis="Y")]
    struts = [k.tube("fs", (0.5, -1.0, 0.95), (0.62, -1.62, 1.95), 0.04, T)]
    struts += k.mirror_x(struts)
    parts = k.standard_details(P, front=(0.38, 1.88, 0.75), rear=(0.5, -1.42, 0.8), mirror=(0.75, 0.6, 1.0), bumper_w=1.1, bumper_z=0.58)
    k.join(body, cage + seat + [ring] + blades + hub + struts + parts)
    k.four_wheels(1.02, 1.35, -1.25, 0.42, 0.48, 0.42, 0.52, P, rim="Accent", spokes=6)


k.run(build)
