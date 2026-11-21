"""Vegetation + rocks kit (graphics pass 5, "unified quality"): real shapes instead of cones and
blobs, vertex colours with baked occlusion (the mobile renderer has no SSAO), two detail levels.

Usage: blender --background --factory-startup --python art/blender/env/vegetation.py -- <out.glb> [preview.png]

Every object is 1 m tall (rocks: ~1 m wide) with its origin at the base; the game scales and
tints instances. Objects: Pine, Pine_lod1, PineSnow, PineSnow_lod1, Broadleaf, Broadleaf_lod1,
Bush, Cactus, Cactus_lod1, Rock0, Rock1, Rock2. One vertex-coloured material ("Foliage").
Deterministic (fixed seeds).
"""
import math
import random
import sys

import bmesh
import bpy
from mathutils import Vector, noise


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def lin(c):
    """sRGB hex/tuple → linear RGBA."""
    def f(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), 1.0)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def mul(a, k):
    return tuple(min(1.0, a[i] * k) for i in range(3))


MAT = None


def material():
    global MAT
    if MAT is None:
        MAT = bpy.data.materials.new("Foliage")
        MAT.use_nodes = True
        nt = MAT.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.9
    return MAT


def to_object(name, bm, colors, smooth=True):
    """colors: per-face list of RGB (all corners of the face) or callable(face) → RGB."""
    me = bpy.data.meshes.new(name)
    col_layer = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        c = colors(f) if callable(colors) else colors[f.index]
        for loop in f.loops:
            cc = c(loop) if callable(c) else c
            loop[col_layer] = (cc[0], cc[1], cc[2], 1.0)  # byte colour layer: sRGB values
    bm.to_mesh(me)
    bm.free()
    ca = me.color_attributes.get("Col")
    if ca is not None:  # the exporter takes the active/render colour layer
        me.color_attributes.active_color = ca
        me.color_attributes.render_color_index = me.color_attributes.find("Col")
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    me.materials.append(material())
    if smooth:
        me.shade_smooth()
    else:
        me.shade_flat()
    return obj


def tris(obj):
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


# ---------- pine ----------

def pine(name, tiers, branches, snow, seed, detail=True):
    rng = random.Random(seed)
    bm = bmesh.new()
    face_col = {}
    bark = (0.32, 0.22, 0.15)
    needle = (0.16, 0.36, 0.2)
    tip = (0.32, 0.54, 0.26)
    snowc = (0.93, 0.95, 0.99)

    def add_face(vs, col):
        f = bm.faces.new(vs)
        face_col[f] = col
        return f

    # trunk: tapered 7-sided cone, darker at the base
    segs = 7 if detail else 5
    rings = []
    for k, (y, r) in enumerate([(0.0, 0.04), (0.35, 0.03), (0.95, 0.008)]):
        rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs), y))
                      for i in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            add_face((a[i], a[j], b[j], b[i]), mul(bark, 0.7 if a is rings[0] else 1.0))
    # branch tiers: star-shaped drooping skirts, widest at the bottom
    for t in range(tiers):
        u = t / max(tiers - 1, 1)
        y = 0.16 + 0.8 * u
        R = 0.38 * (1.0 - u) ** 0.85 + 0.05
        droop = 0.08 + 0.12 * R
        top = bm.verts.new((0, 0, y + 0.05 + 0.03 * R))
        under = bm.verts.new((0, 0, y - droop * 0.35))
        n = branches + (0 if detail else -2)
        rot = rng.random() * math.tau
        outer, mid = [], []
        for i in range(2 * n):
            a = rot + math.pi * i / n + rng.uniform(-0.12, 0.12)
            is_tip = i % 2 == 0
            r = R * (rng.uniform(0.9, 1.08) if is_tip else rng.uniform(0.55, 0.68))
            z = y - (droop if is_tip else droop * 0.6) + rng.uniform(-0.01, 0.01)
            outer.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
            if detail:  # mid ring: the branch arches up before it droops
                mid.append(bm.verts.new((0.5 * r * math.cos(a), 0.5 * r * math.sin(a), y - droop * 0.15 + 0.02)))
        dark = mul(needle, 0.75 + 0.35 * u)
        for i in range(2 * n):
            j = (i + 1) % (2 * n)
            is_tip_i = i % 2 == 0
            ctop = mix(dark, tip, 0.55 if is_tip_i else 0.2)
            if snow:
                ctop = mix(ctop, snowc, 0.85 if rng.random() < 0.75 else 0.4)
            if detail:
                add_face((top, mid[i], mid[j]), mix(dark, ctop, 0.3) if not snow else mix(dark, snowc, 0.8))
                add_face((mid[i], outer[i], outer[j], mid[j]), ctop)
            else:
                add_face((top, outer[i], outer[j]), ctop)
            add_face((under, outer[j], outer[i]), mul(dark, 0.45))  # underside: deep shade
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    cols = {f.index: face_col[f] for f in bm.faces}
    bm.faces.index_update()
    cols = [face_col[f] for f in bm.faces]
    return to_object(name, bm, cols, smooth=True)


