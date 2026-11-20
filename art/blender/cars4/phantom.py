import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k2  # noqa: E402
import carkit4 as k  # noqa: E402

# Phantom: long, low white GT; long hood, set-back cabin with a long fastback, twin fins, cyan glow.
ST = [
    dict(y=-2.25, zf=0.32, zb=0.74, wb=0.9, wl=0.85, zt=0.78, wt=0.8, crown=0.01),
    dict(y=-1.9, zf=0.26, zb=0.78, wb=0.98, wl=0.93, zt=0.84, wt=0.84, crown=0.02),
    dict(y=-1.55, zf=0.25, zb=0.79, wb=0.99, wl=0.94, zt=0.88, wt=0.82, crown=0.02),
    dict(y=-0.6, zf=0.25, zb=0.78, wb=0.99, wl=0.94, zt=1.14, wt=0.66, crown=0.04),
    dict(y=0.05, zf=0.25, zb=0.76, wb=0.98, wl=0.94, zt=1.16, wt=0.68, crown=0.04),
    dict(y=0.75, zf=0.25, zb=0.72, wb=0.97, wl=0.93, zt=0.8, wt=0.82, crown=0.05),
    dict(y=1.7, zf=0.27, zb=0.66, wb=0.95, wl=0.9, zt=0.72, wt=0.82, crown=0.04),
    dict(y=2.25, zf=0.32, zb=0.55, wb=0.88, wl=0.82, zt=0.58, wt=0.76, crown=0.02),
]
CABIN = dict(ws=(0.08, 0.72), rw=(-1.52, -0.62), b=-0.3, a_w=0.1, c_w=0.1, b_w=0.12)


def build():
    P = k.palette("#f3f5fa", "#55e6ff", metallic=0.35)
    cyan = k2.glow("Cyan", "#55e6ff", 5.0)
    body = k.body("Body", P, ST, CABIN, nose_round=(0.94, 0.72), tail_round=(0.97, 0.86))
    wheels = [(-0.88, 1.38, 0.35), (0.88, 1.38, 0.35), (-0.88, -1.38, 0.37), (0.88, -1.38, 0.37)]
    k.arches(body, wheels, P)
    parts = k2.standard_details(P, front=(0.58, 2.25, 0.5), rear=(0.62, -2.25, 0.68), mirror=(0.88, 0.45, 0.88),
                                grille=(0.8, 2.29, 0.36), bumper_w=1.45, bumper_z=0.36,
                                doors=dict(z0=0.36, z1=0.74, seams=[0.72, -0.85], handles=[-0.65]), target=body,
                                hl=dict(half=(0.28, 0.045), slant=0.4, p=6.0), tl=dict(half=(0.36, 0.04), slant=0.0, p=7.0), hood_back=0.14)
    fins = [k2.rounded_box("fin", (0.05, 0.75, 0.32), (sx * 0.45, -1.85, 0.98), P["Paint"], bevel=0.025, segs=2, rot=(-0.35, 0, 0))
            for sx in (1, -1)]
    glow = []
    for sx in (1, -1):
        starts = [(sx * 3.0, -1.9 + 3.8 * i / 16, 0.5) for i in range(17)]
        ln = k2.surface_line("glow_side", body, starts, (-sx, 0, 0), 0.03, cyan, off=0.004, keep=lambda n, s=sx: n.x * s > 0.3)
        if ln:
            glow.append(ln)
    k2.join(body, parts + fins + glow + k.interior(P) + k.wipers(body, P) + (k.hi_extras(body, P) if k.DETAIL >= 2 else []))
    k.four_wheels(0.88, 1.38, -1.38, 0.35, 0.37, 0.26, 0.31, P, spokes=10, twin=False)


k.run(build)
