import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k2  # noqa: E402
import carkit4 as k  # noqa: E402

# Glacier: compact crossover/hatchback, ice blue with a white roof and ice-crystal fins.
ST = [
    dict(y=-1.98, zf=0.44, zb=0.96, wb=0.93, wl=0.89, zt=1.3, wt=0.82, crown=0.02),
    dict(y=-1.78, zf=0.4, zb=0.98, wb=0.99, wl=0.95, zt=1.5, wt=0.86, crown=0.03),
    dict(y=-1.0, zf=0.38, zb=0.97, wb=1.0, wl=0.96, zt=1.6, wt=0.88, crown=0.04),
    dict(y=0.4, zf=0.38, zb=0.95, wb=1.0, wl=0.96, zt=1.62, wt=0.88, crown=0.04),
    dict(y=1.0, zf=0.38, zb=0.92, wb=0.99, wl=0.95, zt=1.0, wt=0.9, crown=0.05),
    dict(y=1.6, zf=0.39, zb=0.86, wb=0.97, wl=0.93, zt=0.94, wt=0.9, crown=0.05),
    dict(y=2.02, zf=0.43, zb=0.76, wb=0.92, wl=0.88, zt=0.82, wt=0.84, crown=0.03),
]
CABIN = dict(ws=(0.42, 0.98), rw=(-1.96, -1.8), b=-0.38, a_w=0.1, c_w=0.2, b_w=0.11)


def build():
    P = k.palette("#6fd0f5", "#f2f8ff", metallic=0.5)
    A = P["Accent"]
    body = k.body("Body", P, ST, CABIN, nose_round=(0.95, 0.8), tail_round=(0.97, 0.88))
    wheels = [(-0.9, 1.25, 0.38), (0.9, 1.25, 0.38), (-0.9, -1.25, 0.39), (0.9, -1.25, 0.39)]
    k.arches(body, wheels, P)
    parts = k2.standard_details(P, front=(0.58, 2.02, 0.7), rear=(0.72, -1.98, 1.02), mirror=(0.96, 0.9, 1.05),
                                grille=(0.7, 2.06, 0.5), bumper_w=1.6, bumper_z=0.5,
                                doors=dict(z0=0.48, z1=0.93, seams=[0.95, -0.42], handles=[0.6, -0.65]), target=body,
                                hl=dict(half=(0.22, 0.07), slant=0.25), tl=dict(half=(0.2, 0.09), slant=0.0), hood_back=0.18)
    roof = [k2.patch("roof_white", body, (0, -0.55, 3.0), (0.78, 1.1), (0, 0, -1), A, off=0.004, p=6.0, rings=3, segs=28)]
    fins = [k2.rounded_box("crystal", (0.08, 0.7, 0.3), (0, -1.0, 1.75), A, bevel=0.03, segs=2, rot=(-0.3, 0, 0))]
    fins += [k2.rounded_box("crystal", (0.06, 0.45, 0.2), (sx * 0.35, -1.2, 1.7), P["Paint"], bevel=0.03, segs=2, rot=(-0.4, 0, sx * 0.15))
             for sx in (1, -1)]
    rails = [k2.rounded_box("roof_rail", (0.05, 1.7, 0.05), (sx * 0.72, -0.6, 1.66), P["Chrome"], bevel=0.015, segs=1) for sx in (1, -1)]
    k2.join(body, parts + roof + fins + rails + k.interior(P) + k.wipers(body, P) + (k.hi_extras(body, P) if k.DETAIL >= 2 else []))
    k.four_wheels(0.9, 1.25, -1.25, 0.38, 0.39, 0.27, 0.28, P, spokes=5, twin=False)


k.run(build)
