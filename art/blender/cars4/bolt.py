import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k2  # noqa: E402
import carkit4 as k  # noqa: E402

# Bolt: low, wide sports coupe; long hood, cab-rear greenhouse, fastback, big wing.
ST = [
    dict(y=-2.2, zf=0.34, zb=0.84, wb=0.95, wl=0.9, zt=0.9, wt=0.86, crown=0.02),
    dict(y=-1.85, zf=0.29, zb=0.86, wb=0.99, wl=0.94, zt=0.93, wt=0.86, crown=0.03),
    dict(y=-1.3, zf=0.27, zb=0.86, wb=1.0, wl=0.95, zt=0.97, wt=0.84, crown=0.03),
    dict(y=-0.55, zf=0.27, zb=0.84, wb=0.99, wl=0.95, zt=1.22, wt=0.68, crown=0.04),
    dict(y=0.25, zf=0.27, zb=0.82, wb=0.98, wl=0.94, zt=1.25, wt=0.7, crown=0.04),
    dict(y=1.05, zf=0.27, zb=0.79, wb=0.98, wl=0.94, zt=0.88, wt=0.84, crown=0.05),
    dict(y=1.75, zf=0.29, zb=0.74, wb=0.96, wl=0.92, zt=0.79, wt=0.85, crown=0.05),
    dict(y=2.2, zf=0.35, zb=0.62, wb=0.9, wl=0.84, zt=0.66, wt=0.78, crown=0.03),
]
CABIN = dict(ws=(1.02, 0.28), rw=(-1.28, -0.52), b=-0.15, a_w=0.1, c_w=0.12, b_w=0.1)
# windscreen runs from the cowl (y 1.02) up to the roof front (0.28); rear window from the
# deck (−1.28) up to the roof rear (−0.52)
CABIN = dict(ws=(0.28, 1.02), rw=(-1.28, -0.52), b=-0.15, a_w=0.1, c_w=0.12, b_w=0.1)


def build():
    P = k.palette("#ffc21a", "#1d1e22")
    body = k.body("Body", P, ST, CABIN, nose_round=(0.94, 0.75), tail_round=(0.97, 0.88))
    wheels = [(-0.9, 1.32, 0.36), (0.9, 1.32, 0.36), (-0.9, -1.32, 0.38), (0.9, -1.32, 0.38)]
    k.arches(body, wheels, P)
    parts = k2.standard_details(P, front=(0.62, 2.2, 0.6), rear=(0.66, -2.2, 0.76), mirror=(0.9, 0.62, 0.95),
                                grille=(0.7, 2.24, 0.42), bumper_w=1.5, bumper_z=0.4,
                                doors=dict(z0=0.4, z1=0.82, seams=[0.95, -0.55], handles=[-0.35]), target=body,
                                hl=dict(half=(0.25, 0.065), slant=0.35), tl=dict(half=(0.3, 0.06), slant=0.15), hood_back=0.16)
    wing = [k2.rounded_box("wing", (1.85, 0.36, 0.05), (0, -1.95, 1.22), P["Accent"], bevel=0.02, segs=2),
            k2.rounded_box("wing_l", (0.04, 0.42, 0.2), (0.93, -1.95, 1.18), P["Accent"], bevel=0.01, segs=1),
            k2.rounded_box("wing_r", (0.04, 0.42, 0.2), (-0.93, -1.95, 1.18), P["Accent"], bevel=0.01, segs=1)]
    wing += [k2.rounded_box("strut", (0.04, 0.18, 0.3), (sx * 0.55, -1.9, 1.02), P["Accent"], bevel=0.01, segs=1) for sx in (1, -1)]
    pipes = k.exhausts(P, [((sx * 0.38, -2.25, 0.34), (0, -1, 0.02), 0.058, 0.3, "round") for sx in (1, -1)])
    inside = k.interior(P)
    wip = k.wipers(body, P)
    hi = k.hi_extras(body, P) if k.DETAIL >= 2 else []
    k2.join(body, parts + wing + pipes + inside + wip + hi)
    k.four_wheels(0.9, 1.32, -1.32, 0.36, 0.38, 0.27, 0.31, P, spokes=5, twin=True)


k.run(build)
