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
        "Plate": material("Plate", srgb("#f1f2ee"), rough=0.4),
        "Brake": material("Brake", srgb("#2a2c31"), metallic=0.6, rough=0.45),
        "Housing": material("Housing", srgb("#2c3038"), metallic=0.85, rough=0.22),
        "TailHousing": material("TailHousing", srgb("#3a0c10"), metallic=0.3, rough=0.12),
        "Lens": material("Lens", srgb("#e8ecf2"), metallic=0.4, rough=0.08),
        "Reflector": material("Reflector", srgb("#9a1218"), metallic=0.2, rough=0.15),
        "Amber": material("Amber", srgb("#ff9c1c"), metallic=0.1, rough=0.15),
        "Caliper": material("Caliper", srgb("#c81e26"), metallic=0.2, rough=0.3),
        # see-through cabin glass (Godot: car_glass.gdshader) and the cabin interior behind it
        "GlassClear": material("GlassClear", srgb("#1d2f45"), metallic=0.4, rough=0.05),
        "Interior": material("Interior", srgb("#232428"), rough=0.75),
        "Seat": material("Seat", srgb("#3b3d45"), rough=0.6),
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


def loft(name, sections, mats, ring=24, glass=None, round_ends=False):
    """Lofts closed sections (sorted by y). glass=(y0, y1, belt_z): faces in that range above the
    belt line that do not face straight up become material 'Glass'."""
    bm = bmesh.new()
    if round_ends:  # pull the ends in over two extra sections: rounded nose/tail, no big flat cap
        def shrink(sec, k, dy):
            zc = (sec["zb"] + sec["zt"]) / 2
            hh = (sec["zt"] - sec["zb"]) / 2 * k
            return dict(sec, y=sec["y"] + dy, w=sec["w"] * k, zb=zc - hh, zt=zc + hh)
        a, b = sections[0], sections[-1]
        sections = [shrink(a, 0.55, -0.07), shrink(a, 0.86, -0.035)] + list(sections) + \
                   [shrink(b, 0.86, 0.035), shrink(b, 0.55, 0.07)]
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


def cabin(name, sections, P, roof_from=0.82, sink=0.22):
    """Greenhouse: lofted canopy; faces below roof_from of its height are glass, the roof is paint.
    The canopy is sunk `sink` m into the body so its walls cross the body surface steeply:
    nearly tangent/coplanar overlaps z-fight (visible flicker in motion)."""
    mats = [P["Paint"], P["GlassClear"], P["Trim"]]
    split_zb = min(s["zb"] for s in sections)
    _STATE["cab_belt"] = split_zb
    _STATE["cab_top"] = max(s["zt"] for s in sections)
    sections = [dict(s, zb=s["zb"] - sink) for s in sections]
    obj = loft(name, sections, mats, ring=24)
    _STATE["canopy"], _STATE["cab_sections"] = obj, sections
    zb = split_zb
    zt = max(s["zt"] for s in sections)
    split = zb + (zt - zb) * roof_from
    y0, y1 = sections[0]["y"], sections[-1]["y"]
    span = y1 - y0
    b_pillar = y0 + span * 0.52
    for f in obj.data.polygons:
        if f.center.z < split and abs(f.normal.z) < 0.97:
            f.material_index = 1
            side = abs(f.normal.x) > 0.55 and abs(f.normal.y) < 0.6
            if side and abs(f.center.y - b_pillar) < span * 0.05:
                f.material_index = 2  # black B-pillar: separate front/rear side windows
            elif f.center.z > split - (zt - zb) * 0.07:
                f.material_index = 2  # black window frame along the roof edge
    return obj


def cut_arches(body, wheels_xyr, width=0.7, radii=None, verts=24):
    """Boolean wheel arches: cylinders slightly larger than the wheels (radii: per-wheel
    override, e.g. capped below a low shoulder line)."""
    _STATE["wheels"] = list(wheels_xyr)
    _STATE["arch_radii"] = list(radii) if radii else [r * 1.18 for (_, _, r) in wheels_xyr]
    for (x, y, r), rad in zip(wheels_xyr, _STATE["arch_radii"]):
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=rad, depth=width, location=(x, y, r),
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


