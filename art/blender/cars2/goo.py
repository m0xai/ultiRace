import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k  # noqa: E402


def build():
    """Goo: lime tanker: stubby cab, big glossy tank with drips, chunky tyres."""
    P = k.palette("#9be22e", "#3a7d1e")
    S = [
        dict(y=-2.05, w=0.92, zb=0.42, zt=0.85, p=5, top=0.98),
        dict(y=2.05, w=0.92, zb=0.42, zt=0.85, p=5, top=0.98),
    ]
    frame = k.loft("Body", S, [P["Trim"]], ring=16)
    CAB = [
        dict(y=0.85, w=0.92, zb=0.80, zt=1.0, p=5, top=0.95),
        dict(y=0.95, w=0.95, zb=0.80, zt=1.75, p=5, top=0.86),
        dict(y=1.85, w=0.95, zb=0.80, zt=1.68, p=5, top=0.86),
        dict(y=2.15, w=0.92, zb=0.80, zt=1.0, p=4, top=0.95),
    ]
    cab_paint = k.loft("CabPaint", CAB, [P["Paint"], P["Glass"]], ring=24)
    for f in cab_paint.data.polygons:
        if 1.25 < f.center.z < 1.62 and abs(f.normal.z) < 0.9:
            f.material_index = 1
    wheels = k.four_wheels(0.92, 1.4, -1.25, 0.40, 0.40, 0.42, 0.42, P, rim="Accent", spokes=5)
    k.cut_arches(frame, wheels)
    k.finalize_body(frame)
    tank = k.lathe("tank", [(0.0, -2.0), (0.62, -1.98), (0.82, -1.7), (0.86, -0.5), (0.86, 0.3), (0.80, 0.62), (0.0, 0.66)],
                   [0] * 6, [P["Paint"]], segments=28)
    tank.rotation_euler = (0, 0, math.pi / 2)
    tank.location = (0, 0, 1.55)
    bands = [k.disc("band", 0.9, 0.08, (0, y, 1.55), P["Accent"], axis="Y", verts=28) for y in (-1.3, -0.4)]
    drips = [k.blob("drip", r, (x, y, z), P["Paint"]) for (x, y, z, r) in ((0.5, -0.9, 2.3, 0.16), (-0.3, -1.5, 2.25, 0.12), (0.1, -0.2, 2.38, 0.1))]
    parts = k.standard_details(P, front=(0.55, 2.13, 1.05), rear=(0.7, -2.06, 0.7), mirror=(0.99, 1.7, 1.4), grille=(0.6, 2.17, 0.95), bumper_w=1.7, bumper_z=0.55, doors=dict(x=0.96, z0=0.86, z1=1.6, seams=[1.0], handles=[1.18]))
    k.join(frame, [cab_paint, tank] + bands + drips + parts)


k.run(build)
