"""Shared helpers for the environment kits (graphics pass 5): vertex-coloured meshes built with
bmesh, one material per kit ("Col" byte colour layer, sRGB values, exported as COLOR_0)."""
import math

import bmesh
import bpy
from mathutils import Vector


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def mul(a, k):
    return tuple(min(1.0, a[i] * k) for i in range(3))


_MATS = {}


def material(name="Kit"):
    if name not in _MATS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.85
        _MATS[name] = m
    return _MATS[name]


class Builder:
    """Accumulates coloured faces into one bmesh; finish() makes the object."""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = {}

    def face(self, pts, c):
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs)
        self.col[f] = c
        return f

    def box(self, center, half, c, rot_z=0.0, top=None, shade=True):
        """Axis box (optionally rotated about Z). Faces get simple baked shading: top lighter,
        sides mid, bottom dark. `top` overrides the top colour."""
        cx, cy, cz = center
        hx, hy, hz = half
        cs, sn = math.cos(rot_z), math.sin(rot_z)

        def P(x, y, z):
            return Vector((cx + x * cs - y * sn, cy + x * sn + y * cs, cz + z))
        v = [P(sx * hx, sy * hy, sz * hz) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
        quads = [((0, 1, 3, 2), 0.55), ((4, 6, 7, 5), 1.08), ((0, 4, 5, 1), 0.9), ((2, 3, 7, 6), 0.82),
                 ((0, 2, 6, 4), 0.86), ((1, 5, 7, 3), 0.94)]
        for idx, k in quads:
            cc = (top if (top is not None and k > 1.0) else c)
            self.face([v[i] for i in idx], mul(cc, k) if shade else cc)

    def prism_roof(self, x0, x1, y0, y1, z, rise, c, gable=None, thick=0.15):
        """Gable roof along X: eaves at y0/y1 (height z), ridge at y-centre (z + rise)."""
        ym = (y0 + y1) / 2
        a, b = Vector((x0, y0, z)), Vector((x1, y0, z))
        r0, r1 = Vector((x0, ym, z + rise)), Vector((x1, ym, z + rise))
        c2, d = Vector((x0, y1, z)), Vector((x1, y1, z))
        t = Vector((0, 0, thick))
        self.face([a + t, b + t, r1 + t, r0 + t], mul(c, 1.05))
        self.face([d + t, c2 + t, r0 + t, r1 + t], mul(c, 0.85))
        self.face([a, r0, r1, b], mul(c, 0.4))  # underside
        self.face([c2, d, r1, r0], mul(c, 0.4))
        for (p, q) in ((a, b), (c2, d)):  # fascia edges
            self.face([p, q, q + t, p + t], mul(c, 0.7))
        if gable is not None:  # gable triangles (wall colour), slightly inside the roof ends
            for x, s in ((x0 + 0.25, -1), (x1 - 0.25, 1)):
                pa, pb, pr = Vector((x, y0 + 0.25, z)), Vector((x, y1 - 0.25, z)), Vector((x, ym, z + rise - 0.1))
                self.face([pa, pb, pr] if s < 0 else [pb, pa, pr], mul(gable, 0.9))

    def cylinder(self, a, b, r, c, segs=8, caps=True):
        a, b = Vector(a), Vector(b)
        d = (b - a).normalized()
        side = d.cross(Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))).normalized()
        up = side.cross(d)
        ra, rb = [], []
        for i in range(segs):
            ang = 2 * math.pi * i / segs
            o = (side * math.cos(ang) + up * math.sin(ang)) * r
            ra.append(a + o)
            rb.append(b + o)
        for i in range(segs):
            j = (i + 1) % segs
            k = 0.75 + 0.3 * (math.sin(2 * math.pi * (i + 0.5) / segs) * 0.5 + 0.5)
            self.face([ra[i], ra[j], rb[j], rb[i]], mul(c, k))
        if caps:
            self.face(list(reversed(ra)), mul(c, 0.8))
            self.face(rb, mul(c, 0.8))

    def finish(self, name, mat_name="Kit", smooth=False):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        layer = bm.loops.layers.color.new("Col")
        for f in bm.faces:
            c = self.col.get(f, (1, 1, 1))
            for loop in f.loops:
                loop[layer] = (c[0], c[1], c[2], 1.0)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ca = me.color_attributes.get("Col")
        if ca is not None:
            me.color_attributes.active_color = ca
            me.color_attributes.render_color_index = me.color_attributes.find("Col")
        obj = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(obj)
        me.materials.append(material(mat_name))
        if smooth:
            me.shade_smooth()
        else:
            me.shade_flat()
        return obj


def tris(obj):
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True,
                              export_vertex_color="ACTIVE")
