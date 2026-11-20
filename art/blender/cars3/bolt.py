import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import boxkit as k  # noqa: E402


def build():
    """Bolt: low, wide boxy sports car; long hood, short cabin set back, big rear wing."""
    P = k.palette("#ffc81a", "#1d1e22")
    T = P["Trim"]
    parts = []
    # chassis: dark sills between the wheels, bumpers at both ends
    parts.append(k.block("sill", T, 0.9, -1.0, 1.0, 0.26, 0.46))
    parts.append(k.block("bumper_f", T, 0.95, 1.9, 2.12, 0.26, 0.5))
    parts.append(k.block("bumper_r", T, 0.95, -2.12, -1.9, 0.26, 0.52))
    # main body: wedge (front lower than rear), slight tumblehome
    body = k.block("Body", P["Paint"], 1.0, -2.0, 2.02, 0.42, 0.74, xt=0.97, y0t=-1.98, y1t=1.9)
    parts.append(k.block("hood", P["Paint"], 0.9, 0.35, 1.9, 0.74, 0.8, xt=0.86, y1t=1.78))
    parts.append(k.block("deck", P["Paint"], 0.94, -1.98, -0.95, 0.74, 0.86, y0t=-1.95))
    # low cabin: strongly raked screen and fastback rear
    parts += k.cabin("cabin", P, 0.84, -1.0, 0.4, 0.74, 1.14, xt=0.7, y0t=-0.55, y1t=-0.15, pillar=0.075, split=0.55)
    # wing on two struts
    parts.append(k.block("wing", P["Accent"], 0.95, -2.02, -1.66, 1.3, 1.38, bevel=0.015))
    parts.append(k.block("wing_end", P["Accent"], 0.03, -2.04, -1.62, 1.12, 1.45, cx=0.97, bevel=0.01, subdiv=False))
    parts.append(k.block("wing_end", P["Accent"], 0.03, -2.04, -1.62, 1.12, 1.45, cx=-0.97, bevel=0.01, subdiv=False))
    parts += k.mirror(lambda sx: [k.block("strut", P["Accent"], 0.035, -1.9, -1.76, 0.88, 1.3, cx=sx * 0.55, bevel=0.01,
                                          subdiv=False)])
    # side intakes and a stripe
    parts += k.mirror(lambda sx: [k.block("intake", P["Dark"], 0.012, -1.0, -0.62, 0.5, 0.68, cx=sx * 1.0, bevel=0.0, subdiv=False)])
    parts.append(k.block("stripe", P["Accent"], 0.18, 0.4, 1.76, 0.8, 0.812, cx=0, bevel=0.0, subdiv=False))
    parts += k.door_lines(P, 1.0, [0.5, -0.95], 0.46, 0.76)
    parts += k.side_mirrors(P, 0.84, 0.3, 0.88)
    parts += k.front_face(P, 2.02, 0.64, 0.98, lamps=0.17, lamp_h=0.06, plate_y=2.12, plate_z=0.38)
    parts += k.rear_face(P, -2.0, 0.68, 0.98, lamps=0.2, lamp_h=0.06, plate_y=-2.12, plate_z=0.4)
    parts += k.mirror(lambda sx: [k.block("exhaust", P["Chrome"], 0.06, -2.2, -2.1, 0.3, 0.4, cx=sx * 0.42, bevel=0.01,
                                          subdiv=False)])
    k.k2.join(body, parts)
    k.four_wheels(0.92, 1.3, -1.3, 0.36, 0.38, 0.34, 0.4, P)
    return body


k.run(build)
