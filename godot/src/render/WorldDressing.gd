class_name WorldDressing
extends RefCounted

## World dressing around a track (A3 world pass 3): chunked terrain from TerrainField, houses
## with lit windows (neon diners and gas stations in the desert, farmhouses on Sunny, log cabins on Frosty), boulders,
## bushes and cacti. Everything is vertex-coloured and batched (one mesh / MultiMesh per kind
## and chunk) so off-screen chunks are culled; the low tier uses a coarser terrain grid.

const CHUNK_CELLS: int = 16
const MARGIN: float = 240.0


static func _low() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree != null and tree.root.has_node("Quality") and str(tree.root.get_node("Quality").get("tier")) == "low"


## Terrain chunks covering the track's surroundings.
static func terrain(field: TerrainField, tr: Track, ground_mat: Material) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = "Terrain"
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	var s: float = 0.0
	while s < tr.length:
		var smp: Track.Sample = tr.at(s)
		lo = Vector2(minf(lo.x, smp.px), minf(lo.y, smp.pz))
		hi = Vector2(maxf(hi.x, smp.px), maxf(hi.y, smp.pz))
		s += 10.0
	lo -= Vector2(MARGIN, MARGIN)
	hi += Vector2(MARGIN, MARGIN)
	var cell: float = 9.0 if _low() else 5.0
	var nx: int = int(ceil((hi.x - lo.x) / cell))
	var nz: int = int(ceil((hi.y - lo.y) / cell))
	# heights on the full grid once (chunks share edge vertices → no cracks)
	var hts: PackedFloat32Array = PackedFloat32Array()
	hts.resize((nx + 1) * (nz + 1))
	for j: int in nz + 1:
		for i: int in nx + 1:
			hts[j * (nx + 1) + i] = field.height(lo.x + i * cell, lo.y + j * cell)
	for cj: int in range(0, nz, CHUNK_CELLS):
		for ci: int in range(0, nx, CHUNK_CELLS):
			var st: SurfaceTool = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var w: int = mini(CHUNK_CELLS, nx - ci)
			var d: int = mini(CHUNK_CELLS, nz - cj)
			for j: int in d + 1:
				for i: int in w + 1:
					var gi: int = ci + i
					var gj: int = cj + j
					var h: float = hts[gj * (nx + 1) + gi]
					var hl: float = hts[gj * (nx + 1) + maxi(gi - 1, 0)]
					var hr: float = hts[gj * (nx + 1) + mini(gi + 1, nx)]
					var hd: float = hts[maxi(gj - 1, 0) * (nx + 1) + gi]
					var hu: float = hts[mini(gj + 1, nz) * (nx + 1) + gi]
					var n: Vector3 = Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
					var x: float = lo.x + gi * cell
					var z: float = lo.y + gj * cell
					st.set_normal(n)
					st.set_color(field.color_at(x, z, h, 1.0 - n.y * n.y))
					st.add_vertex(Vector3(x, h, z))
			for j: int in d:
				for i: int in w:
					var a: int = j * (w + 1) + i
					var b: int = a + 1
					var c: int = a + (w + 1)
					var e: int = c + 1
					# clockwise seen from above = front face in Godot
					st.add_index(a)
					st.add_index(c)
					st.add_index(b)
					st.add_index(b)
					st.add_index(c)
					st.add_index(e)
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.name = "TerrainChunk"
			mi.mesh = st.commit()
			mi.material_override = ground_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
	return node


## Ground material for terrain (graphics pass 5): terrain.gdshader — vertex colours × world-space
## patch variation, speckle and bump; snow sparkles, sand ripples.
static func terrain_mat(night: bool, kind: String = "hills") -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = preload("res://src/render/terrain.gdshader")
	m.set_shader_parameter("kind", {"snow": 1, "desert": 2}.get(kind, 0))
	m.set_shader_parameter("noise", TrackBuilder._noise_tex("terrain_v", 0.03, 256, false))
	m.set_shader_parameter("noise_n", TrackBuilder._noise_tex("terrain_n", 0.06, 256, true))
	m.set_shader_parameter("night", 1.0 if night else 0.0)
	return m


# ---------- houses ----------

