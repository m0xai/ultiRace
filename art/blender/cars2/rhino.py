import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k  # noqa: E402


def build():
    """Rhino: chunky off-road pickup, grey with orange accents, bull bar, roof lights, big tyres."""
    P = k.palette("#7d8590", "#f07a1f")
    S = [
        dict(y=-2.05, w=1.00, zb=0.55, zt=1.20, p=6, top=0.98),
        dict(y=-1.95, w=1.08, zb=0.50, zt=1.25, p=7, top=0.98),
        dict(y=0.10, w=1.10, zb=0.50, zt=1.30, p=7, top=0.98),
        dict(y=1.50, w=1.08, zb=0.52, zt=1.28, p=7, top=0.97),
        dict(y=2.05, w=1.00, zb=0.58, zt=1.18, p=6, top=0.96),
    ]
    body = k.loft("Body", S, [k.palette("#7d8590", "#f07a1f")["Paint"]], ring=24)
    C = [
        dict(y=-0.25, w=0.98, zb=1.2, zt=1.30, p=6, top=0.95),
        dict(y=-0.15, w=1.00, zb=1.2, zt=1.95, p=7, top=0.9),
        dict(y=0.90, w=1.00, zb=1.2, zt=1.95, p=7, top=0.9),
        dict(y=1.35, w=0.98, zb=1.2, zt=1.32, p=6, top=0.95),
    ]
    cab = k.cabin("Cab", C, P, roof_from=0.86)
    wheels = k.four_wheels(1.0, 1.35, -1.35, 0.56, 0.56, 0.48, 0.48, P, rim="Accent", spokes=6)
    k.cut_arches(body, wheels, width=0.8)
    k.finalize_body(body)
    parts = k.standard_details(P, front=(0.62, 2.04, 0.98), rear=(0.75, -2.07, 1.0), mirror=(1.06, 1.15, 1.45),
                               grille=(0.7, 2.08, 0.82), bumper_w=1.9, bumper_z=0.64)
    bed = k.rounded_box("bed", (1.9, 1.7, 0.08), (0, -1.1, 1.26), P["Trim"], bevel=0.03)
    stripe = k.rounded_box("stripe", (2.22, 1.3, 0.1), (0, 0.6, 0.95), P["Accent"], bevel=0.03)
    bar = [k.tube("bar_top", (-0.85, 2.25, 1.05), (0.85, 2.25, 1.05), 0.07, P["Chrome"]),
           k.tube("bar_l", (-0.6, 2.2, 0.45), (-0.6, 2.25, 1.05), 0.06, P["Chrome"]),
           k.tube("bar_r", (0.6, 2.2, 0.45), (0.6, 2.25, 1.05), 0.06, P["Chrome"])]
    lights = [k.blob("roof_light", 0.09, (x, 0.95, 2.0), k.glow("Amber", "#ffb020"), scale=(1, 0.8, 0.7)) for x in (-0.45, -0.15, 0.15, 0.45)]
    k.join(body, [cab, bed, stripe] + parts + bar + lights)


k.run(build)
