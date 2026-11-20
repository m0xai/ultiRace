import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import boxkit as k  # noqa: E402


def build():
    """Glacier: compact ice-blue hatchback, white roof and skirts, ice-crystal roof fins."""
    P = k.palette("#6fd0f5", "#f2f8ff")
    T, A = P["Trim"], P["Accent"]
    parts = [k.block("sill", T, 0.9, -1.05, 1.05, 0.3, 0.5)]
    body = k.block("Body", P["Paint"], 1.0, -1.92, 1.95, 0.45, 0.92, xt=0.97, y1t=1.75, y0t=-1.88)
    parts += k.cabin("cabin", P, 0.94, -1.75, 0.75, 0.92, 1.5, xt=0.86, y0t=-1.65, y1t=0.25, pillar=0.09, split=0.55,
                     roof_mat=A)
    parts += k.mirror(lambda sx: [k.block("skirt", A, 0.05, -1.0, 1.0, 0.42, 0.56, cx=sx * 1.0)])
    # ice crystals on the roof
    parts.append(k.block("crystal", A, 0.06, -1.2, -0.5, 1.5, 1.85, y0t=-1.05, y1t=-0.85, bevel=0.01))
    parts += k.mirror(lambda sx: [k.block("crystal", P["Paint"], 0.05, -1.35, -0.85, 1.5, 1.72, y0t=-1.2, y1t=-1.05,
                                          cx=sx * 0.35, bevel=0.01)])
    parts += k.front_face(P, 1.95, 0.72, 0.96, lamps=0.16, lamp_h=0.07, plate_y=2.08, plate_z=0.42)
    parts.append(k.block("bumper_f", T, 0.95, 1.92, 2.06, 0.32, 0.55))
    parts += k.rear_face(P, -1.92, 0.78, 0.96, lamps=0.15, lamp_h=0.09, plate_y=-2.05, plate_z=0.45)
    parts.append(k.block("bumper_r", T, 0.95, -2.04, -1.9, 0.32, 0.56))
    parts += k.side_mirrors(P, 0.94, 0.55, 1.05, A)
    parts += k.door_lines(P, 1.0, [0.65, -0.55], 0.5, 0.9)
    k.k2.join(body, parts)
    k.four_wheels(0.9, 1.25, -1.25, 0.37, 0.37, 0.34, 0.36, P, hub_mat=A)
    return body


k.run(build)