## Houses beside the road, facing it: style "roadside" (desert night: diners and gas stations with
## neon), "farm" (Sunny), "cabin" (Frosty). ("adobe" is kept for reference.)
## Returns [body mesh instance, lit-window mesh instance].
static func houses(field: TerrainField, tr: Track, style: String, rng: Rng, lit: bool) -> Array[Node3D]:
	if style != "roadside":
		return _kit_houses(field, tr, style, rng, lit)
	var body: SurfaceTool = SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow: SurfaceTool = SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s: float = 40.0
	var side: float = 1.0
	var count: int = 0
	while s < tr.length - 30.0:
		var smp: Track.Sample = tr.at(s)
		var dist: float = smp.half_width + 12.0 + rng.next_float() * 14.0
		var p: Vector3 = Vector3(smp.px + smp.nx * side * dist, 0.0, smp.pz + smp.nz * side * dist)
		var near: Vector3 = field.nearest(p.x, p.z)
		if near.x - near.z > 9.0: # still clear of the road (corners)
			var h0: float = field.height(p.x - 3.0, p.z - 3.0)
			var h1: float = field.height(p.x + 3.0, p.z + 3.0)
			if absf(h1 - h0) < 2.5: # flat enough to build on
				p.y = minf(h0, h1) - 0.3
				var yaw: float = atan2(-smp.nx * side, -smp.nz * side) # front faces the road
				_house(body, glow, p, yaw, style, rng, lit)
				count += 1
		s += (90.0 + rng.next_float() * 70.0) if style == "roadside" else (70.0 + rng.next_float() * 60.0)
		side = -side if rng.next_float() < 0.7 else side
	var out: Array[Node3D] = []
	if count == 0:
		return out
	var bm: StandardMaterial3D = StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.roughness = 0.9
	body.generate_normals()
	var bmi: MeshInstance3D = MeshInstance3D.new()
	bmi.name = "Houses"
	bmi.mesh = body.commit()
	bmi.material_override = bm
	out.append(bmi)
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var gmi: MeshInstance3D = MeshInstance3D.new()
	gmi.name = "HouseWindows"
	gmi.mesh = glow.commit()
	gmi.material_override = gm
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out.append(gmi)
	return out


## Blender buildings kit (art/blender/env/buildings.py): farmhouses and barns on Sunny, log
## cabins on Frosty, placed like the old boxes (front toward the road), two detail levels, windows
## glowing warm at night / in snow.
static func _kit_houses(field: TerrainField, tr: Track, style: String, rng: Rng, lit: bool) -> Array[Node3D]:
	var by_kind: Dictionary = {}
	var s: float = 40.0
	var side: float = 1.0
	var n: int = 0
	while s < tr.length - 30.0:
		var smp: Track.Sample = tr.at(s)
		var dist: float = smp.half_width + 16.0 + rng.next_float() * 16.0
		var p: Vector3 = Vector3(smp.px + smp.nx * side * dist, 0.0, smp.pz + smp.nz * side * dist)
		var near: Vector3 = field.nearest(p.x, p.z)
		if near.x - near.z > 12.0:
			var h0: float = field.height(p.x - 5.0, p.z - 5.0)
			var h1: float = field.height(p.x + 5.0, p.z + 5.0)
			if absf(h1 - h0) < 3.0:
				p.y = minf(h0, h1) - 0.35
				var yaw: float = atan2(-smp.nx * side, -smp.nz * side) # front (+Z) faces the road
				var kind: String = "Cabin" if style == "cabin" else ("Barn" if n % 3 == 2 else "Farmhouse")
				var k: float = 0.9 + rng.next_float() * 0.2
				if not by_kind.has(kind):
					by_kind[kind] = [] as Array[Transform3D]
				(by_kind[kind] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(k, k, k)), p))
				n += 1
		s += 80.0 + rng.next_float() * 70.0
		side = -side if rng.next_float() < 0.7 else side
	var holder: Node3D = Node3D.new()
	holder.name = "Buildings"
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	if lit:
		glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glass.albedo_color = Color(1.0, 0.78, 0.42)
	else:
		glass.albedo_color = Color(0.22, 0.28, 0.36)
		glass.roughness = 0.12
		glass.metallic = 0.3
	for kind: String in by_kind:
		var list: Array[Transform3D] = by_kind[kind] as Array[Transform3D]
		EnvKit.scatter(holder, "buildings", kind, list, rng, EnvKit.solid_material())
		EnvKit.scatter(holder, "buildings", kind + "Glow", list, rng, glass, false)
	var out: Array[Node3D] = []
	out.append(holder)
	return out


