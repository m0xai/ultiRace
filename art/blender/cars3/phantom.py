import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import boxkit as k  # noqa: E402


def build():
    """Phantom: sleek white GT, long smoked cabin, twin tail fins, cyan glow lines."""
    P = k.palette("#f3f5fa", "#55e6ff")
    T = P["Trim"]
    cyan = k.mat("Cyan", "#55e6ff", emission="#55e6ff", strength=5.0, rough=0.2)
    parts = [k.block("sill", T, 0.86, -1.1, 1.1, 0.25, 0.42)]
    body = k.block("Body", P["Paint"], 0.98, -2.1, 2.1, 0.38, 0.7, xt=0.94, y1t=1.95, y0t=-2.05)
    parts.append(k.block("hood", P["Paint"], 0.88, 0.6, 1.95, 0.7, 0.76, xt=0.82, y1t=1.8))
    parts += k.cabin("canopy", P, 0.82, -1.25, 0.6, 0.7, 1.1, xt=0.68, y0t=-0.85, y1t=0.0, pillar=0.07, split=0.55,
                     roof_mat=P["Window"])
    parts += k.mirror(lambda sx: [k.block("fin", P["Paint"], 0.04, -2.1, -1.4, 0.7, 1.15, y0t=-2.05, y1t=-1.85, cx=sx * 0.45,
                                          bevel=0.01)])
    parts += k.mirror(lambda sx: [k.block("glow_side", cyan, 0.01, -1.9, 1.9, 0.5, 0.54, cx=sx * 0.985, bevel=0.0, subdiv=False)])
    parts.append(k.block("glow_rear", cyan, 0.75, -2.12, -2.1, 0.58, 0.62, bevel=0.0, subdiv=False))
    parts += k.front_face(P, 2.1, 0.56, 0.94, lamps=0.22, lamp_h=0.04, plate_y=2.2, plate_z=0.36)
    parts.append(k.block("bumper_f", T, 0.9, 2.04, 2.18, 0.25, 0.44))
    parts += k.rear_face(P, -2.1, 0.66, 0.94, lamps=0.3, lamp_h=0.04, plate_y=-2.2, plate_z=0.38)
    parts.append(k.block("bumper_r", T, 0.9, -2.18, -2.04, 0.25, 0.46))
    parts += k.side_mirrors(P, 0.82, 0.5, 0.86)
    parts += k.door_lines(P, 0.98, [0.62, -0.7], 0.42, 0.68)
    k.k2.join(body, parts)
    k.four_wheels(0.88, 1.35, -1.35, 0.35, 0.37, 0.32, 0.37, P, hub_mat=P["Window"])
    return body


k.run(build)
