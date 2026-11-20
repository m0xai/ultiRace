import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k2  # noqa: E402
import carkit4 as k  # noqa: E402

# Volt: angular purple coupe with a cab-forward cabin, ducktail, lightning stripes, two antennas.
ST = [
    dict(y=-2.15, zf=0.36, zb=0.86, wb=0.92, wl=0.87, zt=0.94, wt=0.84, crown=0.01),
    dict(y=-1.8, zf=0.29, zb=0.86, wb=0.98, wl=0.93, zt=0.96, wt=0.86, crown=0.02),
    dict(y=-1.1, zf=0.27, zb=0.85, wb=0.99, wl=0.95, zt=1.0, wt=0.84, crown=0.02),
    dict(y=-0.6, zf=0.27, zb=0.84, wb=0.99, wl=0.95, zt=1.27, wt=0.68, crown=0.03),
    dict(y=0.45, zf=0.27, zb=0.82, wb=0.98, wl=0.94, zt=1.3, wt=0.7, crown=0.03),
    dict(y=1.15, zf=0.28, zb=0.78, wb=0.97, wl=0.93, zt=0.86, wt=0.84, crown=0.03),
    dict(y=2.15, zf=0.33, zb=0.62, wb=0.9, wl=0.84, zt=0.68, wt=0.8, crown=0.02),
]
CABIN = dict(ws=(0.48, 1.12), rw=(-1.08, -0.62), b=-0.05, a_w=0.1, c_w=0.1, b_w=0.1)


def build():
    P = k.palette("#8e5cf0", "#ffe14a", metallic=0.6)
    tip = k2.glow("Tip", "#ffe14a", 6.0)
    body = k.body("Body", P, ST, CABIN, nose_round=(0.94, 0.72), tail_round=(0.98, 0.9))
    wheels = [(-0.9, 1.3, 0.37), (0.9, 1.3, 0.37), (-0.9, -1.3, 0.39), (0.9, -1.3, 0.39)]
    k.arches(body, wheels, P)
    parts = k2.standard_details(P, front=(0.6, 2.15, 0.58), rear=(0.68, -2.15, 0.82), mirror=(0.9, 0.85, 0.96),
                                grille=(0.8, 2.2, 0.42), bumper_w=1.5, bumper_z=0.4,
                                doors=dict(z0=0.4, z1=0.82, seams=[1.05, -0.55], handles=[-0.35]), target=body,
                                hl=dict(half=(0.26, 0.05), slant=0.45, p=6.0), tl=dict(half=(0.34, 0.05), slant=0.0, p=6.0), hood_back=0.14)
    stripes = []
    for sx in (1, -1):
        for (y0, z0, y1, z1) in ((1.6, 0.66, 0.95, 0.58), (0.95, 0.58, 0.35, 0.7), (0.35, 0.7, -0.4, 0.56), (-0.4, 0.56, -1.2, 0.68)):
            starts = [(sx * 3.0, y0 + (y1 - y0) * i / 8, z0 + (z1 - z0) * i / 8) for i in range(9)]
            ln = k2.surface_line("bolt", body, starts, (-sx, 0, 0), 0.05, P["Accent"], off=0.004,
                                 keep=lambda n, s=sx: n.x * s > 0.3)
            if ln:
                stripes.append(ln)
    ants = []
    for sx in (1, -1):
        ants.append(k2.tube("ant", (sx * 0.55, -1.6, 0.98), (sx * 0.62, -1.78, 2.3), 0.018, P["Trim"], verts=10))
        ants.append(k2.blob("ant_tip", 0.07, (sx * 0.62, -1.79, 2.36), tip, segs=16, rings=10))
    duck = [k2.rounded_box("ducktail", (1.6, 0.25, 0.06), (0, -2.08, 1.0), P["Paint"], bevel=0.02, segs=2, rot=(0.15, 0, 0))]
    k2.join(body, parts + stripes + ants + duck + k.interior(P) + k.wipers(body, P))
    k.four_wheels(0.9, 1.3, -1.3, 0.37, 0.39, 0.27, 0.31, P, spokes=3, twin=True, rim_mat="RimDark")


k.run(build)
