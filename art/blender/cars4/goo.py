import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k2  # noqa: E402
import carkit4 as k  # noqa: E402

# Goo: lime tanker: cab-over truck cab (one shell) on a dark frame, big glossy tank with bands.
ST = [
    dict(y=0.85, zf=0.82, zb=1.25, wb=0.98, wl=0.95, zt=1.72, wt=0.9, crown=0.03),
    dict(y=1.0, zf=0.8, zb=1.25, wb=1.0, wl=0.97, zt=1.78, wt=0.92, crown=0.04),
    dict(y=1.75, zf=0.8, zb=1.24, wb=1.0, wl=0.97, zt=1.76, wt=0.92, crown=0.04),
    dict(y=2.05, zf=0.8, zb=1.18, wb=0.99, wl=0.96, zt=1.32, wt=0.95, crown=0.03),
    dict(y=2.2, zf=0.82, zb=1.08, wb=0.96, wl=0.93, zt=1.14, wt=0.92, crown=0.02),
]
CABIN = dict(ws=(1.78, 2.04), rw=None, back=0.85, b=None, a_w=0.08, c_w=0.15, b_w=0.1)


def build():
    P = k.palette("#9be22e", "#3a7d1e", metallic=0.3)
    A, T = P["Accent"], P["Trim"]
    body = k.body("Body", P, ST, CABIN, nose_round=(0.97, 0.85), tail_round=(0.98, 0.9))
    k2.finalize_body(body)
    parts = k2.standard_details(P, front=(0.62, 2.2, 1.0), rear=(0.8, -2.05, 0.75), mirror=(1.0, 1.85, 1.5),
                                grille=(0.95, 2.24, 0.98), bumper_w=1.9, bumper_z=0.88,
                                doors=dict(z0=0.9, z1=1.24, seams=[1.0], handles=[1.2]), target=body,
                                hl=dict(half=(0.18, 0.07), slant=0.0, p=5.0), hood_back=0.08)
    frame = [k2.rounded_box("frame", (1.7, 4.2, 0.35), (0, -0.05, 0.66), T, bevel=0.02, segs=1),
             k2.rounded_box("bumper_f", (2.0, 0.2, 0.28), (0, 2.25, 0.72), T, bevel=0.03, segs=2),
             k2.rounded_box("bumper_r", (1.9, 0.18, 0.2), (0, -2.15, 0.6), T, bevel=0.03, segs=2)]
    for (y, r) in ((1.4, 0.4), (-1.25, 0.42)):
        for sx in (1, -1):
            frame.append(k2.rounded_box("fender", (0.34, r * 2.5, 0.08), (sx * 0.95, y, r * 2.15), T, bevel=0.03, segs=2))
    for sx in (1, -1):
        frame.append(k2.rounded_box("tail_l", (0.16, 0.04, 0.1), (sx * 0.78, -2.17, 0.74), P["TailLight"], bevel=0.01, segs=1))
    tank = k2.lathe("tank", [(0.0, -2.05), (0.55, -2.03), (0.78, -1.9), (0.86, -1.6), (0.88, -0.5), (0.86, 0.4), (0.78, 0.66),
                             (0.5, 0.76), (0.0, 0.78)], [0] * 8, [P["Paint"]], segments=40)
    tank.rotation_euler = (0, 0, math.pi / 2)
    tank.location = (0, 0, 1.68)
    bands = [k2.disc("band", 0.9, 0.08, (0, y, 1.68), A, axis="Y", verts=40) for y in (-1.4, -0.55, 0.3)]
    hatch = [k2.disc("hatch", 0.22, 0.12, (0, -0.6, 2.56), A, axis="Z", verts=24),
             k2.rounded_box("walkway", (0.4, 1.8, 0.04), (0, -0.6, 2.56), T, bevel=0.01, segs=1)]
    drips = [k2.blob("drip", r, (x, y, z), P["Paint"], scale=(1, 1, 1.5), segs=14, rings=10)
             for (x, y, z, r) in ((0.6, -0.2, 2.22, 0.1), (-0.66, -1.2, 2.12, 0.08), (0.78, -1.5, 1.85, 0.06))]
    k2.join(body, parts + frame + [tank] + bands + hatch + drips + k.interior(P) + k.wipers(body, P) + (k.hi_extras(body, P) if k.DETAIL >= 2 else []))
    k.four_wheels(0.94, 1.4, -1.25, 0.4, 0.42, 0.32, 0.36, P, spokes=8, twin=False, rim_mat="Rim")


k.run(build)
