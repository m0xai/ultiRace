import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import carkit2 as k  # noqa: E402

PAINT, ACCENT = "#ffc81a", "#1a1a1e"


def build():
    """Bolt: low sporty wedge, big wing, wide rear haunches."""
    P = k.palette(PAINT, ACCENT)
    S = [  # body: low wedge, wide rear haunches
        dict(y=-2.05, w=0.86, zb=0.38, zt=0.84, p=3.4, top=0.92),
        dict(y=-1.75, w=1.01, zb=0.30, zt=0.95, p=3.8, top=0.9),
        dict(y=-1.00, w=1.02, zb=0.28, zt=0.97, p=3.8, top=0.88),
        dict(y=0.20, w=0.98, zb=0.28, zt=0.93, p=3.8, top=0.88),
        dict(y=1.10, w=0.96, zb=0.30, zt=0.80, p=3.8, top=0.9),
        dict(y=1.80, w=0.90, zb=0.33, zt=0.68, p=3.6, top=0.92),
        dict(y=2.10, w=0.74, zb=0.38, zt=0.56, p=3.0, top=0.95),
    ]
    body = k.loft("Body", S, [P["Paint"]], ring=28, round_ends=True)
    C = [  # glass canopy: raked windscreen, short roof, fastback
        dict(y=-1.15, w=0.80, zb=0.86, zt=0.95, p=3.0, top=0.9),
        dict(y=-0.70, w=0.82, zb=0.86, zt=1.30, p=3.4, top=0.72),
        dict(y=-0.05, w=0.82, zb=0.86, zt=1.40, p=3.4, top=0.7),
        dict(y=0.40, w=0.82, zb=0.86, zt=1.30, p=3.4, top=0.72),
        dict(y=0.95, w=0.80, zb=0.84, zt=0.92, p=3.0, top=0.9),
    ]
    canopy = k.cabin("Canopy", C, P, roof_from=0.88)
    wheels = [(-0.87, 1.30, 0.37), (0.87, 1.30, 0.37), (-0.87, -1.30, 0.40), (0.87, -1.30, 0.40)]
    k.cut_arches(body, wheels)
    k.finalize_body(body)
    parts = k.standard_details(P, front=(0.5, 1.96, 0.6), rear=(0.58, -2.0, 0.78), mirror=(0.88, 0.62, 0.98),
                               grille=(0.5, 2.07, 0.45), bumper_w=1.35,
                               doors=dict(x=1.0, z0=0.42, z1=0.9, seams=[0.82, -0.62], handles=[-0.4]), bumper_z=0.42)
    wing = k.rounded_box("wing", (1.9, 0.42, 0.06), (0, -1.85, 1.32), P["Accent"], bevel=0.02)
    struts = [k.rounded_box("strut", (0.06, 0.22, 0.34), (0.55, -1.8, 1.12), P["Accent"], bevel=0.01)]
    struts += k.mirror_x(struts)
    pipes = [k.disc("exhaust", 0.07, 0.25, (0.35, -2.1, 0.42), P["Chrome"], axis="Y")]
    pipes += k.mirror_x(pipes)
    k.join(body, [canopy] + parts + [wing] + struts + pipes)
    names = {"FL": wheels[0], "FR": wheels[1], "RL": wheels[2], "RR": wheels[3]}
    for nm, (x, y, r) in names.items():
        k.wheel("Wheel_" + nm, x, y, r, 0.36 if nm.startswith("F") else 0.42, P, spokes=5)


k.run(build)
