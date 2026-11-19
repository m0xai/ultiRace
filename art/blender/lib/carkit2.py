"""Car kit v2 (milestone A1): stylised-realistic, joyful cars built headless and deterministically.

Body = loft of superellipse cross-sections along the car (+Y is forward, Z up), subdivided and
smooth-shaded; windows are faces of the same shell (material "Glass"); wheel arches are boolean
cut-outs; wheels are lathed tyres + spoked rims as separate objects Wheel_FL/FR/RL/RR (axle along
X, origin at the hub, no rotation → Godot spins them cleanly). Materials are PBR and survive the
glTF export: Paint (clear-coat), Accent, Trim, Chrome, Glass, Rubber, Light, TailLight.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


# ---------- scene & materials ----------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, metallic=0.0, rough=0.5, emission=None, strength=3.0, clearcoat=0.0, alpha=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    for key in ("Coat Weight", "Clearcoat"):
        if key in b.inputs:
            b.inputs[key].default_value = clearcoat
            break
    if emission is not None:
        for key in ("Emission Color", "Emission"):
            if key in b.inputs:
                b.inputs[key].default_value = emission
                break
        if "Emission Strength" in b.inputs:
            b.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
    return m


def palette(paint, accent):
    return {
        "Paint": material("Paint", srgb(paint), metallic=0.05, rough=0.28, clearcoat=1.0),
        "Accent": material("Accent", srgb(accent), metallic=0.2, rough=0.35, clearcoat=0.5),
        "Trim": material("Trim", srgb("#1c1e22"), rough=0.6),
        "Chrome": material("Chrome", srgb("#d8dde3"), metallic=1.0, rough=0.12),
        "Glass": material("Glass", srgb("#1d2f45"), metallic=0.4, rough=0.05),
        "Rubber": material("Rubber", srgb("#141414"), rough=0.92),
        "Light": material("Light", srgb("#fff6d8"), emission=srgb("#fff2c8"), strength=4.0, rough=0.1),
        "TailLight": material("TailLight", srgb("#c4141c"), emission=srgb("#ff2a2a"), strength=3.0, rough=0.2),
    }


def link(obj):
    bpy.context.collection.objects.link(obj)
    return obj


def to_object(name, bm, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    return link(bpy.data.objects.new(name, me))


# ---------- lofted body ----------

def _ring(sec, n, belt_z=None):
    """Superellipse ring for a section: dict(y, w, zb, zt, p, top) → list of Vector."""
    y, hw, zb, zt, p, top = sec["y"], sec["w"], sec["zb"], sec["zt"], sec.get("p", 3.0), sec.get("top", 1.0)
    zc, hh = (zb + zt) / 2, (zt - zb) / 2
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        x = hw * math.copysign(abs(c) ** (2 / p), c)
        z = zc + hh * math.copysign(abs(s) ** (2 / p), s)
        if z > zc:  # tumblehome: the upper half narrows toward the roof
            k = (z - zc) / max(hh, 1e-6)
            x *= 1 + (top - 1) * k
        pts.append(Vector((x, y, z)))
    return pts


def loft(name, sections, mats, ring=24, glass=None):
    """Lofts closed sections (sorted by y). glass=(y0, y1, belt_z): faces in that range above the
    belt line that do not face straight up become material 'Glass'."""
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in _ring(s, ring)] for s in sections]
    for a, b in zip(rings, rings[1:]):
        for i in range(ring):
            j = (i + 1) % ring
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    names = [m.name for m in mats]
    if glass:
        gi = names.index("Glass")
        y0, y1, belt = glass
        roof = max(s["zt"] for s in sections if y0 <= s["y"] <= y1)
        for f in bm.faces:
            c = f.calc_center_median()
            # windows: between belt line and roof edge, on side/front/rear faces (roof stays paint)
            if y0 <= c.y <= y1 and belt < c.z < roof - 0.1 and abs(f.normal.z) < 0.8:
                f.material_index = gi
    obj = to_object(name, bm, mats)
    sub = obj.modifiers.new("subd", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def cabin(name, sections, P, roof_from=0.82):
    """Greenhouse: lofted canopy; faces below roof_from of its height are glass, the roof is paint."""
    mats = [P["Paint"], P["Glass"]]
    obj = loft(name, sections, mats, ring=24)
    zb = min(s["zb"] for s in sections)
    zt = max(s["zt"] for s in sections)
    split = zb + (zt - zb) * roof_from
    for f in obj.data.polygons:
        if f.center.z < split and abs(f.normal.z) < 0.97:
            f.material_index = 1
    return obj


def cut_arches(body, wheels_xyr, width=0.7):
    """Boolean wheel arches: cylinders slightly larger than the wheels."""
    for (x, y, r) in wheels_xyr:
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=r * 1.18, depth=width, location=(x, y, r),
                                            rotation=(0, math.pi / 2, 0))
        cutter = bpy.context.active_object
        cutter.display_type = "WIRE"
        m = body.modifiers.new("arch", "BOOLEAN")
        m.operation = "DIFFERENCE"
        m.object = cutter
        m.solver = "EXACT"
        cutter.hide_render = True
        cutter.hide_set(True)
        cutter["cutter"] = True


# ---------- parts ----------

def rounded_box(name, size, loc, mat, bevel=0.04, segs=2, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    obj = to_object(name, bm, [mat])
    obj.location, obj.rotation_euler = loc, rot
    if bevel > 0:
        b = obj.modifiers.new("bevel", "BEVEL")
        b.width, b.segments = bevel, segs
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def disc(name, radius, depth, loc, mat, axis="Y", verts=20):
    rot = {"X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=radius, radius2=radius, depth=depth)
    obj = to_object(name, bm, [mat])
    obj.location, obj.rotation_euler = loc, rot
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def lathe(name, profile, mats_idx, mats, segments=28):
    """Revolve (radius, x) profile points around the X axis; mats_idx[i] = material of band i."""
    bm = bmesh.new()
    rings = []
    for (r, x) in profile:
        ring = []
        for k in range(segments):
            a = 2 * math.pi * k / segments
            ring.append(bm.verts.new((x, r * math.cos(a), r * math.sin(a))))
        rings.append(ring)
    for bi, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(segments):
            j = (k + 1) % segments
            f = bm.faces.new((a[k], a[j], b[j], b[k]))
            f.material_index = mats_idx[bi]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = to_object(name, bm, mats)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def wheel(name, x, y, r, width, P, rim_mat="Chrome", spokes=5, inner=False):
    """Tyre (rubber, rounded sidewalls) + rim with spokes; axle along X, origin at the hub."""
    w = width / 2
    side = -1 if x < 0 else 1  # outer face points away from the car
    prof = [(r * 0.62, -w), (r * 0.86, -w * 1.02), (r * 0.97, -w * 0.85), (r, -w * 0.45), (r, w * 0.45),
            (r * 0.97, w * 0.85), (r * 0.86, w * 1.02), (r * 0.62, w)]
    tyre = lathe(name, prof, [0] * 7, [P["Rubber"]])
    rim_r = r * 0.64
    rim = disc(name + "_rim", rim_r, width * 0.7, (0, 0, 0), P[rim_mat], axis="X", verts=24)
    hub = disc(name + "_hub", rim_r * 0.28, width * 0.82, (0, 0, 0), P["Trim"], axis="X", verts=12)
    parts = [rim, hub]
    for k in range(spokes):
        a = 2 * math.pi * k / spokes
        sp = rounded_box(name + f"_sp{k}", (0.06, rim_r * 0.95, 0.09), (side * width * 0.38, 0, 0), P["Trim"], bevel=0.01, segs=1,
                         rot=(a, 0, 0))
        sp.location = (side * width * 0.37, math.sin(a) * rim_r * 0.0, 0)
        parts.append(sp)
    join(tyre, parts)
    tyre.location = (x, y, r)
    return tyre


def join(target, others):
    bpy.ops.object.select_all(action="DESELECT")
    for o in others:
        o.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    return target


def mirror_x(objs):
    """Duplicates parts mirrored to −X (for lights, mirrors, exhausts)."""
    out = []
    for o in objs:
        d = o.copy()
        d.data = o.data.copy()
        d.location = (-o.location[0], o.location[1], o.location[2])
        d.rotation_euler = (o.rotation_euler[0], -o.rotation_euler[1], -o.rotation_euler[2])
        link(d)
        out.append(d)
    return out


def blob(name, radius, loc, mat, scale=(1, 1, 1), segs=16, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    obj = to_object(name, bm, [mat])
    obj.location, obj.scale = loc, scale
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def standard_details(P, front, rear, mirror, grille=None, bumper_w=1.5, bumper_z=0.42):
    """Lights/mirrors/bumpers embedded into the body. front/rear: (x, y, z) of the right lamp,
    mirror: (x, y, z); grille: (w, y, z) or None. Lamps are flattened ellipsoids sunk into the
    shell so they read as part of the car, not stuck-on boxes."""
    parts = []
    hl = blob("headlight", 0.17, front, P["Light"], scale=(1.25, 0.55, 0.62))
    tl = blob("taillight", 0.15, rear, P["TailLight"], scale=(1.4, 0.45, 0.55))
    mi = blob("mirror", 0.11, mirror, P["Paint"], scale=(1.1, 0.8, 0.75))
    parts += [hl, tl, mi] + mirror_x([hl, tl, mi])
    if grille:
        gw, gy, gz = grille
        parts.append(rounded_box("grille", (gw, 0.08, 0.13), (0, gy, gz), P["Trim"], bevel=0.04))
    parts.append(rounded_box("bumper_f", (bumper_w, 0.12, 0.07), (0, front[1] - 0.02, bumper_z), P["Trim"], bevel=0.03))
    parts.append(rounded_box("bumper_r", (bumper_w, 0.12, 0.07), (0, rear[1] + 0.02, bumper_z), P["Trim"], bevel=0.03))
    return parts


# ---------- export / preview ----------

def apply_and_clean():
    """Applies boolean/subsurf modifiers on the body and deletes cutter helpers."""
    for o in list(bpy.context.scene.objects):
        if o.get("cutter"):
            bpy.data.objects.remove(o)


def triangles():
    deps = bpy.context.evaluated_depsgraph_get()
    total = 0
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and not o.get("cutter"):
            me = o.evaluated_get(deps).to_mesh()
            me.calc_loop_triangles()
            total += len(me.loop_triangles)
    return total


def finalize_body(body):
    """Apply modifiers in order (booleans need the cutters), then remove cutters."""
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    for m in list(body.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    apply_and_clean()


def export(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)


def turntable(png_path, size=480):
    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.view_settings.view_transform = "Standard"  # match Godot's colours more closely
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.62, 0.75, 1)
    bg.inputs["Strength"].default_value = 1.0
    sun = link(bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN")))
    sun.data.energy = 3.2
    sun.rotation_euler = (math.radians(45), 0, math.radians(35))
    fill = link(bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN")))
    fill.data.energy = 1.2
    fill.rotation_euler = (math.radians(60), 0, math.radians(215))
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.data.materials.append(material("Floor", srgb("#8a93a3"), rough=0.7))
    cam = link(bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")))
    cam.data.lens = 50
    scene.camera = cam
    target = link(bpy.data.objects.new("look", None))
    target.location = (0, 0, 0.75)
    c = cam.constraints.new("TRACK_TO")
    c.target, c.track_axis, c.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
    base = os.path.splitext(png_path)[0]
    tiles = []
    for i, a in enumerate((40, 140, 220, 320)):
        r = math.radians(a)
        cam.location = (7.0 * math.sin(r), 7.0 * math.cos(r), 2.6)
        scene.render.filepath = f"{base}_{i}.png"
        bpy.ops.render.render(write_still=True)
        tiles.append(scene.render.filepath)
    sheet = bpy.data.images.new("sheet", size * 2, size * 2, alpha=False)
    px = [0.0] * (size * size * 16)
    for i, t in enumerate(tiles):
        src = list(bpy.data.images.load(t).pixels)
        ox, oy = (i % 2) * size, (1 - i // 2) * size
        for yy in range(size):
            row = (yy + oy) * size * 2 * 4 + ox * 4
            px[row:row + size * 4] = src[yy * size * 4:(yy + 1) * size * 4]
        os.remove(t)
    sheet.pixels = px
    sheet.filepath_raw = png_path
    sheet.file_format = "PNG"
    sheet.save()
    bpy.data.objects.remove(floor)


def run(build):
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    reset()
    build()
    print(f"CAR_TRIS {triangles()}")
    if argv:
        export(argv[0])
    if len(argv) > 1:
        turntable(argv[1])
    print("CAR_OK")


def tube(name, a, b, radius, mat, verts=10):
    """Cylinder from point a to point b (roll cages, crane arms, antennas)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=radius, radius2=radius, depth=d.length)
    obj = to_object(name, bm, [mat])
    obj.location = (a + b) / 2
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def glow(name, hexcol, strength=4.0):
    return material(name, srgb(hexcol), emission=srgb(hexcol), strength=strength, rough=0.2)


def four_wheels(xs, yf, yr, rf, rr, wf, wr, P, rim="Chrome", spokes=5):
    for nm, x, y, r, w in (("FL", -xs, yf, rf, wf), ("FR", xs, yf, rf, wf), ("RL", -xs, yr, rr, wr), ("RR", xs, yr, rr, wr)):
        wheel("Wheel_" + nm, x, y, r, w, P, rim_mat=rim, spokes=spokes)
    return [(-xs, yf, rf), (xs, yf, rf), (-xs, yr, rr), (xs, yr, rr)]
