import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k2  # noqa: E402
import carkit4 as k  # noqa: E402

# Hook: green tow truck: cab and hood (one shell), flat rear deck, yellow crane, cable and hook.
ST = [
    dict(y=0.2, zf=0.5, zb=1.04, wb=1.0, wl=0.96, zt=1.7, wt=0.93, crown=0.03),
    dict(y=0.35, zf=0.5, zb=1.04, wb=1.02, wl=0.98, zt=1.78, wt=0.94, crown=0.04),
    dict(y=1.0, zf=0.5, zb=1.04, wb=1.02, wl=0.98, zt=1.78, wt=0.94, crown=0.04),
    dict(y=1.4, zf=0.5, zb=1.03, wb=1.02, wl=0.98, zt=1.13, wt=0.96, crown=0.04),
    dict(y=1.85, zf=0.5, zb=1.0, wb=1.01, wl=0.97, zt=1.1, wt=0.95, crown=0.03),
    dict(y=2.12, zf=0.54, zb=0.94, wb=0.97, wl=0.93, zt=1.03, wt=0.9, crown=0.02),
]
CABIN = dict(ws=(1.02, 1.38), rw=None, back=0.2, b=None, a_w=0.1, c_w=0.12, b_w=0.1)


def build():
    P = k.palette("#33b852", "#f5c21b", metallic=0.4)
    Y, T = P["Accent"], P["Trim"]
    body = k.body("Body", P, ST, CABIN, nose_round=(0.96, 0.8), tail_round=(0.98, 0.9))
    wheels = [(-0.95, 1.4, 0.42), (0.95, 1.4, 0.42), (-0.95, -1.3, 0.42), (0.95, -1.3, 0.42)]
    k.arches(body, [w for w in wheels if w[1] > 0], P)
    parts = k2.standard_details(P, front=(0.62, 2.12, 0.86), rear=(0.8, -2.1, 0.9), mirror=(1.02, 1.25, 1.42),
                                grille=(0.9, 2.16, 0.7), bumper_w=1.9, bumper_z=0.6,
                                doors=dict(z0=0.56, z1=1.0, seams=[1.32, 0.3], handles=[1.12]), target=body,
                                hl=dict(half=(0.2, 0.08), slant=0.0, p=5.0), hood_back=0.16, plates=True)
    parts.append(k2.patch("rear_glass", body, (0, 0.2, 1.45), (0.6, 0.16), (0, 1, 0), P["GlassClear"], off=0.006, p=6.0, rings=2, segs=24))
    deck = [k2.rounded_box("frame", (1.7, 2.5, 0.25), (0, -0.9, 0.6), T, bevel=0.02, segs=1),
            k2.rounded_box("deck", (2.0, 2.3, 0.14), (0, -1.0, 0.86), P["Paint"], bevel=0.03, segs=2),
            k2.rounded_box("deck_plate", (1.9, 2.2, 0.02), (0, -1.0, 0.94), T, bevel=0.005, segs=1),
            k2.rounded_box("bumper_r", (2.0, 0.18, 0.2), (0, -2.2, 0.6), T, bevel=0.03, segs=2)]
    for sx in (1, -1):
        deck.append(k2.rounded_box("tail_l", (0.12, 0.04, 0.1), (sx * 0.85, -2.17, 0.84), P["TailLight"], bevel=0.01, segs=1))
        deck.append(k2.rounded_box("fender", (0.32, 1.0, 0.08), (sx * 0.98, -1.3, 0.94), T, bevel=0.03, segs=2))
    crane = [k2.rounded_box("crane_base", (0.6, 0.6, 0.35), (0, -0.85, 1.12), Y, bevel=0.05, segs=2),
             k2.tube("crane_arm", (0, -0.85, 1.25), (0, -1.95, 2.45), 0.11, Y, verts=12),
             k2.tube("crane_tip", (0, -1.95, 2.45), (0, -2.45, 2.42), 0.08, Y, verts=12),
             k2.tube("cable", (0, -2.45, 2.42), (0, -2.45, 1.72), 0.015, T, verts=8),
             k2.tube("hook", (0, -2.45, 1.75), (0, -2.55, 1.58), 0.05, P["Chrome"], verts=10)]
    beacon = [k2.blob("beacon", 0.11, (0, 0.65, 1.86), k2.glow("Amber", "#ffa21a"), scale=(1, 1, 0.8), segs=16, rings=10)]
    k2.join(body, parts + deck + crane + beacon + k.interior(P) + k.wipers(body, P))
    k.four_wheels(0.95, 1.4, -1.3, 0.42, 0.42, 0.3, 0.34, P, spokes=6, twin=False, rim_mat="Rim")


k.run(build)
