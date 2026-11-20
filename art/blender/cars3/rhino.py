import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import boxkit as k  # noqa: E402


def build():
    """Rhino: chunky off-road pickup, grey with orange accents, push bar, roof lights, big tyres."""
    P = k.palette("#7d8590", "#f07a1f")
    T, A = P["Trim"], P["Accent"]
    parts = [k.block("frame", T, 0.95, -1.95, 1.95, 0.45, 0.66)]
    body = k.block("Body", P["Paint"], 1.08, 0.25, 2.05, 0.62, 1.2, xt=1.04, y1t=1.98)  # cab + hood section
    parts.append(k.block("hood", P["Paint"], 1.0, 1.0, 1.98, 1.2, 1.28, xt=0.96))
    parts += k.cabin("cab", P, 1.04, -0.35, 1.0, 1.2, 1.92, xt=0.98, y1t=0.88, pillar=0.09, split=0.5)
    # bed: floor + walls, orange top rails
    parts.append(k.block("bed_floor", T, 1.04, -2.05, -0.35, 0.62, 0.9))
    parts += k.mirror(lambda sx: [k.block("bed_wall", P["Paint"], 0.07, -2.05, -0.35, 0.9, 1.32, cx=sx * 1.0)])
    parts.append(k.block("tailgate", P["Paint"], 1.04, -2.08, -1.94, 0.62, 1.3))
    parts += k.mirror(lambda sx: [k.block("rail", A, 0.08, -2.05, -0.35, 1.32, 1.38, cx=sx * 1.0, subdiv=False)])
    # fender flares and orange stripe
    for y in (1.35, -1.35):
        parts += k.mirror(lambda sx, y=y: [k.block("flare", T, 0.1, y - 0.62, y + 0.62, 0.86, 1.02, cx=sx * 1.12)])
    parts += k.mirror(lambda sx: [k.block("stripe", A, 0.012, -0.3, 2.0, 0.95, 1.08, cx=sx * 1.085, bevel=0.0, subdiv=False)])
    # front: big grille, push bar, lamps; rear lamps
    parts += k.front_face(P, 2.05, 0.98, 1.06, lamps=0.18, lamp_h=0.09, plate_y=2.24, plate_z=0.62)
    parts.append(k.block("bumper_f", T, 1.05, 2.04, 2.22, 0.5, 0.74))
    parts.append(k.beam("bar_top", P["Chrome"], (-0.85, 2.32, 0.86), (0.85, 2.32, 0.86), thick=0.1))
    parts += k.mirror(lambda sx: [k.beam("bar_leg", P["Chrome"], (sx * 0.6, 2.2, 0.48), (sx * 0.6, 2.32, 0.86), thick=0.09)])
    parts += k.rear_face(P, -2.08, 1.0, 1.0, lamps=0.12, lamp_h=0.12, lamp_x=0.82, plate_y=-2.22, plate_z=0.62)
    parts.append(k.block("bumper_r", T, 1.05, -2.22, -2.05, 0.5, 0.72))
    # roof light bar
    parts.append(k.block("lightbar", T, 0.7, 0.2, 0.42, 1.92, 2.0, subdiv=False))
    for x in (-0.48, -0.16, 0.16, 0.48):
        parts.append(k.block("roof_light", P["Amber"], 0.1, 0.42, 0.46, 1.93, 1.99, cx=x, bevel=0.005, subdiv=False))
    parts += k.side_mirrors(P, 1.04, 0.95, 1.45, T)
    parts += k.door_lines(P, 1.08, [0.95, 0.3], 0.66, 1.18)
    k.k2.join(body, parts)
    k.four_wheels(1.06, 1.35, -1.35, 0.49, 0.48, 0.46, 0.46, P, hub_mat=A)
    return body


k.run(build)