static func _house(st: SurfaceTool, glow: SurfaceTool, p: Vector3, yaw: float, style: String, rng: Rng, lit: bool) -> void:
	var xf: Transform3D = Transform3D(Basis(Vector3.UP, yaw), p)
	if style == "roadside":
		if rng.next_float() < 0.55:
			_diner(st, glow, xf, rng)
		else:
			_gas_station(st, glow, xf, rng)
		return
	var w: float = 3.5 + rng.next_float() * 2.5 # half width (along the road)
	var dpt: float = 3.0 + rng.next_float() * 1.5 # half depth
	var hgt: float = 3.0 if style != "farm" else 3.4
	var wall: Color
	var roof: Color
	match style:
		"adobe":
			wall = [Color(0.78, 0.62, 0.45), Color(0.83, 0.68, 0.5), Color(0.72, 0.55, 0.4)][rng.next_int(3)]
			roof = wall.darkened(0.12)
		"cabin":
			wall = Color(0.42, 0.28, 0.18)
			roof = Color(0.93, 0.95, 0.99)
		_:
			wall = [Color(0.94, 0.93, 0.88), Color(0.95, 0.88, 0.75), Color(0.85, 0.9, 0.95)][rng.next_int(3)]
			roof = [Color(0.7, 0.2, 0.15), Color(0.35, 0.3, 0.32), Color(0.55, 0.25, 0.18)][rng.next_int(3)]
	TrackBuilder._box(st, Vector3(0, hgt / 2.0, 0), Vector3(w, hgt / 2.0, dpt), wall, xf)
	TrackBuilder._box(st, Vector3(0, 0.15, 0), Vector3(w + 0.15, 0.2, dpt + 0.15), wall.darkened(0.25), xf) # plinth
	if style == "adobe":
		TrackBuilder._box(st, Vector3(0, hgt + 0.2, 0), Vector3(w, 0.2, dpt), roof, xf) # parapet roof
		for k: int in 5: # vigas (roof beams) sticking out of the front wall
			TrackBuilder._box(st, Vector3(-w + 0.6 + k * (2.0 * w - 1.2) / 4.0, hgt - 0.35, dpt + 0.25), Vector3(0.1, 0.1, 0.3),
				Color(0.36, 0.24, 0.15), xf)
	else:
		# gabled roof along the house's width
		var rh: float = 1.8 if style == "farm" else 2.0
		var eave: float = 0.45
		var a: Vector3 = xf * Vector3(-w - eave, hgt, -dpt - eave)
		var b: Vector3 = xf * Vector3(w + eave, hgt, -dpt - eave)
		var c: Vector3 = xf * Vector3(-w - eave, hgt, dpt + eave)
		var d: Vector3 = xf * Vector3(w + eave, hgt, dpt + eave)
		var ra: Vector3 = xf * Vector3(-w - eave, hgt + rh, 0)
		var rb: Vector3 = xf * Vector3(w + eave, hgt + rh, 0)
		for tri: Array in [[a, ra, b], [b, ra, rb], [c, d, ra], [d, rb, ra]]:
			for v: Vector3 in tri:
				st.set_color(roof)
				st.add_vertex(v)
		var ga: Vector3 = xf * Vector3(-w, hgt, -dpt)
		var gb: Vector3 = xf * Vector3(-w, hgt, dpt)
		var gc: Vector3 = xf * Vector3(-w, hgt + rh * 0.95, 0)
		var gd: Vector3 = xf * Vector3(w, hgt, -dpt)
		var ge: Vector3 = xf * Vector3(w, hgt, dpt)
		var gf: Vector3 = xf * Vector3(w, hgt + rh * 0.95, 0)
		for tri2: Array in [[ga, gc, gb], [gd, ge, gf]]:
			for v2: Vector3 in tri2:
				st.set_color(wall)
				st.add_vertex(v2)
		# chimney
		TrackBuilder._box(st, Vector3(w * 0.5, hgt + rh * 0.8, -dpt * 0.3), Vector3(0.35, 0.9, 0.35),
			Color(0.55, 0.3, 0.22) if style == "farm" else Color(0.4, 0.4, 0.42), xf)
	# door + windows on the front (+z, facing the road)
	TrackBuilder._box(st, Vector3(-w * 0.45, 1.05, dpt + 0.03), Vector3(0.5, 1.05, 0.04), wall.darkened(0.55), xf)
	var win: Color = Color(1.0, 0.78, 0.42) if lit else Color(0.16, 0.22, 0.3)
	for wx: float in [w * 0.15, w * 0.6]:
		TrackBuilder._box(glow if lit else st, Vector3(wx, 1.7, dpt + 0.04), Vector3(0.45, 0.45, 0.04), win, xf)
		TrackBuilder._box(st, Vector3(wx, 1.18, dpt + 0.08), Vector3(0.55, 0.06, 0.08), wall.darkened(0.3), xf) # sill
	TrackBuilder._box(glow if lit else st, Vector3(w + 0.04, 1.7, 0), Vector3(0.04, 0.45, 0.5), win, xf) # side window
	if lit: # porch lamp
		TrackBuilder._box(glow, Vector3(-w * 0.45, 2.35, dpt + 0.1), Vector3(0.12, 0.12, 0.08), Color(1.0, 0.85, 0.55), xf)


