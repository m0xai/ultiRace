"""Buildings kit (graphics pass 5): farmhouse, barn, log cabin at real size (metres), front facing
−Y (Godot: +Z, toward the road). Each has a light "_lod1" and a separate window object
("<Name>Glow", "<Name>Glow_lod1") that the game lights at night or in snow.

Usage: blender --background --factory-startup --python art/blender/env/buildings.py -- <out.glb> [preview.png]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import envlib as E  # noqa: E402
from envlib import Builder, mul  # noqa: E402

WHITE = (0.93, 0.92, 0.88)
GLASS = (0.55, 0.62, 0.7)


def window(body, glow, x, y, z, w, h, frame=WHITE, shutters=None, face=-1):
    """Window on a wall facing ±Y (face −1 = front). Frame, sill, glass (glow object), shutters."""
    fy = y + face * 0.06
    glow.box((x, fy + face * 0.01, z), (w / 2, 0.02, h / 2), GLASS, shade=False)
    for (cx, cz, hx, hz) in ((x, z + h / 2 + 0.06, w / 2 + 0.1, 0.07), (x, z - h / 2 - 0.06, w / 2 + 0.14, 0.08),
                             (x - w / 2 - 0.05, z, 0.06, h / 2), (x + w / 2 + 0.05, z, 0.06, h / 2), (x, z, 0.03, h / 2)):
        body.box((cx, fy + face * 0.03, cz), (hx, 0.05, hz), frame)
    if shutters:
        for sx in (-1, 1):
            body.box((x + sx * (w / 2 + 0.33), fy + face * 0.02, z), (0.22, 0.04, h / 2 + 0.05), shutters)


def side_window(body, glow, x, y, z, w, h, face=1):
    """Window on a wall facing ±X."""
    fx = x + face * 0.06
    glow.box((fx + face * 0.01, y, z), (0.02, w / 2, h / 2), GLASS, shade=False)
    body.box((fx + face * 0.03, y, z + h / 2 + 0.06), (0.05, w / 2 + 0.1, 0.07), WHITE)
    body.box((fx + face * 0.03, y, z - h / 2 - 0.06), (0.05, w / 2 + 0.14, 0.08), WHITE)


def farmhouse(lod):
    b, g = Builder(), Builder()
    W, D, H = 5.0, 4.0, 4.4
    siding = (0.93, 0.88, 0.76)
    roof = (0.48, 0.2, 0.15)
    b.box((0, 0, 0.3), (W + 0.25, D + 0.25, 0.3), (0.55, 0.53, 0.5))  # stone foundation
    b.box((0, 0, 0.6 + H / 2), (W, D, H / 2), siding)
    if lod == 0:
        for k in range(1, 11):  # siding boards: thin shadow lines
            z = 0.6 + k * H / 11
            b.box((0, -D - 0.015, z), (W, 0.015, 0.02), mul(siding, 0.8))
            b.box((0, D + 0.015, z), (W, 0.015, 0.02), mul(siding, 0.8))
        for sx in (-1, 1):
            for sy in (-1, 1):
                b.box((sx * W, sy * D, 0.6 + H / 2), (0.14, 0.14, H / 2), WHITE)  # corner boards
    b.prism_roof(-W - 0.5, W + 0.5, -D - 0.6, D + 0.6, 0.6 + H, 3.0, roof, gable=siding)
    if lod == 0:
        for k in range(6):  # shingle courses on the front slope
            t = (k + 0.5) / 6
            yy = -D - 0.6 + t * (D + 0.6)
            zz = 0.6 + H + t * 3.0 + 0.17
            b.box((0, yy, zz), (W + 0.5, 0.05, 0.025), mul(roof, 0.75))
        b.box((2.6, 1.2, 0.6 + H + 2.4), (0.45, 0.45, 1.3), (0.55, 0.27, 0.2))  # chimney
        b.box((2.6, 1.2, 0.6 + H + 3.75), (0.55, 0.55, 0.08), (0.4, 0.4, 0.4))
        # porch: floor, roof on posts, steps, door
        b.box((0, -D - 1.2, 0.55), (2.2, 1.2, 0.12), (0.55, 0.42, 0.3))
        for sx in (-1, 1):
            b.box((sx * 2.0, -D - 2.2, 2.0), (0.1, 0.1, 1.4), WHITE)
        b.box((0, -D - 1.25, 3.45), (2.4, 1.35, 0.1), mul(roof, 0.9))
        for k in range(2):
            b.box((0, -D - 2.55 - k * 0.3, 0.35 - k * 0.15), (0.9, 0.16, 0.12), (0.6, 0.58, 0.55))
        b.box((0, -D - 0.04, 1.65), (0.55, 0.04, 1.05), (0.35, 0.22, 0.15))  # door
        b.box((0, -D - 0.07, 2.8), (0.68, 0.05, 0.08), WHITE)
        for x in (-3.3, -1.6, 1.6, 3.3):
            window(b, g, x, -D, 2.0, 1.0, 1.25, shutters=(0.2, 0.36, 0.28))
        for x in (-2.4, 2.4):
            window(b, g, x, -D, 4.0, 0.9, 0.9)
        for x in (-2.5, 2.5):
            window(b, g, x, D, 2.0, 1.0, 1.25, face=1)
        for sx in (-1, 1):
            side_window(b, g, sx * W, -1.5, 2.0, 1.0, 1.25, face=sx)
            side_window(b, g, sx * W, 1.5, 2.0, 1.0, 1.25, face=sx)
        side_window(b, g, W, 0.0, 6.2, 0.8, 0.8, face=1)
    else:
        for x in (-3.3, -1.6, 1.6, 3.3):
            g.box((x, -D - 0.03, 2.0), (0.5, 0.02, 0.62), GLASS, shade=False)
    return b, g


def barn(lod):
    b, g = Builder(), Builder()
    W, D, H = 6.0, 4.5, 5.0
    red = (0.62, 0.16, 0.12)
    roof = (0.38, 0.38, 0.4)
    b.box((0, 0, 0.2), (W + 0.15, D + 0.15, 0.2), (0.5, 0.48, 0.45))
    b.box((0, 0, 0.4 + H / 2), (W, D, H / 2), red)
    # gambrel roof: lower steep slopes + upper shallow slopes (along X)
    z0 = 0.4 + H
    for sy in (-1, 1):
        a0, a1 = (sy * (D + 0.4), z0), (sy * (D * 0.55), z0 + 2.6)
        b1 = (0.0, z0 + 4.0)
        for (p, q, k) in ((a0, a1, 0.95 if sy < 0 else 0.8), (a1, b1, 1.05 if sy < 0 else 0.85)):
            pts = [(-W - 0.4, p[0], p[1] + 0.12), (W + 0.4, p[0], p[1] + 0.12), (W + 0.4, q[0], q[1] + 0.12), (-W - 0.4, q[0], q[1] + 0.12)]
            b.face(pts if sy < 0 else list(reversed(pts)), mul(roof, k))
    for sx in (-1, 1):  # gable end walls (red) up to the gambrel line
        pts = [(sx * W, -D, z0), (sx * W, -D * 0.55 - 0.3, z0 + 2.5), (sx * W, 0, z0 + 3.9), (sx * W, D * 0.55 + 0.3, z0 + 2.5), (sx * W, D, z0)]
        b.face(pts if sx > 0 else list(reversed(pts)), mul(red, 0.85))
    if lod == 0:
        for k in range(-11, 12):  # vertical board lines
            b.box((k * W / 12, -D - 0.015, 0.4 + H / 2), (0.02, 0.015, H / 2), mul(red, 0.75))
        for sx in (-1, 1):
            for sy in (-1, 1):
                b.box((sx * W, sy * D, 0.4 + H / 2), (0.15, 0.15, H / 2), WHITE)
        # big doors with white X bracing, hayloft door
        b.box((0, -D - 0.05, 2.0), (1.9, 0.05, 1.6), mul(red, 0.85))
        for (cx, cz, hx, hz) in ((0, 3.65, 2.0, 0.09), (0, 0.45, 2.0, 0.09), (-1.95, 2.0, 0.09, 1.6), (1.95, 2.0, 0.09, 1.6), (0, 2.0, 0.07, 1.6)):
            b.box((cx, -D - 0.1, cz), (hx, 0.04, hz), WHITE)
        for sx in (-1, 1):
            b.box((sx * 0.95, -D - 0.1, 2.0), (0.06, 0.03, 1.75), WHITE, rot_z=0)
        b.box((0, -D - 0.05, 5.6), (0.8, 0.05, 0.7), mul(red, 0.8))
        b.box((0, -D - 0.09, 5.6), (0.9, 0.03, 0.78), WHITE, shade=True)
        b.box((0, -D - 0.11, 5.6), (0.72, 0.03, 0.62), mul(red, 0.7))
        window(b, g, -4.0, -D, 3.0, 0.9, 0.9)
        window(b, g, 4.0, -D, 3.0, 0.9, 0.9)
    else:
        b.box((0, -D - 0.03, 2.0), (1.9, 0.03, 1.6), WHITE)
    return b, g


def cabin(lod):
    b, g = Builder(), Builder()
    W, D = 4.2, 3.4
    wood = (0.45, 0.3, 0.18)
    snow = (0.94, 0.96, 1.0)
    logs = 9 if lod == 0 else 0
    if lod == 0:
        r = 0.17
        for k in range(logs):
            z = 0.35 + r + k * 2 * r * 0.95
            c = mul(wood, 0.9 + 0.12 * ((k * 37) % 5) / 5)
            b.cylinder((-W - 0.3, -D, z), (W + 0.3, -D, z), r, c, segs=7)
            b.cylinder((-W - 0.3, D, z), (W + 0.3, D, z), r, c, segs=7)
            b.cylinder((-W, -D - 0.3, z + r * 0.95), (-W, D + 0.3, z + r * 0.95), r, c, segs=7)
            b.cylinder((W, -D - 0.3, z + r * 0.95), (W, D + 0.3, z + r * 0.95), r, c, segs=7)
        b.box((0, 0, 1.9), (W - 0.1, D - 0.1, 1.6), mul(wood, 0.7))  # inner fill (no gaps)
        top = 0.35 + logs * 2 * r * 0.95
    else:
        b.box((0, 0, 1.9), (W, D, 1.6), wood)
        top = 3.5
    b.box((0, 0, 0.2), (W + 0.3, D + 0.3, 0.2), (0.45, 0.45, 0.47))
    b.prism_roof(-W - 0.7, W + 0.7, -D - 0.8, D + 0.8, top, 2.4, (0.3, 0.22, 0.18), gable=wood, thick=0.18)
    b.prism_roof(-W - 0.72, W + 0.72, -D - 0.82, D + 0.82, top + 0.2, 2.4, snow, thick=0.22)  # snow layer
    if lod == 0:
        b.box((-2.8, 0.8, top + 1.6), (0.45, 0.45, 1.6), (0.5, 0.5, 0.52))  # stone chimney
        b.box((-2.8, 0.8, top + 3.25), (0.5, 0.5, 0.12), snow)
        b.box((0.8, -D - 0.08, 1.45), (0.55, 0.05, 1.05), (0.3, 0.2, 0.12))  # door
        b.box((0, -D - 1.1, 0.45), (2.4, 1.0, 0.1), mul(wood, 0.8))  # porch deck + roof
        for sx in (-1, 1):
            b.box((sx * 2.2, -D - 1.95, 1.6), (0.1, 0.1, 1.2), mul(wood, 0.8))
        b.box((0, -D - 1.15, 2.85), (2.6, 1.15, 0.08), snow)
        window(b, g, -1.9, -D, 1.9, 1.0, 1.0, frame=mul(wood, 0.6))
        window(b, g, 2.6, -D, 1.9, 0.9, 1.0, frame=mul(wood, 0.6))
        for sx in (-1, 1):
            side_window(b, g, sx * W, 0.0, 1.9, 1.0, 1.0, face=sx)
    else:
        g.box((-1.9, -D - 0.03, 1.9), (0.5, 0.02, 0.5), GLASS, shade=False)
    return b, g


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    E.reset()
    objs = []
    for name, fn in (("Farmhouse", farmhouse), ("Barn", barn), ("Cabin", cabin)):
        for lod in (0, 1):
            b, g = fn(lod)
            suf = "" if lod == 0 else "_lod1"
            objs.append(b.finish(name + suf))
            objs.append(g.finish(name + "Glow" + suf, mat_name="Glass"))
    for o in objs:
        print("BLD %-18s %5d tris" % (o.name, E.tris(o)))
    if argv:
        E.export(argv[0])
    if len(argv) > 1:
        preview([o for o in objs if not o.name.endswith("_lod1")], argv[1])
    print("BLD_OK")


def preview(objs, path):
    import bpy
    x = 0.0
    pairs = {}
    for o in objs:
        base = o.name.replace("Glow", "")
        pairs.setdefault(base, []).append(o)
    for base, os_ in pairs.items():
        for o in os_:
            o.location = (x, 0, 0)
        x += 16.0
    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else ("BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "CYCLES")
    scene.render.resolution_x, scene.render.resolution_y = 1500, 520
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.68, 0.85, 1)
    scene.world = world
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.5
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (math.radians(50), 0, math.radians(-35))
    bpy.context.collection.objects.link(so)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(x / 2, 0, 0))
    cam = bpy.data.cameras.new("C")
    co = bpy.data.objects.new("C", cam)
    bpy.context.collection.objects.link(co)
    co.location = (x / 2 - 8 - 6, -30, 7)
    co.rotation_euler = (math.radians(80), 0, math.radians(-8))
    cam.lens = 28
    scene.camera = co
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


main()