def lathe(name, profile, mats_idx, mats, segments=22):
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
    """Tyre (rounded sidewalls) + dished alloy: rim barrel with lip, radial spokes, brake disc and
    centre cap. Axle along X, origin at the hub (Godot spins it about X)."""
    w = width / 2
    side = -1 if x < 0 else 1  # outer face points away from the car
    g = r * 0.975  # two circumferential tread grooves
    prof = [(r * 0.64, -w), (r * 0.86, -w * 1.02), (r * 0.97, -w * 0.85), (r, -w * 0.45),
            (r, -w * 0.2), (g, -w * 0.18), (g, -w * 0.1), (r, -w * 0.08), (r, w * 0.08), (g, w * 0.1), (g, w * 0.18),
            (r, w * 0.2), (r, w * 0.45), (r * 0.97, w * 0.85), (r * 0.86, w * 1.02), (r * 0.64, w)]
    tyre = lathe(name, prof, [0] * (len(prof) - 1), [P["Rubber"]], segments=24)
    rr = r * 0.66
    barrel = lathe(name + "_barrel", [(rr * 0.9, -w * 0.8), (rr, -w * 0.7), (rr, w * 0.6), (rr * 1.04, w * 0.72), (rr * 0.93, w * 0.78)],
                   [0, 0, 0, 0], [P[rim_mat]], segments=22)
    if side < 0:
        barrel.scale = (-1, 1, 1)
    brake = disc(name + "_brake", rr * 0.78, 0.05, (-side * w * 0.2, 0, 0), P["Brake"], axis="X", verts=18)
    cap = disc(name + "_cap", rr * 0.24, 0.08, (side * w * 0.62, 0, 0), P[rim_mat], axis="X", verts=12)
    hubface = disc(name + "_hubface", rr * 0.32, 0.06, (side * w * 0.52, 0, 0), P["Trim"], axis="X", verts=12)
    parts = [barrel, brake, cap, hubface]
    for k in range(5):  # wheel nuts around the centre cap
        a = 2 * math.pi * k / 5 + 0.3
        parts.append(disc(name + f"_nut{k}", 0.013, 0.03, (side * (w * 0.52 + 0.035), math.sin(a) * rr * 0.28, math.cos(a) * rr * 0.28),
                          P["Chrome"], axis="X", verts=6))
    for k in range(spokes):
        a = 2 * math.pi * k / spokes
        # long axis along local Z, rotated about X so it points radially outward at angle a
        sp = rounded_box(name + f"_sp{k}", (0.07, 0.07 if spokes > 7 else 0.1, rr * 0.72),
                         (side * w * 0.5, math.sin(a) * rr * 0.55, math.cos(a) * rr * 0.55), P[rim_mat], bevel=0.015, segs=1,
                         rot=(-a, 0, 0))
        parts.append(sp)
    join(tyre, parts)
    tyre.location = (x, y, r)
    return tyre


def apply_mods(o):
    """Bake an object's modifiers (subsurf/bevel) into its mesh."""
    if o.type != "MESH" or not o.modifiers:
        return
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def join(target, others):
    # object.join keeps only the active object's modifiers: bake everyone's first, otherwise
    # subdivided canopies/cabs export as their coarse cage (details projected onto the smooth
    # surface would then end up inside it)
    for o in [target] + list(others):
        apply_mods(o)
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


def blob(name, radius, loc, mat, scale=(1, 1, 1), segs=12, rings=8):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    obj = to_object(name, bm, [mat])
    obj.location, obj.scale = loc, scale
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


# ---------- surface-conforming details (A1 detail pass) ----------
#
# Lamps, grilles, plates, vents and panel lines are projected onto the finished body shell and
# lifted a few millimetres along its normal, so they hug any curvature (flush, like real cars)
# and never overlap the paint at a grazing angle (that z-fights = flicker). Layers on top of each
# other (housing → lens) are ≥ 6 mm apart.

_STATE = {}  # this car's body / canopy / wheel arches, set by cut_arches/finalize_body/cabin


def _hit(target, origin, direction):
    deps = bpy.context.evaluated_depsgraph_get()
    ok, loc, n, _ = target.ray_cast(Vector(origin), Vector(direction).normalized(), depsgraph=deps)
    return (loc, n) if ok else (None, None)