# ---------- broadleaf ----------

def blob(bm, center, radius, subdiv, seed, squash=0.8):
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    vs = res["verts"]
    for v in vs:
        d = v.co.normalized()
        n = noise.noise(d * 2.3 + Vector((seed * 1.7, seed * 0.3, 0)))
        v.co = d * radius * (1.0 + 0.28 * n)
        v.co.z *= squash
        v.co += Vector(center)
    return vs


def broadleaf(name, detail, seed):
    rng = random.Random(seed)
    bm = bmesh.new()
    bark = (0.3, 0.22, 0.16)
    # trunk + two branches (tapered tubes)
    def tube(a, b, ra, rb, segs):
        a, b = Vector(a), Vector(b)
        d = (b - a).normalized()
        side = d.cross(Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))).normalized()
        up = side.cross(d)
        ring_a = [bm.verts.new(a + (side * math.cos(2 * math.pi * i / segs) + up * math.sin(2 * math.pi * i / segs)) * ra)
                  for i in range(segs)]
        ring_b = [bm.verts.new(b + (side * math.cos(2 * math.pi * i / segs) + up * math.sin(2 * math.pi * i / segs)) * rb)
                  for i in range(segs)]
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((ring_a[i], ring_a[j], ring_b[j], ring_b[i]))
    segs = 7 if detail else 5
    tube((0, 0, 0), (0.01, 0, 0.45), 0.045, 0.028, segs)
    if detail:
        tube((0, 0, 0.36), (0.15, 0.06, 0.6), 0.022, 0.01, 5)
        tube((0, 0, 0.4), (-0.13, -0.08, 0.63), 0.022, 0.01, 5)
        tube((0, 0, 0.42), (0.02, -0.14, 0.66), 0.02, 0.01, 5)
    trunk_faces = set(bm.faces)
    # crown of many smaller clusters on an ellipsoid shell + a few inside: an irregular, layered canopy
    clusters = [((0, 0, 0.72), 0.24), ((0.08, 0.06, 0.62), 0.2), ((-0.08, -0.05, 0.82), 0.2)]
    for k in range(7):
        a = k * 2.39996 + rng.uniform(-0.2, 0.2)
        h = 0.55 + 0.36 * ((k * 0.618) % 1.0)
        rr = 0.26 * math.sin(math.pi * (h - 0.48) / 0.5) + 0.05
        clusters.append(((rr * math.cos(a), rr * math.sin(a), h), rng.uniform(0.16, 0.2)))
    if not detail:
        clusters = [((0, 0, 0.72), 0.3), ((0.17, 0.05, 0.64), 0.22), ((-0.16, -0.08, 0.66), 0.22)]
    for k, (c, r) in enumerate(clusters):
        blob(bm, c, r, 2 if detail else 1, seed * 10 + k, squash=0.85)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    leaf_lo = (0.17, 0.34, 0.12)
    leaf_hi = (0.5, 0.7, 0.26)
    crown = Vector((0, 0, 0.72))

    bm.normal_update()

    def vcol(v):  # per vertex: smooth gradients (per-face colours read as facets)
        up = v.normal.z * 0.5 + 0.5
        out = min(1.0, (v.co - crown).length / 0.3)  # outer leaves catch light, inner ones are shaded
        n = noise.noise(v.co * 9.0) * 0.5 + 0.5  # leaf-clump variation
        base = mix(leaf_lo, leaf_hi, up * 0.6 + out * 0.25 + n * 0.25)
        return mul(base, 0.5 + 0.5 * out)

    def col(f):
        if f in trunk_faces:
            return mul(bark, 0.8)
        return lambda loop: vcol(loop.vert)
    cols = [col(f) for f in bm.faces]
    return to_object(name, bm, cols, smooth=True)


