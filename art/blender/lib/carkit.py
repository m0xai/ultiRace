"""Shared helpers for the scripted cars (GAME_PLAN §4.3). Deterministic, headless.

Conventions: Blender Z-up, the car faces +Y (exports to glTF -Z, Godot's forward), origin at the
ground between the axles. Footprint matches the physics: ~2.0 m wide, ~3.8 m long.
One vertex-colour material ("Paint") for the body; "Glass" for windows/translucent parts;
wheels are separate objects Wheel_FL/FR/RL/RR (spin + steer in Godot).
"""
import math
import os
import sys

import bpy
import bmesh

WHEEL_DARK = (0.08, 0.08, 0.09, 1)
RIM = (0.75, 0.76, 0.8, 1)
GLASS = (0.15, 0.22, 0.3, 1)


def hexcol(h, a=1.0):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, a)


def shade(c, k):
    return (c[0] * k, c[1] * k, c[2] * k, c[3])


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    paint = bpy.data.materials.new("Paint")
    paint.use_nodes = True
    nt = paint.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.45
    glass = bpy.data.materials.new("Glass")
    glass.use_nodes = True
    gb = glass.node_tree.nodes["Principled BSDF"]
    gb.inputs["Base Color"].default_value = GLASS
    gb.inputs["Roughness"].default_value = 0.08
    gb.inputs["Metallic"].default_value = 0.3


def _finish(obj, color, bevel, segs, material="Paint"):
    me = obj.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    attr = me.color_attributes["Col"]
    for d in attr.data:
        d.color = color
    me.materials.append(bpy.data.materials[material])
    if bevel > 0:
        m = obj.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = segs
        m.limit_method = "ANGLE"
    for p in me.polygons:
        p.use_smooth = False
    return obj


def _new(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    return obj


def box(name, size, loc, color, bevel=0.06, segs=2, taper=None, rot=(0, 0, 0), material="Paint"):
    """Box of size (x,y,z) centred at loc. taper=(top_x, top_y) scales the top face (wedges)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
        if taper and v.co.z > 0:
            v.co.x *= taper[0]
            v.co.y *= taper[1]
    obj = _new(name, bm)
    obj.location = loc
    obj.rotation_euler = rot
    return _finish(obj, color, bevel, segs, material)


def wedge(name, size, loc, color, front_drop=0.6, bevel=0.05, segs=2):
    """Box whose top slopes down toward the front (+Y) by front_drop of its height."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        top = v.co.z > 0
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
        if top and v.co.y > 0:
            v.co.z -= size[2] * front_drop
    obj = _new(name, bm)
    obj.location = loc
    return _finish(obj, color, bevel, segs)


def cyl(name, radius, depth, loc, color, rot=(0, 0, 0), verts=14, bevel=0.03, segs=1, material="Paint", r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=radius, radius2=radius if r2 is None else r2, depth=depth)
    obj = _new(name, bm)
    obj.location = loc
    obj.rotation_euler = rot
    return _finish(obj, color, bevel, segs, material)


def ball(name, radius, loc, color, scale=(1, 1, 1), segs=12, rings=8, material="Paint"):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    obj = _new(name, bm)
    obj.location = loc
    obj.scale = scale
    return _finish(obj, color, 0, 0, material)


def wheels(track=1.7, front_y=1.2, rear_y=-1.2, radius=0.38, width=0.32, rear_radius=None):
    out = []
    for nm, x, y, r in (("FL", -track / 2, front_y, radius), ("FR", track / 2, front_y, radius),
                        ("RL", -track / 2, rear_y, rear_radius or radius), ("RR", track / 2, rear_y, rear_radius or radius)):
        w = cyl("Wheel_" + nm, r, width, (x, y, r), WHEEL_DARK, rot=(0, math.pi / 2, 0), verts=16, bevel=0.04, segs=1)
        hub = cyl("Hub_" + nm, r * 0.55, width + 0.02, (x, y, r), RIM, rot=(0, math.pi / 2, 0), verts=10, bevel=0)
        join_into(w, [hub])
        out.append(w)
    return out


def join_into(target, others):
    bpy.ops.object.select_all(action="DESELECT")
    for o in others:
        o.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    return target


def body_from(parts, name="Body"):
    """Join all non-wheel parts into one Body object (modifiers applied on export)."""
    body = parts[0]
    body.name = name
    if len(parts) > 1:
        join_into(body, parts[1:])
    return body


def triangles():
    deps = bpy.context.evaluated_depsgraph_get()
    total = 0
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            me = o.evaluated_get(deps).to_mesh()
            me.calc_loop_triangles()
            total += len(me.loop_triangles)
    return total


def export(glb_path):
    os.makedirs(os.path.dirname(glb_path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=glb_path, export_format="GLB", export_apply=True,
                              export_vertex_color="ACTIVE", export_yup=True)


def turntable(png_path, angles=(35, 125, 215, 305), size=420):
    """Renders a 2×2 sheet (four angles) for human review."""
    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.36, 0.45, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    floor = box("Floor", (12, 12, 0.02), (0, 0, -0.01), (0.55, 0.57, 0.6, 1), bevel=0)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 45
    scene.collection.objects.link(cam)
    scene.camera = cam
    tiles = []
    base = os.path.splitext(png_path)[0]
    for i, a in enumerate(angles):
        r = math.radians(a)
        cam.location = (7.5 * math.sin(r), 7.5 * math.cos(r), 3.6)
        direction = -cam.location.normalized() if hasattr(cam.location, "normalized") else None
        look = bpy.data.objects.new("look", None) if i == 0 else bpy.data.objects["look"]
        if i == 0:
            look.location = (0, 0, 0.7)
            scene.collection.objects.link(look)
            c = cam.constraints.new("TRACK_TO")
            c.target = look
            c.track_axis = "TRACK_NEGATIVE_Z"
            c.up_axis = "UP_Y"
        tile = f"{base}_{i}.png"
        scene.render.filepath = tile
        bpy.ops.render.render(write_still=True)
        tiles.append(tile)
    # compose 2×2 sheet
    sheet = bpy.data.images.new("sheet", size * 2, size * 2, alpha=False)
    px = [0.0] * (size * 2 * size * 2 * 4)
    for i, t in enumerate(tiles):
        img = bpy.data.images.load(t)
        src = list(img.pixels)
        ox, oy = (i % 2) * size, (1 - i // 2) * size
        for y in range(size):
            row = (y + oy) * size * 2 * 4 + ox * 4
            px[row:row + size * 4] = src[y * size * 4:(y + 1) * size * 4]
        os.remove(t)
    sheet.pixels = px
    sheet.filepath_raw = png_path
    sheet.file_format = "PNG"
    sheet.save()
    bpy.data.objects.remove(floor)


def run(build):
    """Entry point for a car script: build() creates the parts; args after '--': out_glb out_png."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    reset()
    build()
    tris = triangles()
    print(f"CAR_TRIS {tris}")
    if len(argv) >= 1:
        export(argv[0])
    if len(argv) >= 2:
        turntable(argv[1])
    print("CAR_OK")