def patch(name, target, center, half, toward, mat, off=0.008, depth=0.03, p=4.0, slant=0.0,
          rings=3, segs=20, shift=(0.0, 0.0), up=(0, 0, 1)):
    """Superellipse patch (half sizes `half`, exponent p, top edge shifted by `slant`·half_x) in
    the plane through `center` perpendicular to `toward` (pointing INTO the body), projected onto
    `target` and lifted `off`; its rim sinks `depth` back so no gap shows on curved panels."""
    t = Vector(toward).normalized()
    U = Vector(up).cross(t).normalized()
    V = t.cross(U).normalized()
    c0 = Vector(center) + U * shift[0] + V * shift[1]

    def proj(u, v):
        for s in (1.0, 0.85, 0.7, 0.5, 0.3, 0.0):  # off the edge of the shell: pull inwards
            q = c0 + U * (half[0] * (u + slant * v) * s) + V * (half[1] * v * s)
            loc, n = _hit(target, q - t * 2.0, t)
            if loc is not None:
                return loc, (n if n.dot(t) < 0 else -n)
        return q, -t

    bm = bmesh.new()
    loc, n = proj(0.0, 0.0)
    centre = bm.verts.new(loc + n * off)
    ring_v, back = [], []
    for k in range(1, rings + 1):
        sc = k / rings
        ring = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            ca, sa = math.cos(a), math.sin(a)
            loc, n = proj(sc * math.copysign(abs(ca) ** (2 / p), ca), sc * math.copysign(abs(sa) ** (2 / p), sa))
            ring.append(bm.verts.new(loc + n * off))
            if k == rings:
                back.append(bm.verts.new(loc + n * (off - depth)))
        ring_v.append(ring)
    front_faces = []
    for i in range(segs):
        j = (i + 1) % segs
        front_faces.append(bm.faces.new((centre, ring_v[0][j], ring_v[0][i])))
        for a, b in zip(ring_v, ring_v[1:]):
            front_faces.append(bm.faces.new((a[i], a[j], b[j], b[i])))
        bm.faces.new((ring_v[-1][i], ring_v[-1][j], back[j], back[i]))
    bm.normal_update()
    if front_faces[0].normal.dot(t) > 0:  # winding faces into the body: flip everything
        for f in bm.faces:
            f.normal_flip()
    for f in front_faces:
        f.smooth = True
    return to_object(name, bm, [mat])


