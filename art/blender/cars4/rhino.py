import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k2  # noqa: E402
import carkit4 as k  # noqa: E402

# Rhino: full-size off-road pickup: tall cab and hood (one shell), load bed, push bar, roof lights.
ST = [
    dict(y=-0.5, zf=0.56, zb=1.2, wb=1.06, wl=1.02, zt=1.86, wt=0.98, crown=0.03),
    dict(y=-0.3, zf=0.55, zb=1.2, wb=1.08, wl=1.04, zt=1.95, wt=0.99, crown=0.04),
    dict(y=0.72, zf=0.55, zb=1.2, wb=1.08, wl=1.04, zt=1.96, wt=0.99, crown=0.04),
    dict(y=1.22, zf=0.55, zb=1.2, wb=1.08, wl=1.04, zt=1.31, wt=1.0, crown=0.04),
    dict(y=1.8, zf=0.56, zb=1.19, wb=1.07, wl=1.03, zt=1.29, wt=1.0, crown=0.04),
    dict(y=2.15, zf=0.6, zb=1.12, wb=1.02, wl=0.98, zt=1.22, wt=0.96, crown=0.02),
]
CABIN = dict(ws=(0.74, 1.2), rw=None, back=-0.5, b=0.2, a_w=0.1, c_w=0.12, b_w=0.11)


def build():
    P = k.palette("#7d8590", "#f07a1f", metallic=0.45)
    A, T = P["Accent"], P["Trim"]
    body = k.body("Body", P, ST, CABIN, nose_round=(0.96, 0.82), tail_round=(0.97, 0.85))
    wheels = [(-1.0, 1.35, 0.49), (1.0, 1.35, 0.49), (-1.0, -1.35, 0.48), (1.0, -1.35, 0.48)]
    k.arches(body, wheels, P, width=0.85)
    parts = k2.standard_details(P, front=(0.7, 2.2, 1.0), rear=(0.95, -2.12, 1.05), mirror=(1.08, 1.05, 1.5),
                                grille=(1.1, 2.24, 0.9), bumper_w=2.0, bumper_z=0.72,
                                doors=dict(z0=0.66, z1=1.18, seams=[1.15, 0.2], handles=[0.92, -0.05]), target=body,
                                hl=dict(half=(0.2, 0.09), slant=0.0, p=5.0), hood_back=0.2)
    # rear window on the upright cab back
    parts.append(k2.patch("rear_glass", body, (0, -0.5, 1.6), (0.72, 0.2), (0, 1, 0), P["GlassClear"], off=0.006, p=6.0, rings=2, segs=24))
    # load bed: floor, walls with orange rails, tailgate with lamps
    bed = [k2.rounded_box("bed_floor", (2.0, 1.6, 0.12), (0, -1.3, 0.92), T, bevel=0.02, segs=1)]
    for sx in (1, -1):
        bed.append(k2.rounded_box("bed_wall", (0.1, 1.62, 0.5), (sx * 1.0, -1.3, 1.15), P["Paint"], bevel=0.03, segs=2))
        bed.append(k2.rounded_box("rail", (0.14, 1.62, 0.06), (sx * 1.0, -1.3, 1.42), A, bevel=0.02, segs=1))
        bed.append(k2.rounded_box("tail_l", (0.06, 0.04, 0.32), (sx * 0.92, -2.13, 1.12), P["TailLight"], bevel=0.01, segs=1))
    bed.append(k2.rounded_box("tailgate", (2.08, 0.1, 0.55), (0, -2.1, 1.12), P["Paint"], bevel=0.03, segs=2))
    bed.append(k2.rounded_box("bed_under", (1.9, 1.6, 0.4), (0, -1.3, 0.72), T, bevel=0.02, segs=1))
    bed.append(k2.rounded_box("bumper_r", (2.0, 0.2, 0.18), (0, -2.2, 0.66), T, bevel=0.03, segs=2))
    bar = [k2.tube("bar_top", (-0.85, 2.34, 0.9), (0.85, 2.34, 0.9), 0.06, P["Chrome"], verts=16)]
    bar += [k2.tube("bar_leg", (sx * 0.6, 2.2, 0.5), (sx * 0.6, 2.34, 0.9), 0.055, P["Chrome"], verts=16) for sx in (1, -1)]
    lights = [k2.rounded_box("lightbar", (1.4, 0.18, 0.08), (0, 0.4, 2.01), T, bevel=0.02, segs=1)]
    lights += [k2.rounded_box("roof_light", (0.24, 0.04, 0.1), (x, 0.5, 2.02), k2.glow("Amber", "#ffb020"), bevel=0.01, segs=1)
               for x in (-0.48, -0.16, 0.16, 0.48)]
    flares = []
    for (x, y, r) in wheels:  # black fender flares
        flares.append(k2.rounded_box("flare", (0.12, r * 2.5, 0.12), (x * 1.09, y, r * 2.05), T, bevel=0.04, segs=2))
    k2.join(body, parts + bed + bar + lights + flares + k.interior(P) + k.wipers(body, P) + (k.hi_extras(body, P) if k.DETAIL >= 2 else []))
    k.four_wheels(1.0, 1.35, -1.35, 0.49, 0.48, 0.36, 0.36, P, spokes=6, twin=False, rim_mat="RimDark")


k.run(build)
