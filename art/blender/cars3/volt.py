import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import boxkit as k  # noqa: E402


def build():
    """Volt: angular purple coupe, yellow lightning stripes, two antennas with glowing tips."""
    P = k.palette("#8e5cf0", "#ffe14a")
    T, A = P["Trim"], P["Accent"]
    tip = k.mat("Tip", "#ffe14a", emission="#ffe14a", strength=6.0, rough=0.2)
    parts = [k.block("sill", T, 0.88, -1.05, 1.05, 0.27, 0.46)]
    body = k.block("Body", P["Paint"], 0.98, -2.0, 2.02, 0.42, 0.8, xt=0.9, y1t=1.8, y0t=-1.9)
    parts.append(k.block("nose", P["Paint"], 0.9, 1.1, 1.85, 0.8, 0.86, xt=0.8, y1t=1.6))
    parts += k.cabin("canopy", P, 0.82, -1.15, 0.85, 0.8, 1.26, xt=0.7, y0t=-0.7, y1t=0.15, pillar=0.08, split=0.5)
    parts.append(k.block("spoiler", P["Paint"], 0.9, -2.0, -1.75, 0.8, 0.95, y0t=-1.95))
    # lightning stripes (zig-zag of short bars on each flank)
    for (y0, y1, z0, z1) in ((0.9, 1.5, 0.66, 0.72), (0.3, 0.95, 0.56, 0.62), (-0.4, 0.35, 0.64, 0.7), (-1.1, -0.35, 0.54, 0.6)):
        parts += k.mirror(lambda sx, a=(y0, y1, z0, z1): [k.block("bolt", A, 0.012, a[0], a[1], a[2], a[3], cx=sx * 0.975,
                                                                  bevel=0.0, subdiv=False)])
    # antennas
    parts += k.mirror(lambda sx: [k.beam("ant", T, (sx * 0.55, -1.6, 0.92), (sx * 0.62, -1.78, 2.3), thick=0.05),
                                  k.block("ant_tip", tip, 0.08, -1.86, -1.7, 2.28, 2.44, cx=sx * 0.62, bevel=0.015, subdiv=False)])
    parts += k.front_face(P, 2.02, 0.62, 0.96, lamps=0.2, lamp_h=0.05, plate_y=2.13, plate_z=0.4)
    parts.append(k.block("bumper_f", T, 0.92, 1.95, 2.12, 0.27, 0.5))
    parts += k.rear_face(P, -2.0, 0.7, 0.96, lamps=0.25, lamp_h=0.05, plate_y=-2.12, plate_z=0.42)
    parts.append(k.block("bumper_r", T, 0.92, -2.12, -1.95, 0.27, 0.52))
    parts += k.side_mirrors(P, 0.82, 0.7, 0.95)
    parts += k.door_lines(P, 0.98, [0.8, -0.75], 0.46, 0.78)
    k.k2.join(body, parts)
    k.four_wheels(0.9, 1.3, -1.3, 0.37, 0.39, 0.33, 0.38, P, hub_mat=A)
    return body


k.run(build)
