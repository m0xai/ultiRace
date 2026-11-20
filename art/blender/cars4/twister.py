import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k2  # noqa: E402
import carkit4 as k  # noqa: E402

# Twister: teal dune buggy: low open tub (one shell, no cabin), roll cage, seat, big caged fan.
ST = [
    dict(y=-1.42, zf=0.5, zb=0.9, wb=0.7, wl=0.66, zt=0.96, wt=0.62, crown=0.02),
    dict(y=-1.2, zf=0.45, zb=0.92, wb=0.74, wl=0.7, zt=0.98, wt=0.64, crown=0.02),
    dict(y=0.6, zf=0.45, zb=0.9, wb=0.72, wl=0.68, zt=0.95, wt=0.62, crown=0.02),
    dict(y=1.5, zf=0.48, zb=0.84, wb=0.66, wl=0.62, zt=0.92, wt=0.56, crown=0.03),
    dict(y=1.95, zf=0.55, zb=0.74, wb=0.56, wl=0.52, zt=0.8, wt=0.48, crown=0.02),
]


def build():
    P = k.palette("#18b8a8", "#ff6b3d", metallic=0.5)
    A, T = P["Accent"], P["Trim"]
    body = k.body("Body", P, ST, None, nose_round=(0.94, 0.75), tail_round=(0.96, 0.85))
    k2.finalize_body(body)
    parts = k2.standard_details(P, front=(0.36, 1.95, 0.8), rear=(0.45, -1.42, 0.82), mirror=(0.7, 0.55, 1.05),
                                bumper_w=1.1, bumper_z=0.6, target=body, hl=dict(half=(0.12, 0.05), slant=0.0, p=4.0),
                                tl=dict(half=(0.1, 0.05), slant=0.0), hood_back=0.12)
    seat = [k2.rounded_box("seat", (0.6, 0.55, 0.14), (0, -0.25, 0.98), A, bevel=0.05, segs=2),
            k2.rounded_box("seat_back", (0.6, 0.14, 0.62), (0, -0.52, 1.26), A, bevel=0.05, segs=2, rot=(0.2, 0, 0)),
            k2.disc("steering", 0.16, 0.03, (0, 0.35, 1.25), T, axis="Y", verts=20)]
    cage = [k2.tube("c1", (-0.6, -0.5, 0.95), (-0.45, -0.2, 1.85), 0.045, T, verts=12),
            k2.tube("c2", (0.6, -0.5, 0.95), (0.45, -0.2, 1.85), 0.045, T, verts=12),
            k2.tube("c3", (-0.45, -0.2, 1.85), (0.45, -0.2, 1.85), 0.045, T, verts=12),
            k2.tube("c4", (-0.45, -0.2, 1.85), (-0.55, 0.75, 0.95), 0.045, T, verts=12),
            k2.tube("c5", (0.45, -0.2, 1.85), (0.55, 0.75, 0.95), 0.045, T, verts=12)]
    ring = k2.lathe("fan_ring", [(0.94, -0.09), (1.04, -0.08), (1.06, 0.0), (1.04, 0.08), (0.94, 0.09)], [0] * 4, [A], segments=48)
    ring.rotation_euler = (0, 0, math.pi / 2)
    ring.location = (0, -1.68, 1.4)
    blades = [k2.rounded_box("blade", (0.16, 0.035, 0.88), (0, -1.68, 1.4), T, bevel=0.015, segs=2, rot=(0, a, 0.25))
              for a in (0.0, 1.05, 2.1)]
    hub = [k2.disc("fan_hub", 0.15, 0.22, (0, -1.7, 1.4), P["Chrome"], axis="Y", verts=24)]
    struts = [k2.tube("fs", (sx * 0.5, -1.0, 0.95), (sx * 0.64, -1.64, 1.95), 0.035, T, verts=10) for sx in (1, -1)]
    k2.join(body, parts + seat + cage + [ring] + blades + hub + struts + (k.hi_extras(body, P) if k.DETAIL >= 2 else []))
    k.four_wheels(1.02, 1.35, -1.25, 0.42, 0.5, 0.36, 0.44, P, spokes=6, twin=False, rim_mat="Rim")


k.run(build)
