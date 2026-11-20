import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import boxkit as k  # noqa: E402


def build():
    """Twister: teal dune buggy: small tub, roll cage, seat, big caged fan at the back."""
    P = k.palette("#18b8a8", "#ff6b3d")
    T, A = P["Trim"], P["Accent"]
    parts = [k.block("floor", T, 0.62, -1.45, 1.75, 0.42, 0.6)]
    body = k.block("Body", P["Paint"], 0.72, -1.4, 1.9, 0.55, 0.95, xt=0.66, y1t=1.75, y0t=-1.3)
    parts.append(k.block("nose", P["Paint"], 0.6, 1.0, 1.9, 0.95, 1.02, xt=0.5, y1t=1.75))
    parts.append(k.block("seat", A, 0.32, -0.6, 0.05, 0.95, 1.55, y0t=-0.6, y1t=-0.35, bevel=0.04))
    c = [(-0.6, -0.55, 0.95), (0.6, -0.55, 0.95), (-0.45, -0.25, 1.85), (0.45, -0.25, 1.85), (-0.55, 0.75, 0.95), (0.55, 0.75, 0.95)]
    for a, b in ((0, 2), (1, 3), (2, 3), (2, 4), (3, 5)):
        parts.append(k.beam("cage", T, c[a], c[b], thick=0.08))
    parts += k.mirror(lambda sx: [k.beam("fan_strut", T, (sx * 0.5, -1.0, 0.95), (sx * 0.62, -1.62, 1.95), thick=0.07)])
    parts += k.ring("fan_ring", A, (0, -1.68, 1.4), 0.98, thick=0.12, depth=0.16)
    for i in range(3):
        import math
        a = i * math.pi / 3
        parts.append(k.beam("blade", T, (-0.85 * math.cos(a), -1.68, 1.4 - 0.85 * math.sin(a)),
                            (0.85 * math.cos(a), -1.68, 1.4 + 0.85 * math.sin(a)), thick=0.04, width=0.22))
    parts.append(k.octo("fan_hub", P["Chrome"], (0, -1.68, 1.4), 0.16, 0.22))
    parts += k.front_face(P, 1.9, 0.8, 0.66, lamps=0.12, lamp_h=0.07, grille=False, plate_y=2.0, plate_z=0.55)
    parts.append(k.block("bumper_f", T, 0.72, 1.88, 2.0, 0.42, 0.62))
    parts += k.rear_face(P, -1.4, 0.82, 0.68, lamps=0.1, lamp_h=0.06, plate=False)
    parts += k.side_mirrors(P, 0.66, 0.55, 1.05, T)
    k.k2.join(body, parts)
    k.four_wheels(1.02, 1.35, -1.25, 0.42, 0.48, 0.42, 0.5, P, hub_mat=A)
    return body


k.run(build)