const NEON: Array[Color] = [Color(1.0, 0.25, 0.7), Color(0.2, 0.9, 1.0), Color(1.0, 0.6, 0.15), Color(0.55, 1.0, 0.35)]


## Roadside diner: long low building, chrome-ish trim, a band of warm lit windows, a neon stripe
## along the roof edge and a tall neon sign on a pole. Front (+z) faces the road.
static func _diner(st: SurfaceTool, glow: SurfaceTool, xf: Transform3D, rng: Rng) -> void:
	var w: float = 6.0 + rng.next_float() * 2.0
	var dpt: float = 3.6
	var hgt: float = 3.3
	var wall: Color = [Color(0.86, 0.84, 0.78), Color(0.55, 0.78, 0.76), Color(0.9, 0.78, 0.62)][rng.next_int(3)]
	var neon: Color = NEON[rng.next_int(NEON.size())]
	TrackBuilder._box(st, Vector3(0, hgt / 2.0, 0), Vector3(w, hgt / 2.0, dpt), wall, xf)
	TrackBuilder._box(st, Vector3(0, 0.15, 0), Vector3(w + 0.2, 0.2, dpt + 0.2), wall.darkened(0.4), xf)
	TrackBuilder._box(st, Vector3(0, hgt + 0.2, 0.3), Vector3(w + 0.5, 0.22, dpt + 0.8), Color(0.75, 0.76, 0.8), xf) # roof slab
	TrackBuilder._box(st, Vector3(0, 0.75, dpt + 0.03), Vector3(w - 0.2, 0.35, 0.04), Color(0.78, 0.8, 0.85), xf) # chrome skirt
	TrackBuilder._box(glow, Vector3(0.6, 1.85, dpt + 0.05), Vector3(w - 1.4, 0.7, 0.04), Color(1.0, 0.82, 0.5), xf) # windows
	TrackBuilder._box(st, Vector3(-w + 0.8, 1.2, dpt + 0.05), Vector3(0.5, 1.2, 0.04), Color(0.25, 0.2, 0.2), xf) # door
	TrackBuilder._box(glow, Vector3(0, hgt + 0.48, dpt + 1.12), Vector3(w + 0.5, 0.06, 0.04), neon, xf) # roof edge neon
	# sign on a pole at the road-side corner: frame + glowing panel + border tube
	var sx: float = w + 2.5
	TrackBuilder._box(st, Vector3(sx, 3.5, dpt + 1.5), Vector3(0.15, 3.5, 0.15), Color(0.3, 0.3, 0.34), xf)
	TrackBuilder._box(st, Vector3(sx, 7.6, dpt + 1.5), Vector3(1.9, 1.0, 0.18), Color(0.12, 0.12, 0.16), xf)
	TrackBuilder._box(glow, Vector3(sx, 7.6, dpt + 1.7), Vector3(1.6, 0.75, 0.03), neon, xf)
	var other: Color = NEON[(NEON.find(neon) + 1) % NEON.size()]
	TrackBuilder._box(glow, Vector3(sx, 8.68, dpt + 1.7), Vector3(1.95, 0.06, 0.04), other, xf)
	TrackBuilder._box(glow, Vector3(sx, 6.52, dpt + 1.7), Vector3(1.95, 0.06, 0.04), other, xf)


