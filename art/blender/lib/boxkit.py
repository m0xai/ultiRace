"""Box car kit (A1 v3, "boxy" style): chunky block-built cars with matte paint and baked
ambient occlusion, inspired by voxel toy cars (style reference only; no external geometry).

Cars are stacks of prism blocks (a box whose top face may be narrower/shorter: tumblehome,
raked screens) with small chamfered edges, flat shading, square lamps and inset black windows.
All opaque parts end in ONE vertex-coloured material "Body" (colour × baked AO; metallic and
roughness per part in UV, read by Godot's car_body.gdshader) plus an emissive "Lamp" material.
Wheels are separate objects Wheel_FL/FR/RL/RR (axle along X, origin at the hub) as before.
+Y is forward, Z up, X right.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import carkit2 as k2  # noqa: E402  (scene reset, export, turntable, link helpers)

srgb = k2.srgb


def mat(name, hexcol, metallic=0.0, rough=0.7, emission=None, strength=3.0):
    return k2.material(name, srgb(hexcol), metallic=metallic, rough=rough,
                       emission=srgb(emission) if emission else None, strength=strength)


def palette(paint, accent):
    """Matte palette: no clear-coat (that read as plastic)."""
    return {
        "Paint": mat("Paint", paint, metallic=0.05, rough=0.5),
        "Accent": mat("Accent", accent, metallic=0.05, rough=0.55),
        "Trim": mat("Trim", "#2a2c31", rough=0.85),
        "Dark": mat("Dark", "#16191e", rough=0.8),
        "Window": mat("Window", "#11161d", metallic=0.2, rough=0.12),
        "Chrome": mat("Chrome", "#c4c9d0", metallic=0.85, rough=0.3),
        "Rubber": mat("Rubber", "#1b1c1f", rough=0.95),
        "Hub": mat("Hub", "#d9dce1", metallic=0.3, rough=0.45),
        "Plate": mat("Plate", "#eef0ec", rough=0.6),
        "Light": mat("Light", "#fff4d6", emission="#fff0c4", strength=4.0, rough=0.2),
        "TailLight": mat("TailLight", "#c8141c", emission="#ff2626", strength=3.0, rough=0.3),
        "Amber": mat("Amber", "#ff9c1c", emission="#ffa21a", strength=3.0, rough=0.3),
    }


# ---------- geometry ----------

def block(name, mat_, xb, y0, y1, z0, z1, xt=None, y0t=None, y1t=None, cx=0.0, bevel=0.025, subdiv=True):
    """Prism: bottom rectangle ±xb × [y0, y1] at z0, top rectangle ±xt × [y0t, y1t] at z1,
    centred on x = cx. Chamfered edges, flat shaded; subdivided so baked AO has resolution."""
    xt = xb if xt is None else xt
    y0t = y0 if y0t is None else y0t
    y1t = y1 if y1t is None else y1t
    bm = bmesh.new()
    v = [bm.verts.new((cx + sx * xb, y, z0)) for (sx, y) in ((-1, y0), (1, y0), (1, y1), (-1, y1))]
    v += [bm.verts.new((cx + sx * xt, y, z1)) for (sx, y) in ((-1, y0t), (1, y0t), (1, y1t), (-1, y1t))]
    for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        bm.faces.new([v[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = k2.to_object(name, bm, [mat_])
    if bevel > 0:
        b = obj.modifiers.new("bevel", "BEVEL")
        b.width, b.segments, b.limit_method = bevel, 1, "ANGLE"
    if subdiv:
        s = obj.modifiers.new("ao_res", "SUBSURF")
        s.subdivision_type, s.levels, s.render_levels = "SIMPLE", 1, 1
    for p in obj.data.polygons:
        p.use_smooth = False
    return obj


def pane(name, mat_, corners, off=0.008, centre=None):
    """Flat window/lamp quad over a planar face (4 corners in order), lifted `off` along the
    face normal; oriented to face away from `centre` (the block's middle)."""
    c = [Vector(p) for p in corners]
    n = (c[1] - c[0]).cross(c[2] - c[0]).normalized()
    if centre is not None and n.dot(sum(c, Vector()) / 4 - Vector(centre)) < 0:
        c.reverse()
        n = -n
    bm = bmesh.new()
    vs = [bm.verts.new(p + n * off) for p in c]
    bm.faces.new(vs)
    return k2.to_object(name, bm, [mat_])


def _inset(quad, mx, mz):
    """Shrink a quad (a0 bottom-left, a1 bottom-right, a2 top-right, a3 top-left) by mx along
    its width and mz along its height (fractions of each edge length in metres)."""
    a0, a1, a2, a3 = [Vector(p) for p in quad]

    def lerp(p, q, d):
        L = (q - p).length
        return p + (q - p) * (d / L if L > 1e-6 else 0)
    b0 = lerp(lerp(a0, a1, mx), lerp(a3, a2, mx), mz)
    b1 = lerp(lerp(a1, a0, mx), lerp(a2, a3, mx), mz)
    b2 = lerp(lerp(a2, a3, mx), lerp(a1, a0, mx), mz)
    b3 = lerp(lerp(a3, a2, mx), lerp(a0, a1, mx), mz)
    return [b0, b1, b2, b3]


def cabin(name, P, xb, y0, y1, z0, z1, xt=None, y0t=None, y1t=None, pillar=0.09, split=0.5,
          side_glass=True, front_glass=True, rear_glass=True, roof_mat=None):
    """Cabin block (painted) with black window panes on the front, rear and both sides (split
    into front/rear windows by a B-pillar at `split` of the length)."""
    xt = xb if xt is None else xt
    y0t = y0 if y0t is None else y0t
    y1t = y1 if y1t is None else y1t
    parts = [block(name, roof_mat or P["Paint"], xb, y0, y1, z0, z1, xt, y0t, y1t)]
    zb = z0 + 0.05  # window sill just above the belt
    zt = z1 - 0.06
    f = (zb - z0) / (z1 - z0)
    g = (zt - z0) / (z1 - z0)

    def at(sx, yb, ytop, t):  # point on a side edge at height fraction t
        x = sx * (xb + (xt - xb) * t)
        return Vector((x, yb + (ytop - yb) * t, z0 + (z1 - z0) * t))
    W = P["Window"]
    mid = Vector((0, (y0 + y1 + y0t + y1t) / 4, (z0 + z1) / 2))
    if front_glass:
        q = [at(-1, y1, y1t, f), at(1, y1, y1t, f), at(1, y1, y1t, g), at(-1, y1, y1t, g)]
        parts.append(pane("ws", W, _inset(q, pillar, 0.0), centre=mid))
    if rear_glass:
        q = [at(1, y0, y0t, f), at(-1, y0, y0t, f), at(-1, y0, y0t, g), at(1, y0, y0t, g)]
        parts.append(pane("rw", W, _inset(q, pillar, 0.0), centre=mid))
    if side_glass:
        for sx in (1, -1):
            # side face corners (bottom rear, bottom front, top front, top rear) at window heights
            br = at(sx, y0, y0t, f)
            bf = at(sx, y1, y1t, f)
            tf = at(sx, y1, y1t, g)
            tr = at(sx, y0, y0t, g)
            ym_b = br.y + (bf.y - br.y) * split
            ym_t = tr.y + (tf.y - tr.y) * split

            def on_bottom(y):
                t = (y - br.y) / (bf.y - br.y)
                return br + (bf - br) * t

            def on_top(y):
                t = (y - tr.y) / (tf.y - tr.y)
                return tr + (tf - tr) * t
            for (a, b, c, d) in ((br, on_bottom(ym_b - pillar / 2), on_top(ym_t - pillar / 2), tr),
                                 (on_bottom(ym_b + pillar / 2), bf, tf, on_top(ym_t + pillar / 2))):
                quad = [a, b, c, d] if sx > 0 else [b, a, d, c]
                parts.append(pane("sw", W, _inset(quad, pillar * 0.6, 0.0), centre=mid))
    return parts


def lamp_box(name, mat_, cx, y, z, hx, hz, depth=0.05):
    """Small square lamp/plate box sitting on a vertical face at y (sign of y = facing)."""
    s = 1 if y > 0 else -1
    return block(name, mat_, hx, y - s * depth, y + s * 0.012, z - hz, z + hz, cx=cx, bevel=0.008, subdiv=False) \
        if s > 0 else block(name, mat_, hx, y - 0.012, y + depth, z - hz, z + hz, cx=cx, bevel=0.008, subdiv=False)


def mirror(parts_fn):
    """Calls parts_fn(sx) for sx = +1 and −1 and concatenates the results."""
    return parts_fn(1) + parts_fn(-1)


def wheel(name, x, y, r, w, P, hub_mat=None):
    """Chunky 8-sided tyre (flat bottom) with a square hub plate; axle along X, origin at hub."""
    side = 1 if x > 0 else -1
    bm = bmesh.new()
    n = 8
    rings = []
    for xx in (-w / 2, w / 2):
        ring = []
        for i in range(n):
            a = 2 * math.pi * (i + 0.5) / n
            ring.append(bm.verts.new((xx, r * math.cos(a), r * math.sin(a))))
        rings.append(ring)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    tyre = k2.to_object(name, bm, [P["Rubber"]])
    b = tyre.modifiers.new("bevel", "BEVEL")
    b.width, b.segments, b.limit_method = 0.03, 1, "ANGLE"
    hub_m = hub_mat or P["Hub"]
    hs = r * 0.5
    hub = block(name + "_hub", hub_m, 0.03, -hs, hs, -hs, hs, cx=side * (w / 2 + 0.02), bevel=0.012, subdiv=False)
    cap = block(name + "_cap", P["Dark"], 0.02, -hs * 0.42, hs * 0.42, -hs * 0.42, hs * 0.42, cx=side * (w / 2 + 0.05),
                bevel=0.006, subdiv=False)
    inner = block(name + "_inner", P["Dark"], 0.01, -hs * 1.25, hs * 1.25, -hs * 1.25, hs * 1.25, cx=side * (w / 2 + 0.002),
                  bevel=0.0, subdiv=False)
    k2.join(tyre, [inner, hub, cap])
    tyre.location = (x, y, r)
    return tyre


def four_wheels(xs, yf, yr, rf, rr, wf, wr, P, hub_mat=None):
    for nm, x, y, r, w in (("FL", -xs, yf, rf, wf), ("FR", xs, yf, rf, wf), ("RL", -xs, yr, rr, wr), ("RR", xs, yr, rr, wr)):
        wheel("Wheel_" + nm, x, y, r, w, P, hub_mat)


def front_face(P, y, z, half_w, lamps=0.18, grille=True, plate=True, lamp_h=0.07, lamp_x=None, plate_y=None, plate_z=None):
    """Headlights, grille and number plate on a front face at y (facing +Y); the plate sits on
    the bumper face (plate_y/plate_z) when given."""
    lx = lamp_x if lamp_x is not None else half_w - lamps - 0.06
    parts = mirror(lambda sx: [lamp_box("hl", P["Light"], sx * lx, y, z, lamps, lamp_h)])
    if grille:
        parts.append(lamp_box("grille", P["Dark"], 0, y, z, max(lx - lamps - 0.06, 0.12), lamp_h * 0.9))
    if plate:
        parts.append(lamp_box("plate", P["Plate"], 0, plate_y if plate_y is not None else y,
                              plate_z if plate_z is not None else z - lamp_h - 0.13, 0.2, 0.055, depth=0.03))
    return parts


def rear_face(P, y, z, half_w, lamps=0.18, plate=True, lamp_h=0.07, lamp_x=None, plate_y=None, plate_z=None):
    """Tail lights and number plate on a rear face at y (facing −Y)."""
    lx = lamp_x if lamp_x is not None else half_w - lamps - 0.06
    parts = mirror(lambda sx: [lamp_box("tl", P["TailLight"], sx * lx, y, z, lamps, lamp_h)])
    if plate:
        parts.append(lamp_box("plate_r", P["Plate"], 0, plate_y if plate_y is not None else y,
                              plate_z if plate_z is not None else z, 0.2, 0.055, depth=0.03))
    return parts


def beam(name, mat_, a, b, thick=0.08, width=None, bevel=0.012):
    """Square-section bar from point a to point b (crane arms, roll cages, antennas)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    w = (width if width is not None else thick) / 2
    obj = block(name, mat_, w, -d.length / 2, d.length / 2, -thick / 2, thick / 2, bevel=bevel, subdiv=False)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 1, 0)).rotation_difference(d.normalized())
    obj.location = (a + b) / 2
    return obj


def octo(name, mat_, centre, radius, length, axis="Y", sides=8, bevel=0.02):
    """Octagonal prism (tank barrels) along an axis, flat shaded with chamfers."""
    bm = bmesh.new()
    rings = []
    for t in (-length / 2, length / 2):
        ring = []
        for i in range(sides):
            a = 2 * math.pi * (i + 0.5) / sides
            u, v = radius * math.cos(a), radius * math.sin(a)
            ring.append(bm.verts.new((u, t, v) if axis == "Y" else (t, u, v)))
        rings.append(ring)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = k2.to_object(name, bm, [mat_])
    obj.location = centre
    if bevel > 0:
        bv = obj.modifiers.new("bevel", "BEVEL")
        bv.width, bv.segments, bv.limit_method = bevel, 1, "ANGLE"
    s_ = obj.modifiers.new("ao_res", "SUBSURF")
    s_.subdivision_type, s_.levels, s_.render_levels = "SIMPLE", 1, 1
    return obj


def ring(name, mat_, centre, radius, thick=0.1, depth=0.12, sides=8):
    """Octagonal ring in the XZ plane (fan shroud) made of beams."""
    c = Vector(centre)
    pts = [c + Vector((radius * math.cos(2 * math.pi * i / sides), 0, radius * math.sin(2 * math.pi * i / sides)))
           for i in range(sides)]
    return [beam(name, mat_, pts[i], pts[(i + 1) % sides], thick=thick, width=depth) for i in range(sides)]


def side_mirrors(P, x, y, z, mat_=None):
    m = mat_ or P["Paint"]
    return mirror(lambda sx: [block("mirror", m, 0.07, y - 0.06, y + 0.06, z - 0.06, z + 0.05, cx=sx * (x + 0.07), bevel=0.012,
                                    subdiv=False)])


def door_lines(P, x, ys, z0, z1):
    """Thin dark door gaps on both flanks (x = flank position)."""
    out = []
    for y in ys:
        out += mirror(lambda sx, y=y: [block("gap", P["Dark"], 0.006, y - 0.008, y + 0.008, z0, z1, cx=sx * (x + 0.003), bevel=0.0,
                                             subdiv=False)])
    return out


# ---------- AO bake + consolidation ----------

def apply_all(objs):
    for o in objs:
        k2.apply_mods(o)


def bake_ao(targets, samples=48):
    """Bakes ambient occlusion (Cycles) into a vertex colour layer 'AO' on each target, with a
    temporary ground plane so lower parts get contact shadow."""
    scene = bpy.context.scene
    prev = scene.render.engine
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.device = "CPU"
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.data.materials.append(mat("AOGround", "#808080"))
    for o in targets:
        me = o.data
        attr = me.color_attributes.get("AO") or me.color_attributes.new("AO", "BYTE_COLOR", "CORNER")
        me.color_attributes.active_color = attr
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
        vals = [d.color[0] for d in attr.data]
        print(f"AO_BAKE {o.name}: min {min(vals):.2f} avg {sum(vals) / max(len(vals), 1):.2f}")
    bpy.data.objects.remove(ground)
    scene.render.engine = prev


def consolidate(ao_floor=0.35):
    """One vertex-coloured 'Body' material (base colour × AO, metallic/roughness in UV) and one
    emissive 'Lamp' material per mesh."""
    body = bpy.data.materials.get("Body") or bpy.data.materials.new("Body")
    lamp = bpy.data.materials.get("Lamp") or bpy.data.materials.new("Lamp")
    for m_, emit in ((body, False), (lamp, True)):
        m_.use_nodes = True
        nt = m_.node_tree
        b = nt.nodes["Principled BSDF"]
        vc = nt.nodes.get("vc") or nt.nodes.new("ShaderNodeVertexColor")
        vc.name, vc.layer_name = "vc", "Col"
        nt.links.new(vc.outputs["Color"], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = 0.6
        if emit:
            for key in ("Emission Color", "Emission"):
                if key in b.inputs:
                    nt.links.new(vc.outputs["Color"], b.inputs[key])
                    break
            b.inputs["Emission Strength"].default_value = 3.0
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        me = o.data
        ao = me.color_attributes.get("AO")
        if "Col" not in me.color_attributes:
            me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        col = me.color_attributes["Col"]
        for uvl in list(me.uv_layers):
            me.uv_layers.remove(uvl)
        uv = me.uv_layers.new(name="Surf")
        old = [s.material for s in o.material_slots]
        slots, remap = [], {}
        for i, m_ in enumerate(old):
            t = lamp if (m_ is not None and k2._is_lamp(m_)) else body
            if t not in slots:
                slots.append(t)
            remap[i] = slots.index(t)
        for poly in me.polygons:
            src = old[poly.material_index] if old else None
            c = k2._base_color(src) if src else (0.5, 0.5, 0.5, 1)
            lamp_face = src is not None and k2._is_lamp(src)
            mr = k2._surface(src)
            for li in poly.loop_indices:
                a = 1.0
                if ao is not None and not lamp_face:
                    a = ao_floor + (1 - ao_floor) * ao.data[li].color[0]
                col.data[li].color = (c[0] * a, c[1] * a, c[2] * a, 1.0)
                uv.data[li].uv = mr
        idx = [remap.get(p.material_index, 0) for p in me.polygons]
        me.materials.clear()
        for m_ in slots:
            me.materials.append(m_)
        for poly, i in zip(me.polygons, idx):
            poly.material_index = i
        if ao is not None:
            me.color_attributes.remove(ao)
        me.color_attributes.active_color = col


def run(build):
    """build() returns the body object (wheels are created by name). Applies modifiers, bakes
    AO on everything, consolidates materials, exports and renders the turntable."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    k2.reset()
    build()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    apply_all(meshes)
    bake_ao(meshes)
    consolidate()
    print(f"CAR_TRIS {k2.triangles()}")
    if os.environ.get("CAR_BREAKDOWN"):
        deps = bpy.context.evaluated_depsgraph_get()
        for o in bpy.context.scene.objects:
            if o.type == "MESH":
                me = o.evaluated_get(deps).to_mesh()
                me.calc_loop_triangles()
                print(f"  PART {o.name:14s} {len(me.loop_triangles):6d}")
    if argv:
        k2.export(argv[0])
    if len(argv) > 1:
        k2.turntable(argv[1])
    print("CAR_OK")