def bush(name, seed):
    bm = bmesh.new()
    for k, (c, r) in enumerate([((0, 0, 0.4), 0.42), ((0.3, 0.1, 0.3), 0.3), ((-0.28, -0.08, 0.32), 0.32), ((0.05, -0.3, 0.28), 0.27)]):
        blob(bm, c, r, 2, seed + k, squash=0.85)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()

    def vcol(v):
        up = v.normal.z * 0.5 + 0.5
        n = noise.noise(v.co * 8.0) * 0.5 + 0.5
        return mul(mix((0.2, 0.38, 0.14), (0.48, 0.66, 0.26), up * 0.7 + n * 0.3), 0.65 + 0.35 * min(1.0, v.co.z / 0.6))
    cols = [(lambda loop: vcol(loop.vert)) for f in bm.faces]
    return to_object(name, bm, cols, smooth=True)


# ---------- cactus (saguaro) ----------

def ribbed_tube(bm, path, radius, ribs, rings_per_seg, cap=True):
    """Star cross-section (ribs) along a polyline; returns faces. Radius tapers at the cap."""
    pts = [Vector(p) for p in path]
    prev = None
    faces = []
    nseg = len(pts) - 1
    allrings = []
    for s in range(nseg):
        a, b = pts[s], pts[s + 1]
        for k in range(rings_per_seg + (1 if s == nseg - 1 else 0)):
            t = k / rings_per_seg
            p = a.lerp(b, t)
            d = (b - a).normalized()
            side = d.cross(Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((1, 0, 0))).normalized()
            up = side.cross(d)
            ring = []
            n = ribs * 2
            for i in range(n):
                ang = 2 * math.pi * i / n
                r = radius * (1.0 if i % 2 == 0 else 0.86)
                ring.append(bm.verts.new(p + (side * math.cos(ang) + up * math.sin(ang)) * r))
            allrings.append(ring)
    # rounded cap
    end = pts[-1]
    d = (pts[-1] - pts[-2]).normalized()
    for k, (off, sc) in enumerate([(0.35, 0.8), (0.6, 0.45)]):
        ring = [bm.verts.new(end + (v.co - end) * sc + d * radius * off) for v in allrings[-1]]
        allrings.append(ring)
    tip = bm.verts.new(end + d * radius * 0.72)
    for ra, rb in zip(allrings, allrings[1:]):
        n = len(ra)
        for i in range(n):
            j = (i + 1) % n
            faces.append(bm.faces.new((ra[i], ra[j], rb[j], rb[i])))
    last = allrings[-1]
    for i in range(len(last)):
        faces.append(bm.faces.new((last[i], last[(i + 1) % len(last)], tip)))
    return faces