## Gas station: canopy on four posts with a bright underside and a neon edge, two pumps with
## lit screens, a small shop behind. Front (+z) faces the road.
static func _gas_station(st: SurfaceTool, glow: SurfaceTool, xf: Transform3D, rng: Rng) -> void:
	var neon: Color = NEON[rng.next_int(NEON.size())]
	var cw: float = 6.5
	var cd: float = 3.5
	var ch: float = 4.6
	for px: float in [-cw + 0.8, cw - 0.8]:
		for pz: float in [-cd + 0.8, cd - 0.8]:
			TrackBuilder._box(st, Vector3(px, ch / 2.0, pz + 2.0), Vector3(0.22, ch / 2.0, 0.22), Color(0.85, 0.85, 0.88), xf)
	TrackBuilder._box(st, Vector3(0, ch + 0.35, 2.0), Vector3(cw, 0.35, cd), Color(0.92, 0.92, 0.95), xf) # canopy
	TrackBuilder._box(glow, Vector3(0, ch - 0.02, 2.0), Vector3(cw - 0.4, 0.03, cd - 0.4), Color(0.95, 0.97, 1.0), xf) # lights
	TrackBuilder._box(glow, Vector3(0, ch + 0.35, 2.0 + cd + 0.03), Vector3(cw, 0.14, 0.04), neon, xf) # neon band
	TrackBuilder._box(glow, Vector3(0, ch + 0.35, 2.0 - cd - 0.03), Vector3(cw, 0.14, 0.04), neon, xf)
	for px2: float in [-2.2, 2.2]:
		TrackBuilder._box(st, Vector3(px2, 0.2, 2.0), Vector3(0.9, 0.2, 0.5), Color(0.6, 0.6, 0.62), xf) # island
		TrackBuilder._box(st, Vector3(px2, 1.1, 2.0), Vector3(0.35, 0.75, 0.3), Color(0.85, 0.15, 0.15), xf) # pump
		TrackBuilder._box(glow, Vector3(px2, 1.45, 2.32), Vector3(0.22, 0.16, 0.02), Color(0.6, 1.0, 0.8), xf)
	# shop behind the canopy
	TrackBuilder._box(st, Vector3(0, 1.7, -4.2), Vector3(4.5, 1.7, 2.6), Color(0.82, 0.8, 0.76), xf)
	TrackBuilder._box(glow, Vector3(0, 1.6, -4.2 + 2.63), Vector3(3.2, 0.8, 0.03), Color(1.0, 0.88, 0.62), xf)
	TrackBuilder._box(glow, Vector3(0, 3.6, -4.2 + 2.65), Vector3(2.6, 0.32, 0.03), neon, xf) # shop sign


# ---------- small props ----------

static func boulder_mesh(c: Color) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng: Rng = Rng.new(5)
	var n: int = 7
	var rings: int = 4
	var pts: Array = []
	for j: int in rings + 1:
		var row: Array[Vector3] = []
		var t: float = PI * float(j) / rings
		for i: int in n:
			var a: float = TAU * float(i) / n
			var r: float = 0.8 + rng.next_float() * 0.4
			row.append(Vector3(sin(t) * cos(a) * r, cos(t) * 0.7 * r + 0.25, sin(t) * sin(a) * r))
		pts.append(row)
	for j: int in rings:
		for i: int in n:
			var i2: int = (i + 1) % n
			var a0: Vector3 = (pts[j] as Array)[i]
			var a1: Vector3 = (pts[j] as Array)[i2]
			var b0: Vector3 = (pts[j + 1] as Array)[i]
			var b1: Vector3 = (pts[j + 1] as Array)[i2]
			var shade: Color = c.lightened(0.08) if j < 2 else c.darkened(0.12)
			for v: Vector3 in [a0, b0, a1, a1, b0, b1]:
				st.set_color(shade)
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func cactus_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g: Color = Color(0.25, 0.42, 0.24)
	TrackBuilder._prism(st, 0.0, 1.0, 0.09, 8, g)
	TrackBuilder._prism(st, 0.45, 0.75, 0.06, 6, g.darkened(0.05)) # arm stubs (offset below)
	var arm: Transform3D = Transform3D(Basis(), Vector3(0.16, 0.0, 0.0))
	var arm2: Transform3D = Transform3D(Basis(), Vector3(-0.15, -0.1, 0.0))
	var tmp: SurfaceTool = SurfaceTool.new()
	tmp.begin(Mesh.PRIMITIVE_TRIANGLES)
	TrackBuilder._prism(tmp, 0.5, 0.85, 0.055, 6, g)
	TrackBuilder._prism(tmp, 0.4, 0.68, 0.05, 6, g)
	st.append_from(tmp.commit(), 0, arm)
	st.append_from(tmp.commit(), 0, arm2)
	st.generate_normals()
	return st.commit()


