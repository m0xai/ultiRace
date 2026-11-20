import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import boxkit as k  # noqa: E402


def build():
    """Goo: lime tanker: stubby cab, octagonal tank with dark bands and goo drips."""
    P = k.palette("#9be22e", "#3a7d1e")
    T, A = P["Trim"], P["Accent"]
    parts = [k.block("frame", T, 0.92, -2.05, 2.05, 0.42, 0.85)]
    body = k.block("Body", P["Paint"], 0.98, 0.85, 2.15, 0.8, 1.25, xt=0.96, y1t=2.08)
    parts += k.cabin("cab", P, 0.96, 0.85, 2.0, 1.25, 1.75, xt=0.9, y1t=1.75, pillar=0.09, split=0.5, side_glass=True)
    parts.append(k.octo("tank", P["Paint"], (0, -0.6, 1.6), 0.82, 2.7))
    parts.append(k.octo("tank_cap_r", A, (0, -1.98, 1.6), 0.7, 0.08, bevel=0.01))
    for y in (-1.3, -0.4, 0.45):
        parts.append(k.octo("band", A, (0, y, 1.6), 0.86, 0.1, bevel=0.01))
    parts.append(k.block("hatch", A, 0.22, -0.9, -0.4, 2.38, 2.5, bevel=0.015, subdiv=False))
    for (x, y, z, s) in ((0.55, -0.2, 2.02, 0.12), (-0.62, -1.2, 1.95, 0.1), (0.7, -1.5, 1.6, 0.08)):
        parts.append(k.block("drip", P["Paint"], s, y - s, y + s, z - s * 1.6, z + s, cx=x, bevel=0.02, subdiv=False))
    parts += k.front_face(P, 2.15, 1.0, 0.96, lamps=0.15, lamp_h=0.07, plate_y=2.26, plate_z=0.62)
    parts.append(k.block("bumper_f", T, 0.98, 2.12, 2.26, 0.45, 0.72))
    parts += k.rear_face(P, -2.05, 0.66, 0.92, lamps=0.14, lamp_h=0.07, plate_y=-2.18, plate_z=0.5)
    parts.append(k.block("bumper_r", T, 0.95, -2.18, -2.03, 0.42, 0.62))
    parts += k.side_mirrors(P, 0.96, 1.85, 1.45, T)
    k.k2.join(body, parts)
    k.four_wheels(0.94, 1.4, -1.25, 0.4, 0.42, 0.38, 0.4, P, hub_mat=A)
    return body


k.run(build)