def cactus(name, detail, seed):
    bm = bmesh.new()
    ribs = 8 if detail else 5
    rps = 3 if detail else 1
    ribbed_tube(bm, [(0, 0, 0), (0, 0, 0.5), (0, 0, 0.9)], 0.085, ribs, rps)
    ribbed_tube(bm, [(0.07, 0, 0.36), (0.2, 0, 0.4), (0.22, 0, 0.66)], 0.05, ribs, rps)
    ribbed_tube(bm, [(-0.07, 0, 0.5), (-0.17, 0, 0.53), (-0.18, 0, 0.74)], 0.045, ribs, rps)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()

    def vcol(v):
        base = mix((0.22, 0.4, 0.22), (0.4, 0.55, 0.3), v.normal.z * 0.5 + 0.5)
        return mul(base, 0.68 + 0.32 * min(1.0, v.co.z / 0.3))
    cols = [(lambda loop: vcol(loop.vert)) for f in bm.faces]
    return to_object(name, bm, cols, smooth=True)


# ---------- rocks ----------

def rock(name, seed):
    bm = bmesh.new()
    res = bmesh.ops.create_icosphere(bm, subdivisions=3, radius=0.5)
    for v in res["verts"]:
        d = v.co.normalized()
        n = noise.noise(d * 1.6 + Vector((seed, seed * 2.1, 0)))
        n2 = noise.noise(d * 4.0 + Vector((0, seed, seed)))
        v.co = d * 0.5 * (1.0 + 0.3 * n + 0.08 * n2)
        v.co.z = v.co.z * 0.62 + 0.2  # flattened, sitting a bit into the ground
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    cols = []
    for f in bm.faces:
        up = f.normal.z * 0.5 + 0.5
        z = f.calc_center_median().z
        c = mix((0.55, 0.54, 0.52), (0.82, 0.8, 0.76), up)
        cols.append(mul(c, 0.7 + 0.3 * min(1.0, max(0.0, z) / 0.45)))  # darker where it meets the ground
    return to_object(name, bm, cols, smooth=False)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    reset()
    objs = [
        pine("Pine", 11, 9, False, 1, True), pine("Pine_lod1", 5, 6, False, 1, False),
        pine("PineSnow", 11, 9, True, 2, True), pine("PineSnow_lod1", 5, 6, True, 2, False),
        broadleaf("Broadleaf", True, 3), broadleaf("Broadleaf_lod1", False, 3),
        bush("Bush", 4), cactus("Cactus", True, 5), cactus("Cactus_lod1", False, 5),
        rock("Rock0", 1.3), rock("Rock1", 4.1), rock("Rock2", 7.7),
    ]
    for i, o in enumerate(objs):
        print("VEG %-14s %5d tris" % (o.name, tris(o)))
    if argv:
        bpy.ops.export_scene.gltf(filepath=argv[0], export_format="GLB", export_apply=True, export_yup=True,
                                  export_vertex_color="ACTIVE")
    if len(argv) > 1:
        preview(objs, argv[1])
    print("VEG_OK")


def preview(objs, path):
    # lay the objects out in a row and render a quick look (Eevee if available)
    x = 0.0
    for o in objs:
        o.location = (x, 0, 0)
        s = 3.0 if not o.name.startswith("Rock") else 1.5
        o.scale = (s, s, s)
        x += 2.4
    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else ("BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "CYCLES")
    scene.render.resolution_x, scene.render.resolution_y = 1600, 420
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.68, 0.85, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    scene.world = world
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.5
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (math.radians(50), 0, math.radians(30))
    bpy.context.collection.objects.link(so)
    bpy.ops.mesh.primitive_plane_add(size=80, location=(x / 2, 0, 0))
    cam = bpy.data.cameras.new("C")
    co = bpy.data.objects.new("C", cam)
    bpy.context.collection.objects.link(co)
    co.location = (x / 2 - 1.2, -24, 3.4)
    co.rotation_euler = (math.radians(84), 0, 0)
    cam.lens = 30
    scene.camera = co
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


main()