## Props on the terrain near the road: rocks everywhere, cacti (desert) or bushes (Sunny).
static func props(node: Node3D, field: TerrainField, tr: Track, style: String, rng: Rng) -> void:
	var rocks: Array[Transform3D] = []
	var plants: Array[Transform3D] = []
	var density: float = 0.35 if _low() else 0.7
	var s: float = 0.0
	while s < tr.length:
		var smp: Track.Sample = tr.at(s)
		for side: float in [-1.0, 1.0]:
			if rng.next_float() > density:
				continue
			var dist: float = smp.half_width + 6.0 + rng.next_float() * 45.0
			var x: float = smp.px + smp.nx * side * dist
			var z: float = smp.pz + smp.nz * side * dist
			var near: Vector3 = field.nearest(x, z)
			if near.x - near.z < 4.0:
				continue
			var y: float = field.height(x, z)
			var sc: float = 0.4 + rng.next_float() * 1.3
			var b: Basis = Basis(Vector3.UP, rng.next_float() * TAU).scaled(Vector3(sc * (0.8 + rng.next_float() * 0.5), sc, sc))
			if rng.next_float() < 0.45:
				rocks.append(Transform3D(b, Vector3(x, y - 0.15 * sc, z)))
			elif style != "cabin":
				var ps: float = (2.2 + rng.next_float() * 2.0) if style == "roadside" else (0.6 + rng.next_float() * 0.6)
				plants.append(Transform3D(Basis(Vector3.UP, rng.next_float() * TAU).scaled(Vector3(ps, ps, ps)), Vector3(x, y, z)))
		s += 9.0
	var rock_c: Color = Color(0.56, 0.4, 0.3) if style == "roadside" else (Color(0.55, 0.57, 0.62) if style == "cabin" else Color(0.55, 0.53, 0.5))
	# Blender kit rocks (three shapes) tinted per map, cacti (desert) or bushes
	var by_shape: Array = [[] as Array[Transform3D], [] as Array[Transform3D], [] as Array[Transform3D]]
	for i: int in rocks.size():
		(by_shape[i % 3] as Array[Transform3D]).append(rocks[i])
	var rmat: StandardMaterial3D = EnvKit.solid_material().duplicate() as StandardMaterial3D
	rmat.albedo_color = rock_c.lightened(0.5) # the kit rocks are neutral grey: tint toward the map's rock colour
	for k: int in 3:
		EnvKit.scatter(node, "vegetation", "Rock%d" % k, by_shape[k] as Array[Transform3D], rng, rmat)
	if not plants.is_empty():
		EnvKit.scatter(node, "vegetation", "Cactus" if style == "roadside" else "Bush", plants, rng, EnvKit.foliage_material())


static func _chunked(node: Node3D, name: String, mesh: Mesh, xforms: Array[Transform3D], rng: Rng) -> void:
	var cells: Dictionary = {}
	for t: Transform3D in xforms:
		var key: Vector2i = Vector2i(floori(t.origin.x / 200.0), floori(t.origin.z / 200.0))
		if not cells.has(key):
			cells[key] = [] as Array[Transform3D]
		(cells[key] as Array[Transform3D]).append(t)
	for key: Vector2i in cells:
		var mmi: MultiMeshInstance3D = TrackBuilder._tinted_multimesh(name, mesh, cells[key] as Array[Transform3D], rng)
		node.add_child(mmi)
