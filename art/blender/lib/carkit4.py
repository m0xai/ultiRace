"""Car kit v4 (A1 mid-poly): realistic cars, 25–50 k triangles (LOD0) + a light LOD1.

Body: one lofted, subdivided shell generated from smooth profile curves along the car
(stations of zf/zb/wb/wl/zt/wt/crown, interpolated with monotone cubic splines). Every cross
section has the same structure — bottom, lower side, SHOULDER (creased beltline), upper side
(tumblehome), roof edge, roof crown — so the greenhouse, windscreen, rear window, hood and boot
are all one surface. Windows are regions of that surface: recessed glass inset into a rubber
frame (creased, so subdivision keeps them crisp). Wheel arches are boolean cut-outs with a
lip. Details (lamps, grille, plates, gaps, …) reuse carkit2's surface-projected parts.
+Y forward, Z up, X right.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import carkit2 as k2  # noqa: E402

srgb = k2.srgb
_STATE = k2._STATE


# ---------- materials ----------

def palette(paint, accent, metallic=0.55):
    """Metallic paint with a moderate clear coat (not the glossy-plastic v2 look)."""
    P = k2.palette(paint, accent)
    P["Paint"] = k2.material("Paint", srgb(paint), metallic=metallic, rough=0.32, clearcoat=0.6)
    P["Rubber"] = k2.material("Rubber", srgb("#161617"), rough=0.9)
    P["Tread"] = k2.material("Tread", srgb("#0f0f10"), rough=0.95)
    P["Rim"] = k2.material("Rim", srgb("#b8bec7"), metallic=0.9, rough=0.25)
    P["RimDark"] = k2.material("RimDark", srgb("#2f3238"), metallic=0.7, rough=0.35)
    P["Disc"] = k2.material("Disc", srgb("#6d7076"), metallic=0.9, rough=0.5)
    P["Frame"] = k2.material("Frame", srgb("#141518"), rough=0.6)
    P["Interior"] = k2.material("Interior", srgb("#222327"), rough=0.75)
    P["Seat"] = k2.material("Seat", srgb("#34363d"), rough=0.65)
    return P


# ---------- profile curves ----------

def pchip(xs, ys):
    """Monotone cubic Hermite interpolant (no overshoot between stations)."""
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(x):
        if x <= xs[0]:
            return ys[0]
        if x >= xs[-1]:
            return ys[-1]
        i = max(j for j in range(n - 1) if xs[j] <= x)
        t = (x - xs[i]) / h[i]
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i] +
                (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1])
    return f


KEYS = ("zf", "zb", "wb", "wl", "zt", "wt", "crown")


def profile(stations):
    """stations: list of dicts with y and KEYS → function y → section dict."""
    st = sorted(stations, key=lambda s: s["y"])
    ys = [s["y"] for s in st]
    fns = {k: pchip(ys, [s[k] for s in st]) for k in KEYS}
    return lambda y: {k: fns[k](y) for k in KEYS} | {"y": y}


# Ring structure (right half, bottom centre → top centre). Index ranges are used to classify
# faces: [0, J_SIDE) bottom, [J_SIDE, J_SHOULDER) lower side, [J_SHOULDER, J_ROOF) upper
# side (side glass on the cabin), [J_ROOF, HALF) roof / hood / windscreen / rear window.
J_SIDE, J_SHOULDER, J_ROOF, HALF = 5, 11, 17, 22


def half_ring(sec):
    zf, zb, wb, wl, zt, wt, cr = (sec[k] for k in KEYS)
    rb = min(0.12, (zb - zf) * 0.35)  # bottom corner radius
    pts = []
    # bottom: centre → corner start
    for t in (0.0, 0.35, 0.7):
        pts.append((wl * t * 0.92, zf))
    # bottom corner (quarter arc)
    cx, cz = wl - rb, zf + rb
    for a in (0.35, 0.8):
        ang = -math.pi / 2 + a * math.pi / 2
        pts.append((cx + rb * math.cos(ang), cz + rb * math.sin(ang)))
    # lower side: slight outward bulge (wheel-arch line), up to just below the shoulder
    for t in (0.0, 0.25, 0.5, 0.75, 0.92, 0.985):
        z = zf + rb + (zb - zf - rb) * t
        x = wl + (wb - wl) * t + 0.025 * math.sin(math.pi * t)
        pts.append((x, z))
    # shoulder (creased) → upper side (tumblehome curve) → roof edge
    for t in (0.0, 0.12, 0.3, 0.52, 0.75, 0.92):
        e = t ** 1.15
        x = wb + (wt - wb) * e
        z = zb + (zt - zb) * (1 - (1 - t) ** 1.6)
        pts.append((x, z))
    # roof edge round → crown → centre
    for t in (0.0, 0.25, 0.5, 0.75, 0.9):
        x = wt * (1 - t) * (0.96 if t > 0 else 1)
        z = zt + cr * math.sin(math.pi / 2 * t) + 0.012 * (1 - t) * (t > 0)
        pts.append((x, z))
    assert len(pts) == HALF, len(pts)
    pts.append((0.0, zt + cr))
    return pts  # HALF + 1 points: index HALF is the top centre


def ring(sec):
    h = half_ring(sec)
    right = [Vector((x, sec["y"], z)) for (x, z) in h]
    left = [Vector((-x, sec["y"], z)) for (x, z) in reversed(h[1:HALF])]
    return right + left  # 2*HALF points, closed


# ---------- body ----------

def body(name, P, stations, cabin, n_sections=46, nose_round=(0.9, 0.6), tail_round=(0.9, 0.6)):
    """Builds the shell. cabin: dict(ws=(y_bottom, y_top), rw=(y_bottom, y_top), b=y_pillar,
    a_w, c_w, b_w = pillar widths in m). Returns the object (subdivided, applied, creased)."""
    prof = profile(stations)
    y0 = min(s["y"] for s in stations)
    y1 = max(s["y"] for s in stations)
    # denser sections near the ends and around the windscreen/rear-window bends
    ys = []
    for i in range(n_sections):
        t = i / (n_sections - 1)
        u = 0.5 - 0.5 * math.cos(math.pi * t)  # cosine spacing: denser at the ends
        ys.append(y0 + (y1 - y0) * (0.35 * t + 0.65 * u))
    secs = [prof(y) for y in ys]

    def shrink(sec, k, dy):
        zc = (sec["zf"] + sec["zt"]) / 2
        s2 = dict(sec)
        s2["y"] = sec["y"] + dy
        for key in ("wb", "wl", "wt"):
            s2[key] = sec[key] * k
        for key in ("zf", "zb", "zt"):
            s2[key] = zc + (sec[key] - zc) * k
        s2["crown"] = sec["crown"] * k
        return s2
    a, b = secs[0], secs[-1]
    secs = [shrink(a, tail_round[1], -0.06), shrink(a, tail_round[0], -0.025)] + secs + \
           [shrink(b, nose_round[0], 0.025), shrink(b, nose_round[1], 0.06)]
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in ring(s)] for s in secs]
    n = 2 * HALF
    faces = {}
    for i in range(len(rings) - 1):
        for j in range(n):
            jj = (j + 1) % n
            f = bm.faces.new((rings[i][j], rings[i][jj], rings[i + 1][jj], rings[i + 1][j]))
            faces[(i, j)] = f
    cap0 = bm.faces.new(list(reversed(rings[0])))
    cap1 = bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mats = [P["Paint"], P["GlassClear"], P["Frame"]]
    # classify window faces on the cage (cabin=None: open car / no glass; rw=None: upright cab
    # back, rear window added as a patch by the car script)
    cabin_ = cabin or dict(ws=(99, 99), rw=None, b=0, back=99)
    ws0, ws1 = cabin_["ws"]
    rw0, rw1 = cabin_["rw"] if cabin_.get("rw") else (-99, -99)

    def band(j):
        jr = j if j < HALF else n - 1 - j
        if jr < J_SIDE:
            return "bottom"
        if jr < J_SHOULDER:
            return "lower"
        if jr < J_ROOF:
            return "upper"
        return "roof"
    regions = {"ws": [], "rw": [], "sideR0": [], "sideR1": [], "sideL0": [], "sideL1": []}
    for (i, j), f in faces.items():
        yc = (secs[i]["y"] + secs[i + 1]["y"]) / 2
        bnd = band(j)
        right = j < HALF
        if bnd == "roof" and ws0 + 0.02 < yc < ws1 - 0.01:
            regions["ws"].append(f)
        elif bnd == "roof" and rw0 + 0.01 < yc < rw1 - 0.02:
            regions["rw"].append(f)
        elif bnd == "upper" and cabin is not None:
            jr = j if right else n - 1 - j
            if jr < J_SHOULDER + 1 or jr > J_ROOF - 2:
                continue  # keep a paint strip below/above the glass (belt + roof rail)
            back = rw1 if cabin_.get("rw") else cabin_["back"]
            lo, hi = back + cabin_.get("c_w", 0.1), ws1 - cabin_.get("a_w", 0.08)
            if not (lo < yc < hi):
                continue
            bw = cabin_.get("b_w", 0.09)
            if cabin_.get("b") is not None and abs(yc - cabin_["b"]) < bw / 2:
                continue
            key = ("sideR" if right else "sideL") + ("1" if cabin_.get("b") is None or yc > cabin_["b"] else "0")
            regions[key].append(f)
    glass_i, frame_i = 1, 2
    crease = bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")
    for key, fs in regions.items():
        if not fs:
            continue
        res = bmesh.ops.inset_region(bm, faces=fs, thickness=0.028, depth=-0.014, use_even_offset=True)
        for f in fs:
            f.material_index = glass_i
        for f in res["faces"]:
            f.material_index = frame_i
        # crisp frames: crease the glass border and the outer frame border
        for f in fs:
            for e in f.edges:
                if any(l.material_index != glass_i for l in e.link_faces):
                    e[crease] = 1.0
        for f in res["faces"]:
            for e in f.edges:
                if any(l.material_index == 0 for l in e.link_faces):
                    e[crease] = 0.9
    # shoulder (beltline) crease along the whole car
    for i in range(len(rings)):
        for jr in (J_SHOULDER,):
            for j in (jr, n - jr):
                v = rings[i][j % n]
                for e in v.link_edges:
                    o = e.other_vert(v)
                    if i + 1 < len(rings) and o is rings[i + 1][j % n]:
                        e[crease] = max(e[crease], 0.55)
    obj = k2.to_object(name, bm, mats)
    sub = obj.modifiers.new("subd", "SUBSURF")
    sub.levels = sub.render_levels = 1
    for p in obj.data.polygons:
        p.use_smooth = True
    _STATE["stations"], _STATE["cabin"], _STATE["profile"] = stations, cabin, prof
    return obj


def arches(obj, wheels, P, width=0.75, clearance=1.13, lip=True):
    """Boolean wheel arches + dark liners (reuses carkit2), plus a slim arch lip."""
    prof = _STATE["profile"]
    # arch top stays ≥ 5 cm below the shoulder crease (else it bites into the hood/fender top)
    radii = [min(r * clearance, prof(y)["zb"] - r - 0.05) for (x, y, r) in wheels]
    k2.cut_arches(obj, wheels, width=width, radii=radii, verts=48)
    k2.finalize_body(obj)
    k2.arch_liners(obj, wheels, P["Trim"])
    parts = []  # (arch lips: later)
    return parts


# ---------- wheels ----------

def wheel(name, x, y, r, width, P, spokes=5, rim_mat="Rim", twin=True, rim_ratio=0.72):
    """Mid-poly wheel: tyre with sidewall bulge and tread blocks, rim barrel and lip, (twin)
    spokes, centre cap, lug nuts, brake disc. Axle along X, origin at the hub."""
    w = width / 2
    side = -1 if x < 0 else 1
    seg = 64
    # tyre profile (radius, x) from inner bead over the tread to the outer bead
    prof = [(r * rim_ratio, -w * 0.95), (r * 0.84, -w * 1.03), (r * 0.94, -w * 0.98), (r * 0.985, -w * 0.82),
            (r, -w * 0.62), (r, -w * 0.3), (r, 0.0), (r, w * 0.3), (r, w * 0.62), (r * 0.985, w * 0.82),
            (r * 0.94, w * 0.98), (r * 0.84, w * 1.03), (r * rim_ratio, w * 0.95)]
    bm = bmesh.new()
    rings_ = []
    for (rr, xx) in prof:
        rg = [bm.verts.new((xx, rr * math.cos(2 * math.pi * k / seg), rr * math.sin(2 * math.pi * k / seg))) for k in range(seg)]
        rings_.append(rg)
    tread_faces = []
    for bi, (a, b) in enumerate(zip(rings_, rings_[1:])):
        for k in range(seg):
            j = (k + 1) % seg
            f = bm.faces.new((a[k], a[j], b[j], b[k]))
            if bi in (5, 6) and (k + bi) % 2 == 0:
                tread_faces.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # tread blocks: extrude alternating faces of the tread band outward
    res = bmesh.ops.extrude_discrete_faces(bm, faces=tread_faces)
    for f in res["faces"]:
        c = f.calc_center_median()
        n_ = Vector((0, c.y, c.z)).normalized()
        for v in f.verts:
            v.co += n_ * 0.003
    tyre = k2.to_object(name, bm, [P["Rubber"]])
    for p in tyre.data.polygons:
        p.use_smooth = True
    rr = r * rim_ratio
    rim_m = P[rim_mat]
    parts = []
    # rim barrel with an outer lip, dished face
    barrel = k2.lathe(name + "_barrel", [(rr * 0.96, -w * 0.9), (rr, -w * 0.85), (rr, w * 0.62), (rr * 1.04, w * 0.72),
                                          (rr * 1.05, w * 0.8), (rr * 0.97, w * 0.84), (rr * 0.9, w * 0.8)],
                      [0] * 6, [rim_m], segments=seg)
    if side < 0:
        barrel.scale = (-1, 1, 1)
    parts.append(barrel)
    # brake disc + hat
    parts.append(k2.disc(name + "_disc", rr * 0.82, 0.03, (-side * w * 0.25, 0, 0), P["Disc"], axis="X", verts=36))
    parts.append(k2.disc(name + "_hat", rr * 0.36, 0.08, (-side * w * 0.12, 0, 0), P["Disc"], axis="X", verts=20))
    # spokes (twin): tapered boxes from the hub to the barrel lip, dished outward
    count = spokes * (2 if twin else 1)
    for kk in range(count):
        base = 2 * math.pi * (kk // (2 if twin else 1)) / spokes
        off = (0.075 if twin else 0.0) * (1 if kk % 2 else -1) if twin else 0.0
        a = base + off
        L = rr * 0.66
        sp = k2.rounded_box(name + f"_sp{kk}", (0.045, 0.06 if twin else 0.1, L),
                            (side * w * 0.5, math.sin(a) * (rr * 0.25 + L / 2), math.cos(a) * (rr * 0.25 + L / 2)),
                            rim_m, bevel=0.012, segs=2, rot=(-a, side * 0.12, 0))
        parts.append(sp)
    parts.append(k2.disc(name + "_face", rr * 0.3, 0.07, (side * w * 0.5, 0, 0), rim_m, axis="X", verts=24))
    parts.append(k2.disc(name + "_cap", rr * 0.16, 0.08, (side * (w * 0.5 + 0.02), 0, 0), P["RimDark"], axis="X", verts=20))
    for kk in range(5):
        a = 2 * math.pi * kk / 5 + math.pi / 5
        parts.append(k2.disc(name + f"_nut{kk}", 0.014, 0.035, (side * (w * 0.5 + 0.03), math.sin(a) * rr * 0.22, math.cos(a) * rr * 0.22),
                             P["Chrome"], axis="X", verts=6))
    k2.join(tyre, parts)
    tyre.location = (x, y, r)
    return tyre


def four_wheels(xs, yf, yr, rf, rr, wf, wr, P, **kw):
    for nm, x, y, r, w in (("FL", -xs, yf, rf, wf), ("FR", xs, yf, rf, wf), ("RL", -xs, yr, rr, wr), ("RR", xs, yr, rr, wr)):
        wheel("Wheel_" + nm, x, y, r, w, P, **kw)
    return [(-xs, yf, rf), (xs, yf, rf), (-xs, yr, rr), (xs, yr, rr)]


# ---------- interior + wipers for v4 bodies ----------

def interior(P):
    """Seats, headrests, dash and steering wheel sized to the v4 cabin (from the stations)."""
    cab = _STATE["cabin"]
    prof = _STATE["profile"]
    ys_ = [s["y"] for s in _STATE["stations"]]
    y_front = cab["ws"][0]
    y_rear = cab["rw"][0] if cab.get("rw") else cab["back"]
    mid = (cab["ws"][1] + (cab["rw"][1] if cab.get("rw") else cab["back"])) / 2
    sec = prof(mid)
    belt = sec["zb"]
    roof = sec["zt"]
    H = roof - belt
    wi = sec["wb"] * 0.8
    out = [k2.rounded_box("floor", (2 * wi, (y_front - y_rear) * 0.9, 0.05), (0, (y_front + y_rear) / 2, belt - 0.1), P["Interior"],
                          bevel=0.02, segs=1)]
    ys = mid - 0.1
    sx = wi * 0.5
    for x in (sx, -sx):
        out.append(k2.rounded_box("seat", (wi * 0.72, 0.45, 0.12), (x, ys, belt - 0.02), P["Seat"], bevel=0.04, segs=2))
        out.append(k2.rounded_box("seat_back", (wi * 0.72, 0.12, H * 0.75), (x, ys - 0.26, belt + H * 0.3), P["Seat"], bevel=0.04,
                                  segs=2, rot=(0.22, 0, 0)))
        out.append(k2.rounded_box("headrest", (wi * 0.4, 0.1, H * 0.2), (x, ys - 0.36, belt + H * 0.78), P["Seat"], bevel=0.03, segs=2))
    yd = (cab["ws"][0] + cab["ws"][1]) / 2 - 0.05
    out.append(k2.rounded_box("dash", (2 * wi, 0.35, H * 0.25), (0, yd, belt + H * 0.12), P["Interior"], bevel=0.04, segs=2))
    sw = k2.disc("steering", H * 0.2, 0.035, (-sx, yd - 0.3, belt + H * 0.35), P["Frame"], axis="Y", verts=20)
    sw.rotation_euler = (math.pi / 2 - 0.45, 0, 0)
    out.append(sw)
    del ys_
    return out


def wipers(body_obj, P):
    cab = _STATE["cabin"]
    prof = _STATE["profile"]
    yb = cab["ws"][0] + 0.12
    z0 = prof(yb)["zt"] + 0.05
    out = []
    for xs in ((0.05, 0.62), (-0.55, 0.0)):
        starts = [(x, yb + 4.0, z0 + (x - xs[0]) * 0.08) for x in [xs[0] + (xs[1] - xs[0]) * i / 9 for i in range(10)]]
        w = k2.surface_line("wiper", body_obj, starts, (0, -1, 0), 0.02, P["Frame"], off=0.014, sink=0.0)
        if w:
            out.append(w)
    return out


# ---------- LOD1 + export ----------

def make_lod1(ratio=0.14):
    """Duplicates every mesh as a light LOD1 (decimated), named <name>_lod1."""
    out = []
    for o in [o for o in bpy.context.scene.objects if o.type == "MESH" and not o.name.endswith("_lod1")]:
        d = o.copy()
        d.data = o.data.copy()
        d.name = o.name + "_lod1"
        bpy.context.collection.objects.link(d)
        m = d.modifiers.new("dec", "DECIMATE")
        m.ratio = ratio if not o.name.startswith("Wheel_") else ratio * 0.8
        k2.apply_mods(d)
        out.append(d)
    return out


def tris_of(objs):
    deps = bpy.context.evaluated_depsgraph_get()
    total = 0
    for o in objs:
        me = o.evaluated_get(deps).to_mesh()
        me.calc_loop_triangles()
        total += len(me.loop_triangles)
    return total


def run(build):
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    k2.reset()
    _STATE.clear()
    build()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in meshes:
        k2.apply_mods(o)
    k2.consolidate()
    lod0 = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    t0 = tris_of(lod0)
    lod1 = make_lod1()
    t1 = tris_of(lod1)
    print(f"CAR_TRIS {t0}")
    print(f"CAR_TRIS_LOD1 {t1}")
    if os.environ.get("CAR_BREAKDOWN"):
        for o in lod0:
            print(f"  PART {o.name:14s} {tris_of([o]):6d}")
    if argv:
        k2.export(argv[0])
    if len(argv) > 1:
        for o in lod1:
            o.hide_render = True
        k2.turntable(argv[1])
    print("CAR_OK")