def surface_line(name, target, starts, direction, width, mat, off=0.004, keep=None, sink=0.012):
    """Thin strip following the shell along the hits of rays from `starts` (panel gaps, skirts,
    wipers). keep(normal) filters hits (e.g. only the top of the hood)."""
    hits = []
    for q in starts:
        loc, n = _hit(target, q, direction)
        if loc is None:
            continue
        n = n if n.dot(Vector(direction)) < 0 else -n
        if keep is None or keep(n):
            hits.append((loc, n))
    if len(hits) < 2:
        return None
    bm = bmesh.new()
    rows = []
    for i, (p, n) in enumerate(hits):
        a = hits[max(i - 1, 0)][0]
        b = hits[min(i + 1, len(hits) - 1)][0]
        tdir = (b - a).normalized()
        side = tdir.cross(n).normalized() * (width / 2)
        rows.append([bm.verts.new(p + n * off - side), bm.verts.new(p + n * off + side),
                     bm.verts.new(p - n * sink + side), bm.verts.new(p - n * sink - side)])
    for r0, r1 in zip(rows, rows[1:]):
        for k in range(4):
            m = (k + 1) % 4
            bm.faces.new((r0[k], r0[m], r1[m], r1[k]))
    bm.faces.new(rows[0])
    bm.faces.new(list(reversed(rows[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return to_object(name, bm, [mat])


def _x_extent(body, y, z):
    loc, _ = _hit(body, (3.0, y, z), (-1, 0, 0))
    return loc.x if loc is not None else None


def _facing(body, origin, direction, limit=0.45):
    loc, n = _hit(body, origin, direction)
    return loc is not None and n.dot(Vector(direction).normalized()) < -limit


def _face_band(body, y_from, direction, x=0.0):
    """(lowest, highest) z where the shell faces along −direction (the nose or tail face)."""
    zs = [0.1 + i * 0.02 for i in range(80) if _facing(body, (x, y_from, 0.1 + i * 0.02), direction)]
    return (min(zs), max(zs)) if zs else (0.35, 0.8)


def _fit(body, y_from, direction, z, want, limit=0.6):
    """Half width ≤ want that stays on the part of the shell facing along −direction at height z."""
    x = 0.0
    while x < want and _facing(body, (x + 0.02, y_from, z), direction, limit) and _facing(body, (-x - 0.02, y_from, z), direction, limit):
        x += 0.02
    return x * 0.9


def plate(body, P, origin, direction):
    """Number plate on a little mount: a flat plate standing off the curved bumper (as real ones do)."""
    loc, n = _hit(body, origin, direction)
    if loc is None:
        return []
    n = Vector((0.0, n.y, n.z)).normalized()
    if n.dot(Vector(direction)) > 0:
        n = -n
    tilt = math.atan2(n.z, abs(n.y)) * (1 if n.y > 0 else -1)
    c = loc + n * 0.03
    pl = rounded_box("plate", (0.44, 0.018, 0.11), c, P["Plate"], bevel=0.006, segs=1, rot=(tilt, 0, 0))
    tx = rounded_box("plate_txt", (0.32, 0.01, 0.035), c + n * 0.012, P["Trim"], bevel=0.0, rot=(tilt, 0, 0))
    return [pl, tx]


def arch_liners(body, wheels, mat):
    """Inside faces of the boolean wheel arches → dark plastic liner (no paint-coloured cave)."""
    names = [m.name if m else "" for m in body.data.materials]
    if mat.name not in names:
        body.data.materials.append(mat)
        names.append(mat.name)
    mi = names.index(mat.name)
    radii = _STATE.get("arch_radii") or [r * 1.18 for (_, _, r) in wheels]
    for f in body.data.polygons:
        c, n = f.center, f.normal
        for (x, y, r), R in zip(wheels, radii):
            to_axis = Vector((0.0, y - c.y, r - c.z))
            d = to_axis.length
            if abs(d - R) < 0.07 and abs(abs(c.x) - abs(x)) < 0.4 and d > 1e-6 and n.dot(to_axis / d) > 0.5:
                f.material_index = mi
                break


def lamp(target, P, center, toward, kind, side, hl=None):
    """Headlight / tail light cluster on the right (side=+1) or left (−1) of the car."""
    parts = []
    t = Vector(toward)
    # U axis of the patch points +X for front lamps, −X for rear lamps: outward = side·sign
    outward = side * (1 if t.y < 0 else -1)
    o = dict(hl or {})
    if kind == "head":
        half = o.get("half", (0.17, 0.075))
        slant = o.get("slant", 0.25) * outward
        parts.append(patch("hl_housing", target, center, half, t, P["Housing"], off=0.006, slant=slant, p=o.get("p", 3.5),
                           rings=4, segs=28))
        parts.append(patch("hl_reflector", target, center, (half[0] * 0.8, half[1] * 0.62), t, P["Chrome"], off=0.011,
                           slant=slant, p=4.0, rings=2, segs=20, shift=(0.0, -half[1] * 0.1)))
        parts.append(patch("hl_projector", target, center, (half[0] * 0.2, half[1] * 0.36), t, P["Light"], off=0.017,
                           p=3.0, rings=1, segs=14, shift=(-outward * half[0] * 0.38, -half[1] * 0.12)))
        parts.append(patch("hl_drl", target, center, (half[0] * 0.86, half[1] * 0.12), t, P["Light"], off=0.017, p=8.0,
                           rings=1, segs=18, slant=slant, shift=(0.0, half[1] * 0.68)))
    else:
        half = o.get("half", (0.19, 0.065))
        slant = o.get("slant", 0.2) * outward
        parts.append(patch("tl_housing", target, center, half, t, P["TailHousing"], off=0.006, slant=slant, p=o.get("p", 4.0),
                           rings=4, segs=28))
        parts.append(patch("tl_bar", target, center, (half[0] * 0.78, half[1] * 0.38), t, P["TailLight"], off=0.014, p=6.0,
                           rings=2, segs=16, slant=slant, shift=(outward * half[0] * 0.08, half[1] * 0.18)))
        parts.append(patch("tl_reverse", target, center, (half[0] * 0.18, half[1] * 0.26), t, P["Lens"], off=0.014, p=4.0,
                           rings=1, segs=12, shift=(-outward * half[0] * 0.62, -half[1] * 0.42)))
    return parts


def interior(P):
    """Cabin interior seen through the clear glass: dark floor/tub, two front seats with
    headrests, dashboard and steering wheel (left-hand drive). Every part is sized to the
    canopy's local roof height so nothing pokes through the glass on low, sloped cabins."""
    cab = sorted(_STATE["cab_sections"], key=lambda s: s["y"])
    belt, top = _STATE["cab_belt"], _STATE["cab_top"]
    H = top - belt
    y0, y1 = cab[0]["y"], cab[-1]["y"]
    span = y1 - y0

    def room(y):  # inner height above the belt at y (canopy shell ~6 cm thick + margin)
        for a, b in zip(cab, cab[1:]):
            if a["y"] <= y <= b["y"]:
                t = (y - a["y"]) / max(b["y"] - a["y"], 1e-6)
                return (a["zt"] + (b["zt"] - a["zt"]) * t) - belt - 0.1
        return 0.0

    mid = [s for s in cab if s["zt"] > belt + H * 0.6] or cab
    wi = min(s["w"] for s in mid) * 0.8
    out = [rounded_box("floor", (2 * wi, span * 0.86, 0.05), (0, (y0 + y1) / 2, belt + 0.02), P["Interior"], bevel=0.02, segs=1)]
    seat_x = wi * 0.48
    # front seats where the roof is highest (driver's head room)
    ys = max((y0 + span * f for f in (0.4, 0.45, 0.5, 0.55, 0.6)), key=room)
    h = max(min(room(ys - 0.3), H * 0.82), 0.2)  # seat back + headrest height
    for x in (seat_x, -seat_x):
        out.append(rounded_box("seat", (wi * 0.72, 0.4, 0.08), (x, ys, belt + 0.07), P["Seat"], bevel=0.03, segs=1))
        out.append(rounded_box("seat_back", (wi * 0.72, 0.09, h * 0.72), (x, ys - 0.22, belt + 0.07 + h * 0.36),
                               P["Seat"], bevel=0.03, segs=1, rot=(0.2, 0, 0)))
        out.append(rounded_box("headrest", (wi * 0.42, 0.08, h * 0.18), (x, ys - 0.3, belt + h * 0.86),
                               P["Seat"], bevel=0.025, segs=1))
    # dashboard + wheel: from the windscreen base back to where there is room for them
    yd = y1 - span * 0.12
    while yd > ys + 0.3 and room(yd + 0.15) < 0.2:  # its front edge must fit under the windscreen
        yd -= 0.04
    hd = max(min(room(yd + 0.15) - 0.04, H * 0.22), 0.06)
    out.append(rounded_box("dash", (2 * wi * 0.96, 0.3, hd), (0, yd, belt + hd / 2 + 0.02), P["Interior"], bevel=0.03, segs=1))
    r = min(H * 0.16, room(yd - 0.2) * 0.35)
    sw = disc("steering", r, 0.03, (-seat_x, yd - 0.22, belt + hd + r * 0.6), P["Trim"], axis="Y", verts=14)
    sw.rotation_euler = (math.pi / 2 - 0.45, 0, 0)
    out.append(sw)
    return out


def window_line(canopy, P):
    """Chrome strip along the bottom edge of the side windows (both sides)."""
    cab = _STATE["cab_sections"]
    y0, y1 = min(s["y"] for s in cab), max(s["y"] for s in cab)
    z = _STATE["cab_belt"] + 0.035
    out = []
    for side in (1, -1):
        starts = [(side * 3.0, y0 + (y1 - y0) * (0.08 + 0.84 * i / 16), z) for i in range(17)]
        ln = surface_line("window_line", canopy, starts, (-side, 0, 0), 0.022, P["Chrome"], off=0.006,
                          keep=lambda n, s=side: n.x * s > 0.4)
        if ln:
            out.append(ln)
    return out


def wipers(canopy, P):
    """Two dark wiper arms lying at the base of the windscreen."""
    front = max(_STATE["cab_sections"], key=lambda s: s["y"])
    z0 = front["zt"] + 0.07
    out = []
    for xs in ((0.06, 0.6), (-0.5, 0.0)):
        starts = [(x, front["y"] + 3.0, z0 + (x - xs[0]) * 0.1) for x in [xs[0] + (xs[1] - xs[0]) * i / 7 for i in range(8)]]
        w = surface_line("wiper", canopy, starts, (0, -1, 0), 0.022, P["Trim"], off=0.012, sink=0.0)
        if w:
            out.append(w)
    return out


def standard_details(P, front, rear, mirror, grille=None, bumper_w=1.5, bumper_z=0.42, doors=None, plates=True,
                     hl=None, tl=None, target=None, hood_back=0.32):
    """Lamp clusters, grille, intakes, plates, diffuser, panel gaps, side skirts, door handles,
    indicators, mirrors, wipers, arch liners and brake calipers.
    front/rear: (x, y, z) of the right lamp centre; mirror: (x, y, z); grille: (width, y, z);
    doors: dict(z0, z1, seams=[y…], handles=[y…]); hl/tl: dict(half=(hx, hz), slant, p);
    target: shell to project onto when it isn't the main body (e.g. a separate cab)."""
    body = target or _STATE.get("body")
    parts = []
    mx, my, mz = mirror
    # wing mirror: slim painted housing on a black stalk, glass on the rear face
    mi = rounded_box("mirror", (0.19, 0.075, 0.1), (mx + 0.07, my, mz), P["Paint"], bevel=0.032, segs=2, rot=(0, 0, -0.12))
    stalk = tube("mirror_stalk", (mx - 0.12, my + 0.01, mz - 0.07), (mx + 0.0, my, mz - 0.02), 0.022, P["Trim"], verts=6)
    mglass = rounded_box("mirror_glass", (0.155, 0.012, 0.072), (mx + 0.075, my - 0.042, mz), P["Housing"], bevel=0.008,
                         segs=1, rot=(0, 0, -0.12))
    group = [mi, stalk, mglass]
    parts += group + mirror_x(group)
    if body is None:
        return parts
    fy = front[1]
    ry = rear[1]
    _, nf = _hit(body, (front[0], fy + 3.0, front[2]), (0, -1, 0))
    _, nr = _hit(body, (rear[0], ry - 3.0, rear[2]), (0, 1, 0))
    tf = -(nf if nf is not None else Vector((0, 1, 0)))
    tr = -(nr if nr is not None else Vector((0, -1, 0)))
    for side in (1, -1):
        parts += lamp(body, P, (front[0] * side, fy, front[2]), (tf.x * side, tf.y, tf.z), "head", side, hl)
        parts += lamp(body, P, (rear[0] * side, ry, rear[2]), (tr.x * side, tr.y, tr.z), "tail", side, tl)
    # --- vertical layout from the real shell: the forward/backward facing band of the nose/tail ---
    flo, _fhi = _face_band(body, fy + 3.0, (0, -1, 0))
    rlo, _rhi = _face_band(body, ry - 3.0, (0, 1, 0))
    zi = max(bumper_z - 0.02, flo + 0.11)  # intake / front plate
    zd = rlo + 0.07  # diffuser
    zrp = max(bumper_z + 0.13, zd + 0.14)  # rear plate
    # --- front: grille with chrome slats + badge, lower intake, fog lamps ---
    if grille:
        gw, gy, gz = grille
        parts.append(patch("grille", body, (0, gy, gz), (gw / 2, 0.07), (0, -1, 0), P["Trim"], off=0.006, p=5.0))
        for k, dz in enumerate((-0.036, 0.0, 0.036)):
            parts.append(patch(f"slat{k}", body, (0, gy, gz + dz), (gw / 2 * 0.9, 0.0065), (0, -1, 0), P["Chrome"],
                               off=0.012, p=8.0, rings=1, segs=16))
        parts.append(patch("badge", body, (0, gy, gz), (0.04, 0.028), (0, -1, 0), P["Chrome"], off=0.018, p=2.0, rings=1, segs=14))
    iw = _fit(body, fy + 3.0, (0, -1, 0), zi, bumper_w * 0.32)
    parts.append(patch("intake", body, (0, fy, zi), (iw, 0.05), (0, -1, 0), P["Trim"], off=0.006, p=4.0, rings=3, segs=24))
    for k in range(5):  # intake mesh bars
        parts.append(patch(f"intake_bar{k}", body, (0, fy, zi), (0.006, 0.044), (0, -1, 0), P["Housing"],
                           off=0.012, p=6.0, rings=1, segs=10, shift=((k - 2) * iw * 0.36, 0.0)))
    for side in (1, -1):
        if _facing(body, (side * bumper_w * 0.4, fy + 3.0, zi), (0, -1, 0)):
            parts.append(patch("fog", body, (side * bumper_w * 0.4, fy, zi), (0.042, 0.028), (0, -1, 0), P["Lens"],
                               off=0.01, p=2.4, rings=2, segs=14))
    # --- rear: diffuser with fins, reflectors ---
    dw = _fit(body, ry - 3.0, (0, 1, 0), zd, bumper_w * 0.38)
    parts.append(patch("diffuser", body, (0, ry, zd), (dw, 0.055), (0, 1, 0), P["Trim"], off=0.006, p=5.0, rings=3, segs=24))
    for k in range(5):
        parts.append(patch(f"fin{k}", body, (0, ry, zd), (0.008, 0.05), (0, 1, 0), P["Housing"], off=0.012,
                           p=6.0, rings=1, segs=10, shift=((k - 2) * dw * 0.38, 0.0)))
    for side in (1, -1):
        if _facing(body, (side * bumper_w * 0.42, ry - 3.0, zd + 0.05), (0, 1, 0)):
            parts.append(patch("reflector", body, (side * bumper_w * 0.42, ry, zd + 0.05), (0.06, 0.014), (0, 1, 0), P["Reflector"],
                               off=0.01, p=6.0, rings=1, segs=12))
    if plates:
        parts += plate(body, P, (0, fy + 3.0, zi), (0, -1, 0))
        parts += plate(body, P, (0, ry - 3.0, zrp), (0, 1, 0))
    # --- panel gaps: hood, trunk (projected from above) ---
    top = lambda n: n.z > 0.55  # noqa: E731
    cab = _STATE.get("cab_sections")
    hood_y = fy - hood_back  # shut line between bumper/lamps and the hood
    lines = [(hood_y, None)]
    if cab:
        lines.append((min(s["y"] for s in cab) - 0.12, None))
    for k, (yv, _) in enumerate(lines):
        starts = [(-1.3 + 2.6 * i / 26, yv, 3.0) for i in range(27)]
        ln = surface_line(f"gap{k}", body, starts, (0, 0, -1), 0.012, P["Trim"], keep=top)
        if ln:
            parts.append(ln)
    hw = _x_extent(body, hood_y, front[2])
    if hw and cab:
        y_ws = max(s["y"] for s in cab)
        for side in (1, -1):
            starts = [(side * hw * 0.8, hood_y + (y_ws - hood_y) * i / 10, 3.0) for i in range(11)]
            ln = surface_line("hood_side", body, starts, (0, 0, -1), 0.012, P["Trim"], keep=top)
            if ln:
                parts.append(ln)
    # --- sides: door gaps, handles, skirts, indicator repeaters ---
    wheels = _STATE.get("wheels", [])
    fw = max(wheels, key=lambda w: w[1]) if wheels else None
    rw = min(wheels, key=lambda w: w[1]) if wheels else None
    for side in (1, -1):
        sidef = (lambda n, s=side: n.x * s > 0.35)
        if doors:
            for yv in doors.get("seams", []):
                starts = [(side * 3.0, yv, doors["z0"] + (doors["z1"] - doors["z0"]) * i / 10) for i in range(11)]
                ln = surface_line("seam", body, starts, (-side, 0, 0), 0.012, P["Trim"], keep=sidef)
                if ln:
                    parts.append(ln)
            for yv in doors.get("handles", []):
                parts.append(patch("handle", body, (side, yv, doors["z1"] - 0.08), (0.08, 0.017), (-side, 0, 0), P["Chrome"],
                                   off=0.012, p=4.0, rings=2, segs=14))
                parts.append(patch("handle_cup", body, (side, yv, doors["z1"] - 0.08), (0.095, 0.03), (-side, 0, 0), P["Trim"],
                                   off=0.005, p=3.0, rings=1, segs=14))
        if fw and rw:
            zs = (doors["z0"] + 0.02) if doors else bumper_z
            y0, y1 = rw[1] + rw[2] * 1.2, fw[1] - fw[2] * 1.2
            starts = [(side * 3.0, y0 + (y1 - y0) * i / 12, zs) for i in range(13)]
            ln = surface_line("skirt", body, starts, (-side, 0, 0), 0.075, P["Trim"], off=0.008, keep=sidef)
            if ln:
                parts.append(ln)
            zi = (doors["z1"] - 0.14) if doors else front[2]
            parts.append(patch("repeater", body, (side, fw[1] - fw[2] * 1.45, zi), (0.045, 0.016), (-side, 0, 0), P["Amber"],
                               off=0.01, p=3.0, rings=1, segs=12))
    if wheels:
        arch_liners(body, wheels, P["Trim"])
        for (x, y, r) in wheels:  # brake calipers sit on the body (they don't spin with the wheel)
            parts.append(rounded_box("caliper", (0.07, 0.16, 0.1), (x * 0.985, y - r * 0.3, r + r * 0.3), P["Caliper"],
                                     bevel=0.02, segs=1, rot=(0.785, 0, 0)))
    canopy = _STATE.get("canopy")
    if canopy is not None and cab:
        parts += wipers(canopy, P)
        parts += interior(P)
        parts += window_line(canopy, P)
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
    _STATE["body"] = body
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    for m in list(body.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    apply_and_clean()
    # keep the smooth panels smooth but give the boolean arch rims crisp edges (no creases)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=1.05)  # only the ~90° arch rims stay crisp
    except (AttributeError, RuntimeError):
        pass


def export(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)


def turntable(png_path, size=480):
    size = int(os.environ.get("CAR_PREVIEW_SIZE", size))
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
    target.location = (0, 0, float(os.environ.get("CAR_PREVIEW_LOOKZ", "0.75")))
    c = cam.constraints.new("TRACK_TO")
    c.target, c.track_axis, c.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
    base = os.path.splitext(png_path)[0]
    tiles = []
    angles = [float(v) for v in os.environ.get("CAR_PREVIEW_ANGLES", "40,140,220,320").split(",")]
    for i, a in enumerate(angles):
        r = math.radians(a)
        dist = float(os.environ.get("CAR_PREVIEW_DIST", "7.0"))  # e.g. 4.0 for detail close-ups
        cam.location = (dist * math.sin(r), dist * math.cos(r), 2.6 * dist / 7.0)
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


KEEP = ("Paint", "Glass", "GlassClear")


def _base_color(m):
    b = m.node_tree.nodes.get("Principled BSDF") if m.use_nodes else None
    return tuple(b.inputs["Base Color"].default_value) if b else (0.5, 0.5, 0.5, 1.0)


def _is_lamp(m):
    b = m.node_tree.nodes.get("Principled BSDF") if m.use_nodes else None
    return b is not None and "Emission Strength" in b.inputs and b.inputs["Emission Strength"].default_value > 0.5 \
        and m.name not in KEEP


def _surface(m):
    """(metallic, roughness) of a source material. The merged Detail surface carries them in its UV
    channel (u = metallic, v = roughness; glTF drops vertex alpha), read by Godot's
    car_detail.gdshader, so chrome, rubber and plastic keep their own look."""
    b = m.node_tree.nodes.get("Principled BSDF") if (m is not None and m.use_nodes) else None
    metal = b.inputs["Metallic"].default_value if b else 0.25
    rough = b.inputs["Roughness"].default_value if b else 0.45
    return (metal, rough)


def consolidate():
    """Draw-call budget (GAME_PLAN §8): per mesh keep Paint and Glass, bake every other material's
    colour into vertex colours and merge them into two materials: Detail (opaque) and Lamp
    (emissive). Bodies end up with ≤ 4 surfaces, wheels with 1."""
    detail = bpy.data.materials.get("Detail") or bpy.data.materials.new("Detail")
    lamp = bpy.data.materials.get("Lamp") or bpy.data.materials.new("Lamp")
    for mat, emit in ((detail, False), (lamp, True)):
        mat.use_nodes = True
        nt = mat.node_tree
        b = nt.nodes["Principled BSDF"]
        vc = nt.nodes.get("vc") or nt.nodes.new("ShaderNodeVertexColor")
        vc.name, vc.layer_name = "vc", "Col"
        nt.links.new(vc.outputs["Color"], b.inputs["Base Color"])
        b.inputs["Metallic"].default_value = 0.25
        b.inputs["Roughness"].default_value = 0.45
        if emit:
            for key in ("Emission Color", "Emission"):
                if key in b.inputs:
                    nt.links.new(vc.outputs["Color"], b.inputs[key])
                    break
            b.inputs["Emission Strength"].default_value = 3.0
    for o in bpy.context.scene.objects:
        if o.type != "MESH" or o.get("cutter"):
            continue
        me = o.data
        if "Col" not in me.color_attributes:
            me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        col = me.color_attributes["Col"]
        for uvl in list(me.uv_layers):
            me.uv_layers.remove(uvl)
        uv = me.uv_layers.new(name="Surf")
        old = [s.material for s in o.material_slots]
        new_slots, remap = [], {}
        for i, m in enumerate(old):
            target = m if (m is not None and m.name in KEEP) else (lamp if (m is not None and _is_lamp(m)) else detail)
            if target not in new_slots:
                new_slots.append(target)
            remap[i] = new_slots.index(target)
        for poly in me.polygons:
            src = old[poly.material_index] if old else None
            c = _base_color(src) if src else (0.5, 0.5, 0.5, 1)
            mr = _surface(src)
            for li in poly.loop_indices:
                col.data[li].color = c
                uv.data[li].uv = mr
        idx = [remap.get(p.material_index, 0) for p in me.polygons]
        me.materials.clear()
        for m in new_slots:
            me.materials.append(m)
        for poly, i in zip(me.polygons, idx):
            poly.material_index = i


def run(build):
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    reset()
    build()
    consolidate()
    print(f"CAR_TRIS {triangles()}")
    if os.environ.get("CAR_BREAKDOWN"):
        deps = bpy.context.evaluated_depsgraph_get()
        for o in bpy.context.scene.objects:
            if o.type == "MESH":
                me = o.evaluated_get(deps).to_mesh()
                me.calc_loop_triangles()
                print(f"  PART {o.name:14s} {len(me.loop_triangles):6d}")
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
