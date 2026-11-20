import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import boxkit as k  # noqa: E402


def build():
    """Hook: green tow truck: cab up front, flat rear deck, yellow crane with cable and hook."""
    P = k.palette("#33b852", "#f5c21b")
    T, Y = P["Trim"], P["Accent"]
    parts = [k.block("frame", T, 0.92, -2.05, 2.0, 0.36, 0.56)]
    body = k.block("Body", P["Paint"], 1.02, 0.25, 2.05, 0.52, 1.02, xt=1.0, y1t=1.98)
    parts.append(k.block("hood", P["Paint"], 0.95, 1.15, 1.98, 1.02, 1.1, xt=0.9))
    parts += k.cabin("cab", P, 1.0, 0.25, 1.15, 1.02, 1.78, xt=0.94, y1t=1.0, pillar=0.09, split=0.5)
    parts.append(k.block("deck", P["Paint"], 1.0, -2.05, 0.2, 0.52, 0.88))
    parts.append(k.block("deck_top", T, 0.98, -2.0, 0.15, 0.88, 0.94, subdiv=False))
    parts += k.mirror(lambda sx: [k.block("stripe", Y, 0.012, -2.0, 2.0, 0.62, 0.7, cx=sx * 1.02, bevel=0.0, subdiv=False)])
    # crane: base, arm, tip, cable, hook
    parts.append(k.block("crane_base", Y, 0.32, -1.25, -0.6, 0.94, 1.35))
    parts.append(k.beam("crane_arm", Y, (0, -0.95, 1.3), (0, -2.0, 2.45), thick=0.2, width=0.22))
    parts.append(k.beam("crane_tip", Y, (0, -2.0, 2.45), (0, -2.45, 2.42), thick=0.16))
    parts.append(k.beam("cable", T, (0, -2.45, 2.38), (0, -2.45, 1.72), thick=0.04))
    parts.append(k.block("hook", P["Chrome"], 0.06, -2.55, -2.35, 1.55, 1.74, bevel=0.01, subdiv=False))
    parts.append(k.block("hook_tip", P["Chrome"], 0.05, -2.6, -2.5, 1.55, 1.64, bevel=0.01, subdiv=False))
    # beacon on the cab
    parts.append(k.block("beacon_base", T, 0.16, 0.55, 0.85, 1.78, 1.84, subdiv=False))
    parts.append(k.block("beacon", P["Amber"], 0.11, 0.6, 0.8, 1.84, 1.98, bevel=0.02, subdiv=False))
    parts += k.front_face(P, 2.05, 0.82, 0.98, lamps=0.16, lamp_h=0.08, plate_y=2.18, plate_z=0.48)
    parts.append(k.block("bumper_f", T, 1.0, 2.02, 2.16, 0.36, 0.6))
    parts += k.rear_face(P, -2.05, 0.74, 0.98, lamps=0.14, lamp_h=0.08, plate_y=-2.16, plate_z=0.48)
    parts.append(k.block("bumper_r", T, 1.0, -2.16, -2.02, 0.36, 0.6))
    parts += k.side_mirrors(P, 1.0, 1.1, 1.38, T)
    parts += k.door_lines(P, 1.02, [1.12, 0.3], 0.56, 1.0)
    k.k2.join(body, parts)
    k.four_wheels(0.96, 1.3, -1.3, 0.4, 0.4, 0.36, 0.38, P, hub_mat=Y)
    return body


k.run(build)
