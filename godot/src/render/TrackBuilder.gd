class_name TrackBuilder
extends RefCounted

## Builds the visual track from map JSON via Track.gd (GAME_PLAN §2.4, §4.3): road, curbs,
## walls, skirts or bridge pillars, start gate, ramps, ground, simple scenery and the theme's
## environment. M8 replaces the placeholder look (baked lighting, Blender props).

const STEP: float = 2.0
const WALL_H: float = 1.1
const WALL_GAP: float = 0.25
const CURB_W: float = 1.2
const CURB_SEG: float = 4.0
const ROAD_LIFT: float = 0.02
const LINE_W: float = 0.16
const DASH_LEN: float = 3.0
const DASH_GAP: float = 5.0
const LANE_W: float = 3.6
const RAIL_Z0: float = 0.45
const RAIL_Z1: float = 0.8
const POST_EVERY: float = 4.0
const LAMP_EVERY: float = 36.0
## W-beam cross-section: (bulge toward the road, height) from bottom to top
const W_BEAM: Array[Vector2] = [Vector2(0.0, 0.45), Vector2(0.08, 0.5), Vector2(0.08, 0.56), Vector2(0.02, 0.625),
	Vector2(0.08, 0.69), Vector2(0.08, 0.75), Vector2(0.0, 0.8)]


class TrackTheme:
	extends RefCounted
	var road: Color
	var curb_a: Color
	var curb_b: Color
	var wall: Color
	var wall_emission: Color
	var ground: Color
	var skirt: Color
	var sky_top: Color
	var sky_horizon: Color
	var sun_color: Color
	var sun_energy: float
	var sun_rot: Vector3
	var ambient: float
	var fog: Color
	var fog_density: float
	var pillars: bool
	var prop_color: Color
	var prop_emission: Color
	var night: bool = false
	var snow: bool = false
	var terrain: String = "hills" # TerrainField kind: hills | snow | desert


static func theme_for(theme_id: String) -> TrackTheme:
	var t: TrackTheme = TrackTheme.new()
	match theme_id:
		"neon":
			t.road = Color(0.09, 0.09, 0.12)
			t.curb_a = Color(0.95, 0.2, 0.75)
			t.curb_b = Color(0.15, 0.85, 1.0)
			t.wall = Color(0.12, 0.12, 0.18)
			t.wall_emission = Color(0.2, 0.9, 1.0)
			t.ground = Color(0.42, 0.33, 0.25) # desert sand (moonlit)
			t.skirt = Color(0.1, 0.1, 0.14)
			t.sky_top = Color(0.015, 0.02, 0.07)
			t.sky_horizon = Color(0.08, 0.1, 0.22)
			t.sun_color = Color(0.74, 0.8, 1.0) # moonlight (cool, the sand stays warm)
			t.sun_energy = 1.0 # bluish moonlight key: cars keep their shape at night
			t.sun_rot = Vector3(-38, 30, 0)
			t.ambient = 0.9
			t.fog = Color(0.05, 0.06, 0.12)
			t.fog_density = 0.0009
			t.pillars = true
			t.prop_color = Color(0.1, 0.1, 0.16)
			t.prop_emission = Color(1.0, 0.3, 0.8)
			t.night = true
			t.terrain = "desert"
		"frosty":
			t.road = Color(0.26, 0.28, 0.32)
			t.curb_a = Color(0.85, 0.15, 0.15)
			t.curb_b = Color(0.95, 0.95, 0.97)
			t.wall = Color(0.75, 0.82, 0.9)
			t.wall_emission = Color(0, 0, 0)
			t.ground = Color(0.9, 0.93, 0.97)
			t.skirt = Color(0.55, 0.58, 0.64)
			t.sky_top = Color(0.22, 0.42, 0.8)
			t.sky_horizon = Color(0.82, 0.88, 0.95)
			t.sun_color = Color(1.0, 0.95, 0.9)
			t.sun_energy = 1.35
			t.sun_rot = Vector3(-35, -40, 0)
			t.ambient = 0.45
			t.fog = Color(0.85, 0.9, 0.96)
			t.fog_density = 0.0009
			t.pillars = false
			t.prop_color = Color(0.13, 0.3, 0.2)
			t.prop_emission = Color(0, 0, 0)
			t.snow = true
			t.terrain = "snow"
		_:
			t.road = Color(0.24, 0.24, 0.26)
			t.curb_a = Color(0.9, 0.15, 0.12)
			t.curb_b = Color(0.97, 0.97, 0.97)
			t.wall = Color(0.95, 0.95, 0.95)
			t.wall_emission = Color(0, 0, 0)
			t.ground = Color(0.35, 0.62, 0.25)
			t.skirt = Color(0.45, 0.36, 0.25)
			t.sky_top = Color(0.12, 0.4, 0.95) # deeper blue: AgX desaturates bright sky
			t.sky_horizon = Color(0.62, 0.8, 0.98)
			t.sun_color = Color(1.0, 0.92, 0.78)
			t.sun_energy = 1.45
			t.sun_rot = Vector3(-40, 50, 0)
			t.ambient = 0.4
			t.fog = Color(0.75, 0.85, 0.95)
			t.fog_density = 0.0005
			t.pillars = false
			t.prop_color = Color(0.18, 0.5, 0.2)
			t.prop_emission = Color(0, 0, 0)
	return t


static func _mat(c: Color, emission: Color = Color(0, 0, 0), vertex_colors: bool = false) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if vertex_colors:
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(1, 1, 1)
	if emission.r + emission.g + emission.b > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 2.0
	return m


static func _two_sided(m: StandardMaterial3D) -> StandardMaterial3D:
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _mesh_instance(name: String, st: SurfaceTool, mat: Material) -> MeshInstance3D:
	st.generate_normals()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


## A quad strip along the track between lateral offsets d0 → d1 at heights h0/h1 (above road).
static func _strip(st: SurfaceTool, tr: Track, d0: float, d1: float, h0: float, h1: float, color_fn: Callable = Callable()) -> void:
	var n: int = int(ceil(tr.length / STEP))
	for i: int in n:
		var sa: float = tr.length * float(i) / float(n)
		var sb: float = tr.length * float(i + 1) / float(n)
		var a0: Vector3 = tr.world(sa, d0, h0)
		var a1: Vector3 = tr.world(sa, d1, h1)
		var b0: Vector3 = tr.world(sb, d0, h0)
		var b1: Vector3 = tr.world(sb, d1, h1)
		if color_fn.is_valid():
			st.set_color(color_fn.call(sa) as Color)
		st.add_vertex(a0)
		st.add_vertex(a1)
		st.add_vertex(b0)
		st.add_vertex(a1)
		st.add_vertex(b1)
		st.add_vertex(b0)


## Builds the full track scene under a new Node3D.
static func build(tr: Track) -> Node3D:
	var th: TrackTheme = theme_for(tr.theme)
	var root: Node3D = Node3D.new()
	root.name = "Track_" + tr.id
	var hw_max: float = 0.0
	var n: int = int(ceil(tr.length / STEP))
	var min_y: float = INF
	var aabb_min: Vector3 = Vector3(INF, INF, INF)
	var aabb_max: Vector3 = Vector3(-INF, -INF, -INF)
	for i: int in n:
		var smp: Track.Sample = tr.at(tr.length * float(i) / float(n))
		hw_max = maxf(hw_max, smp.half_width)
		min_y = minf(min_y, smp.py)
		var p: Vector3 = Vector3(smp.px, smp.py, smp.pz)
		aabb_min = aabb_min.min(p)
		aabb_max = aabb_max.max(p)

	# Road (variable width: build per-sample with the local half width)
	var road: SurfaceTool = SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in n:
		var sa: float = tr.length * float(i) / float(n)
		var sb: float = tr.length * float(i + 1) / float(n)
		var ha: float = tr.half_width(sa)
		var hb: float = tr.half_width(sb)
		# UV = track space (d, s) in metres, UV2.x = local half width (road.gdshader)
		var verts: Array = [[sa, -ha, ha], [sa, ha, ha], [sb, -hb, hb], [sa, ha, ha], [sb, hb, hb], [sb, -hb, hb]]
		for v: Array in verts:
			road.set_uv(Vector2(float(v[1]), float(v[0])))
			road.set_uv2(Vector2(float(v[2]), 0.0))
			road.add_vertex(tr.world(float(v[0]), float(v[1]), ROAD_LIFT))
	road.generate_normals()
	road.generate_tangents()
	var road_mi: MeshInstance3D = MeshInstance3D.new()
	road_mi.name = "Road"
	road_mi.mesh = road.commit()
	road_mi.material_override = _asphalt(th.road, th.night)
	root.add_child(road_mi)
	var marks: MeshInstance3D = _mesh_instance("Markings", _markings(tr), _mat(Color(0.93, 0.93, 0.9)))
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # flat paint: no shadow pass
	root.add_child(marks)

	# Curbs + walls + skirts, both sides, following the local half width
	var curbs: SurfaceTool = SurfaceTool.new()
	curbs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls: SurfaceTool = SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall_tops: SurfaceTool = SurfaceTool.new()
	wall_tops.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skirts: SurfaceTool = SurfaceTool.new()
	skirts.begin(Mesh.PRIMITIVE_TRIANGLES)
	var guard_rails: bool = th.wall_emission == Color(0, 0, 0) # glowing barriers stay on neon
	for i: int in n:
		var sa: float = tr.length * float(i) / float(n)
		var sb: float = tr.length * float(i + 1) / float(n)
		var ha: float = tr.half_width(sa)
		var hb: float = tr.half_width(sb)
		var curb_col: Color = th.curb_a if int(sa / CURB_SEG) % 2 == 0 else th.curb_b
		for side: float in [-1.0, 1.0]:
			# curb: raised kerb just inside the road edge: bevel up from the road, flat top, small
			# outer drop (profile across: inner foot → bevel top → outer top → outer foot)
			var prof: Array[Vector2] = [Vector2(ha - CURB_W, 0.02), Vector2(ha - CURB_W + 0.3, 0.1), Vector2(ha - 0.12, 0.1), Vector2(ha, 0.04)]
			var off_b: float = hb - ha
			for k: int in prof.size() - 1:
				var p0: Vector2 = prof[k]
				var p1: Vector2 = prof[k + 1]
				var shade: Color = curb_col.darkened(0.12) if k == 0 else curb_col
				if side > 0.0:
					_quad(curbs, tr.world(sa, p0.x, ROAD_LIFT + p0.y), tr.world(sb, p0.x + off_b, ROAD_LIFT + p0.y),
						tr.world(sa, p1.x, ROAD_LIFT + p1.y), tr.world(sb, p1.x + off_b, ROAD_LIFT + p1.y), shade)
				else:
					_quad(curbs, tr.world(sa, -p1.x, ROAD_LIFT + p1.y), tr.world(sb, -p1.x - off_b, ROAD_LIFT + p1.y),
						tr.world(sa, -p0.x, ROAD_LIFT + p0.y), tr.world(sb, -p0.x - off_b, ROAD_LIFT + p0.y), shade)
			# wall: vertical face at the edge
			var wa: float = side * (ha + WALL_GAP)
			var wb: float = side * (hb + WALL_GAP)
			if guard_rails:
				# W-beam guard rail on posts: two ridges bulging toward the road, plus its top lip
				for k: int in W_BEAM.size() - 1:
					var q0: Vector2 = W_BEAM[k]
					var q1: Vector2 = W_BEAM[k + 1]
					_quad(walls, tr.world(sa, wa - side * q0.x, q0.y), tr.world(sb, wb - side * q0.x, q0.y),
						tr.world(sa, wa - side * q1.x, q1.y), tr.world(sb, wb - side * q1.x, q1.y), th.wall)
				_quad(wall_tops, tr.world(sa, wa, RAIL_Z1), tr.world(sb, wb, RAIL_Z1), tr.world(sa, wa + side * 0.12, RAIL_Z1), tr.world(sb, wb + side * 0.12, RAIL_Z1), th.wall)
			else:
				_quad(walls, tr.world(sa, wa, 0.0), tr.world(sb, wb, 0.0), tr.world(sa, wa, WALL_H), tr.world(sb, wb, WALL_H), th.wall)
				_quad(wall_tops, tr.world(sa, wa, WALL_H), tr.world(sb, wb, WALL_H), tr.world(sa, wa + side * 0.35, WALL_H), tr.world(sb, wb + side * 0.35, WALL_H), th.wall)
			# skirt: from the wall foot down to the ground (not on bridge themes)
			if not th.pillars:
				var fa: Vector3 = tr.world(sa, wa + side * 0.35, 0.0)
				var fb: Vector3 = tr.world(sb, wb + side * 0.35, 0.0)
				if fa.y > min_y + 0.05 or fb.y > min_y + 0.05:
					_quad(skirts, fa, fb, Vector3(fa.x + side * 0.0, min_y - 0.5, fa.z), Vector3(fb.x, min_y - 0.5, fb.z), th.skirt)
	root.add_child(_mesh_instance("Curbs", curbs, _mat(Color.WHITE, Color(0, 0, 0), true)))
	if guard_rails:
		var steel: StandardMaterial3D = _two_sided(_mat(Color(0.74, 0.76, 0.79)))
		steel.metallic = 0.7
		steel.roughness = 0.35
		root.add_child(_mesh_instance("Walls", walls, steel))
		root.add_child(_mesh_instance("WallTops", wall_tops, steel))
		var posts: MeshInstance3D = _mesh_instance("RailPosts", _posts(tr), _mat(Color(0.45, 0.47, 0.5)))
		posts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(posts)
	else:
		root.add_child(_mesh_instance("Walls", walls, _two_sided(_mat(th.wall))))
		root.add_child(_mesh_instance("WallTops", wall_tops, _two_sided(_mat(th.wall, th.wall_emission))))
	if not th.pillars:
		root.add_child(_mesh_instance("Skirts", skirts, _two_sided(_mat(th.skirt))))

	# Bridge pillars where the road is high above the ground
	if th.pillars:
		var pillar_mesh: BoxMesh = BoxMesh.new()
		pillar_mesh.size = Vector3(1.6, 1.0, 1.6)
		var pillars: MultiMesh = MultiMesh.new()
		pillars.transform_format = MultiMesh.TRANSFORM_3D
		pillars.mesh = pillar_mesh
		var xforms: Array[Transform3D] = []
		var s: float = 0.0
		while s < tr.length:
			var smp: Track.Sample = tr.at(s)
			var h: float = smp.py - min_y
			if h > 3.0:
				for side: float in [-1.0, 1.0]:
					var top: Vector3 = tr.world(s, side * (smp.half_width - 1.5), -0.3)
					var basis: Basis = Basis.from_scale(Vector3(1, h, 1))
					xforms.append(Transform3D(basis, Vector3(top.x, min_y + (top.y - min_y) / 2.0, top.z)))
			s += 22.0
		pillars.instance_count = xforms.size()
		for i: int in xforms.size():
			pillars.set_instance_transform(i, xforms[i])
		var pmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		pmi.name = "Pillars"
		pmi.multimesh = pillars
		pmi.material_override = _mat(th.skirt)
		root.add_child(pmi)

	# Ramps: full-width wedges rising to the ramp's height (physics launches every car from the lip)
	var ramps: SurfaceTool = SurfaceTool.new()
	ramps.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r: Dictionary in tr.ramps:
		_ramp(ramps, tr, r)
	if tr.ramps.size() > 0:
		root.add_child(_mesh_instance("Ramps", ramps, _two_sided(_mat(Color.WHITE, Color(0, 0, 0), true))))

	# Start line (checkered) + gate
	var line: SurfaceTool = SurfaceTool.new()
	line.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw_s: float = tr.half_width(0.0)
	var cells: int = 12
	for row: int in 2:
		for k: int in cells:
			var d0: float = lerpf(-hw_s, hw_s, float(k) / cells)
			var d1: float = lerpf(-hw_s, hw_s, float(k + 1) / cells)
			var c: Color = Color.WHITE if (k + row) % 2 == 0 else Color(0.05, 0.05, 0.05)
			_quad(line, tr.world(float(row), d0, ROAD_LIFT + 0.04), tr.world(float(row + 1), d0, ROAD_LIFT + 0.04),
				tr.world(float(row), d1, ROAD_LIFT + 0.04), tr.world(float(row + 1), d1, ROAD_LIFT + 0.04), c)
	root.add_child(_mesh_instance("StartLine", line, _mat(Color.WHITE, Color(0, 0, 0), true)))
	root.add_child(_gate(tr, th))
	for hz: Node3D in _hazards(tr):
		root.add_child(hz)

	# Ground
	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.name = "Ground"
	var plane: PlaneMesh = PlaneMesh.new()
	var bounds: Vector4 = _bounds(tr)
	var gs: float = 2.0 * (bounds.w + MOUNTAIN_FAR + 250.0) # reaches under the far mountains
	plane.size = Vector2(gs, gs)
	ground.mesh = plane
	ground.position = Vector3(bounds.x, min_y - 3.0, bounds.z) # under the terrain (no z-fight)
	ground.material_override = _ground_mat(th)
	root.add_child(ground)
	var field: TerrainField = TerrainField.new(tr, th.terrain, min_y - 0.5, hash(tr.id) & 0xFFFF)
	root.add_child(WorldDressing.terrain(field, tr, WorldDressing.terrain_mat(th.night)))

	root.add_child(_scenery(tr, th, min_y, field))
	root.add_child(_environment(th))
	return root


static var _tex_cache: Dictionary = {}


## Seamless noise textures shared by the road and patch shaders (built once per run).
static func _noise_tex(key: String, freq: float, size: int, normal: bool) -> NoiseTexture2D:
	if _tex_cache.has(key):
		return _tex_cache[key] as NoiseTexture2D
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = key.hash() & 0xFFFF
	noise.frequency = freq
	noise.fractal_octaves = 4
	var tex: NoiseTexture2D = NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	if normal:
		tex.as_normal_map = true
		tex.bump_strength = 6.0
	_tex_cache[key] = tex
	return tex


## Asphalt (road.gdshader): grain, tyre tracks per lane, patches, cracks, edge dirt.
static func _asphalt(c: Color, night: bool = false) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load("res://src/render/road.gdshader") as Shader
	m.set_shader_parameter("base_color", c)
	m.set_shader_parameter("grain", _noise_tex("grain", 0.06, 256, false))
	m.set_shader_parameter("grain_normal", _noise_tex("grain_n", 0.09, 256, true))
	m.set_shader_parameter("blotch", _noise_tex("blotch", 0.012, 256, false))
	m.set_shader_parameter("lane_w", LANE_W)
	m.set_shader_parameter("curb_w", CURB_W)
	m.set_shader_parameter("wet", 0.6 if night else 0.0)
	return m


## White edge lines and dashed lane dividers (lanes ≈ LANE_W wide, following the local width).
static func _markings(tr: Track) -> SurfaceTool:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = int(ceil(tr.length / STEP))
	var lift: float = ROAD_LIFT + 0.012
	for i: int in n:
		var sa: float = tr.length * float(i) / float(n)
		var sb: float = tr.length * float(i + 1) / float(n)
		var ha: float = tr.half_width(sa)
		var hb: float = tr.half_width(sb)
		for side: float in [-1.0, 1.0]:
			var ea: float = side * (ha - CURB_W - 0.35)
			var eb: float = side * (hb - CURB_W - 0.35)
			_line(st, tr, sa, sb, ea, eb, lift)
		var lanes: int = maxi(2, roundi((2.0 * ha - 2.0 * CURB_W) / LANE_W))
		var in_dash: bool = fmod(sa, DASH_LEN + DASH_GAP) < DASH_LEN
		if not in_dash:
			continue
		for k: int in range(1, lanes):
			var fa: float = -ha + CURB_W + (2.0 * ha - 2.0 * CURB_W) * float(k) / float(lanes)
			var fb: float = -hb + CURB_W + (2.0 * hb - 2.0 * CURB_W) * float(k) / float(lanes)
			_line(st, tr, sa, sb, fa, fb, lift)
	return st


static func _line(st: SurfaceTool, tr: Track, sa: float, sb: float, da: float, db: float, lift: float) -> void:
	var w: float = LINE_W / 2.0
	_quad(st, tr.world(sa, da - w, lift), tr.world(sb, db - w, lift), tr.world(sa, da + w, lift), tr.world(sb, db + w, lift), Color.WHITE)


## Guard-rail posts every POST_EVERY metres on both sides.
static func _posts(tr: Track) -> SurfaceTool:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = int(tr.length / POST_EVERY)
	for i: int in count:
		var s0: float = float(i) * POST_EVERY
		var s1: float = s0 + 0.14
		var h: float = tr.half_width(s0)
		for side: float in [-1.0, 1.0]:
			var d0: float = side * (h + WALL_GAP + 0.06)
			var d1: float = side * (h + WALL_GAP + 0.2)
			var top: float = RAIL_Z1 + 0.05
			_quad(st, tr.world(s0, d0, 0.0), tr.world(s1, d0, 0.0), tr.world(s0, d0, top), tr.world(s1, d0, top), Color.WHITE)
			_quad(st, tr.world(s0, d1, 0.0), tr.world(s0, d0, 0.0), tr.world(s0, d1, top), tr.world(s0, d0, top), Color.WHITE)
			_quad(st, tr.world(s1, d0, 0.0), tr.world(s1, d1, 0.0), tr.world(s1, d0, top), tr.world(s1, d1, top), Color.WHITE)
	return st


static func _quad(st: SurfaceTool, a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3, c: Color) -> void:
	st.set_color(c)
	st.add_vertex(a0)
	st.add_vertex(a1)
	st.add_vertex(b0)
	st.add_vertex(a1)
	st.add_vertex(b1)
	st.add_vertex(b0)


## Start/finish gantry (graphics pass 4): two lattice towers + a truss beam (one metal mesh),
## a banner with the game name in the race font and checkered edges, five red start lights.
static func _gate(tr: Track, th: TrackTheme) -> Node3D:
	var gate: Node3D = Node3D.new()
	gate.name = "StartGate"
	var hw: float = tr.half_width(0.0) + WALL_GAP + 0.9
	var o: Vector3 = tr.world(0.0, 0.0, 0.0)
	var lat: Vector3 = tr.lateral(0.0).normalized()
	var fwd: Vector3 = (tr.world(1.0, 0.0, 0.0) - o).normalized()
	var up: Vector3 = fwd.cross(lat).normalized()
	if up.y < 0.0:
		up = -up
	var P: Callable = func(x: float, y: float, z: float) -> Vector3: return o + lat * x + up * y + fwd * z
	var truss: SurfaceTool = SurfaceTool.new()
	truss.begin(Mesh.PRIMITIVE_TRIANGLES)
	var H: float = 7.6 # beam top
	var tw: float = 0.45 # tower half size
	for side: float in [-1.0, 1.0]:
		var cx: float = side * hw
		var corners: Array[Vector2] = [Vector2(-tw, -tw), Vector2(tw, -tw), Vector2(tw, tw), Vector2(-tw, tw)]
		for c: Vector2 in corners:
			_tube(truss, P.call(cx + c.x, 0.0, c.y), P.call(cx + c.x, H, c.y), 0.06)
		var y: float = 0.0
		var k: int = 0
		while y < H - 0.1: # zig-zag bracing on all four faces
			var y2: float = minf(y + 0.9, H)
			for f: int in 4:
				var a: Vector2 = corners[f]
				var b: Vector2 = corners[(f + 1) % 4]
				if k % 2 == 1:
					var t: Vector2 = a
					a = b
					b = t
				_tube(truss, P.call(cx + a.x, y, a.y), P.call(cx + b.x, y2, b.y), 0.035)
			y = y2
			k += 1
		_tube(truss, P.call(cx - tw - 0.2, 0.0, 0.0), P.call(cx + tw + 0.2, 0.0, 0.0), 0.12) # foot
	# beam: 4 chords + diagonals
	var bh: float = 1.1
	var bz: float = 0.45
	for c2: Vector2 in [Vector2(H - bh, -bz), Vector2(H - bh, bz), Vector2(H, -bz), Vector2(H, bz)]:
		_tube(truss, P.call(-hw, c2.x, c2.y), P.call(hw, c2.x, c2.y), 0.07)
	var n: int = int(2.0 * hw / 1.1)
	for i2: int in n:
		var x0: float = lerpf(-hw, hw, float(i2) / n)
		var x1: float = lerpf(-hw, hw, float(i2 + 1) / n)
		for z: float in [-bz, bz]:
			_tube(truss, P.call(x0, H - bh, z), P.call(x1, H, z), 0.035)
		_tube(truss, P.call(x0, H, -bz), P.call(x1, H, bz), 0.03)
	var metal: StandardMaterial3D = _mat(Color(0.78, 0.8, 0.84))
	metal.metallic = 0.7
	metal.roughness = 0.35
	gate.add_child(_mesh_instance("Truss", truss, metal))
	# banner hanging under the beam, checkered stripes top and bottom
	var ban: SurfaceTool = SurfaceTool.new()
	ban.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bw: float = hw - tw - 0.3
	var y0: float = H - bh - 1.9
	var y1: float = H - bh - 0.05
	var face: Color = Color(0.08, 0.1, 0.28)
	for z3: float in [-0.08, 0.08]:
		_quad(ban, P.call(-bw, y0, z3), P.call(bw, y0, z3), P.call(-bw, y1, z3), P.call(bw, y1, z3), face)
	var cells: int = int(2.0 * bw / 0.35)
	for row: int in 2:
		for e: int in [0, 1]:
			var ya: float = (y1 - 0.35 + 0.175 * row) if e == 0 else (y0 + 0.175 * row)
			for k2: int in cells:
				var xa: float = lerpf(-bw, bw, float(k2) / cells)
				var xb: float = lerpf(-bw, bw, float(k2 + 1) / cells)
				var cc: Color = Color.WHITE if (k2 + row) % 2 == 0 else Color(0.04, 0.04, 0.05)
				for z4: float in [-0.09, 0.09]:
					_quad(ban, P.call(xa, ya, z4), P.call(xb, ya, z4), P.call(xa, ya + 0.175, z4), P.call(xb, ya + 0.175, z4), cc)
	var bm: StandardMaterial3D = _two_sided(_mat(Color.WHITE, Color(0, 0, 0), true))
	bm.roughness = 0.6
	gate.add_child(_mesh_instance("Banner", ban, bm))
	# the game name on both faces
	var font: Font = load("res://assets/fonts/ui_font.tres") as Font
	for dir: float in [-1.0, 1.0]:
		var lb: Label3D = Label3D.new()
		lb.text = "ULTIRACE"
		lb.font = font
		lb.font_size = 160
		lb.pixel_size = 0.0075
		lb.outline_size = 24
		lb.modulate = Color(1.0, 0.78, 0.1)
		lb.outline_modulate = Color(0.02, 0.03, 0.1)
		lb.shaded = false
		lb.double_sided = false
		lb.position = P.call(0.0, (y0 + y1) * 0.5, dir * 0.13)
		var lz: Vector3 = fwd * dir # Label3D reads from its +Z side: point it at that side's drivers
		lb.basis = Basis(up.cross(lz).normalized(), up, lz)
		gate.add_child(lb)
	# start lights under the banner
	var lights: SurfaceTool = SurfaceTool.new()
	lights.begin(Mesh.PRIMITIVE_TRIANGLES)
	for li: int in 5:
		var lx: float = (float(li) - 2.0) * 0.75
		_tube(lights, P.call(lx, y0 - 0.55, -0.15), P.call(lx, y0 - 0.15, -0.15), 0.17)
	var lm: StandardMaterial3D = _mat(Color(0.25, 0.02, 0.02), Color(1.0, 0.1, 0.05))
	gate.add_child(_mesh_instance("StartLights", lights, lm))
	if th.wall_emission != Color(0, 0, 0): # neon: glowing banner frame
		bm.emission_enabled = true
		bm.emission = th.wall_emission * 0.25
	return gate


## Square tube (4 sides) from a to b with half-size r (truss members, lamps).
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var axis: Vector3 = (b - a).normalized()
	var ref: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u: Vector3 = axis.cross(ref).normalized() * r
	var v: Vector3 = axis.cross(u).normalized() * r
	var ring: Array[Vector3] = [u + v, -u + v, -u - v, u - v]
	for k: int in 4:
		var p0: Vector3 = ring[k]
		var p1: Vector3 = ring[(k + 1) % 4]
		_quad(st, a + p0, b + p0, a + p1, b + p1, Color.WHITE)


## Deterministic placeholder scenery (trees / pines / towers) kept clear of the track.
static func _scenery(tr: Track, th: TrackTheme, min_y: float, field: TerrainField) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = "Scenery"
	var rng: Rng = Rng.new(hash(tr.id) & 0x7FFFFFFF)
	var style: String = {"desert": "roadside", "snow": "cabin"}.get(th.terrain, "farm")
	if th.terrain != "desert":
		_forest(node, tr, th, rng, min_y, field)
	for h: Node3D in WorldDressing.houses(field, tr, style, rng, th.night or th.snow):
		node.add_child(h)
	WorldDressing.props(node, field, tr, style, rng)
	node.add_child(_mountains(tr, th, rng, min_y))
	node.add_child(_lamps(tr, th))
	if tr.theme != "neon":
		node.add_child(_clouds(tr, rng))
		node.add_child(_billboards(tr, rng))
	return node


## Current graphics tier ("high" when the Quality autoload is absent, e.g. in tests).
static func _quality_tier() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root.has_node("Quality"):
		return str(tree.root.get_node("Quality").get("tier"))
	return "high"


## (centre x, 0, centre z, radius) of the track's ground footprint.
static func _bounds(tr: Track) -> Vector4:
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	var s: float = 0.0
	while s < tr.length:
		var smp: Track.Sample = tr.at(s)
		lo = Vector2(minf(lo.x, smp.px), minf(lo.y, smp.pz))
		hi = Vector2(maxf(hi.x, smp.px), maxf(hi.y, smp.pz))
		s += 10.0
	return Vector4((lo.x + hi.x) / 2.0, 0.0, (lo.y + hi.y) / 2.0, (hi - lo).length() / 2.0)


## Grass/snow with large soft noise patches (world-space triplanar: no UVs needed).
static func _ground_mat(th: TrackTheme) -> StandardMaterial3D:
	var m: StandardMaterial3D = _mat(th.ground)
	if th.night:
		return m
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(0.8, 0.84, 0.8) if not th.snow else Color(0.9, 0.93, 0.98))
	ramp.set_color(1, Color(1.12, 1.1, 1.0) if not th.snow else Color(1.04, 1.04, 1.04))
	var tex: NoiseTexture2D = NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.02, 0.02, 0.02)
	return m


## Neon city: near buildings along the track plus a distant skyline ring, one MultiMesh drawn
## with city_building.gdshader (procedural lit windows, neon sign bands on some roofs).
static func _city(tr: Track, rng: Rng, min_y: float) -> MultiMeshInstance3D:
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var data: Array[Color] = []
	var tints: Array[Color] = [Color(0.09, 0.08, 0.14), Color(0.13, 0.09, 0.17), Color(0.07, 0.1, 0.15), Color(0.16, 0.12, 0.2), Color(0.1, 0.1, 0.12)]
	for ring: int in 2:
		var s: float = 0.0
		var step: float = 9.0 if ring == 0 else 15.0
		while s < tr.length:
			var smp: Track.Sample = tr.at(s)
			for side: float in [-1.0, 1.0]:
				if rng.next_float() < (0.55 if ring == 0 else 0.35):
					continue
				var dist: float = smp.half_width + 12.0 + rng.next_float() * 60.0 if ring == 0 else 110.0 + rng.next_float() * 220.0
				var p: Vector3 = Vector3(smp.px + smp.nx * side * dist, min_y - 0.5, smp.pz + smp.nz * side * dist)
				if _too_close(tr, p, 14.0 if ring == 0 else 40.0):
					continue
				var h: float = 15.0 + rng.next_float() * 45.0 if ring == 0 else 35.0 + rng.next_float() * 95.0
				var w: float = 8.0 + rng.next_float() * 10.0 if ring == 0 else 14.0 + rng.next_float() * 18.0
				var d: float = w * (0.7 + rng.next_float() * 0.6)
				var yaw: float = atan2(smp.tx, smp.tz)
				xf.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w, h, d)), p + Vector3(0, h / 2.0, 0)))
				cols.append(tints[rng.next_int(tints.size())])
				var hue: float = rng.next_float() if rng.next_float() < 0.35 else -1.0
				data.append(Color(rng.next_float(), hue, p.y + h, 0.0))
			s += step
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var box: BoxMesh = BoxMesh.new()
	mm.mesh = box
	mm.instance_count = xf.size()
	for i: int in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
		mm.set_instance_custom_data(i, data[i])
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "City"
	mmi.multimesh = mm
	var sm: ShaderMaterial = ShaderMaterial.new()
	sm.shader = preload("res://src/render/city_building.gdshader")
	mmi.material_override = sm
	return mmi


## Roadside trees: tiered conifers (snow caps on Frosty) and, on Sunny, round broadleaf trees.
## Two MultiMeshes of vertex-coloured low-poly meshes, slight per-tree colour variation.
static func _forest(node: Node3D, tr: Track, th: TrackTheme, rng: Rng, min_y: float, field: TerrainField) -> void:
	var pines: Array[Transform3D] = []
	var leafy: Array[Transform3D] = []
	var skip: float = 0.45 if _quality_tier() != "low" else 0.62 # low tier: a third fewer trees (triangle budget)
	var s: float = 0.0
	while s < tr.length:
		var smp: Track.Sample = tr.at(s)
		for side: float in [-1.0, 1.0]:
			if rng.next_float() < skip:
				continue
			var dist: float = smp.half_width + 12.0 + rng.next_float() * 70.0
			var p: Vector3 = Vector3(smp.px + smp.nx * side * dist, 0.0, smp.pz + smp.nz * side * dist)
			var near: Vector3 = field.nearest(p.x, p.z)
			if near.x - near.z < 10.0:
				continue
			p.y = field.height(p.x, p.z) - 0.2 # stands on the terrain
			var h: float = 6.0 + rng.next_float() * 8.0
			var b: Basis = Basis(Vector3.UP, rng.next_float() * TAU).scaled(Vector3(h * (0.85 + rng.next_float() * 0.3), h, h * (0.85 + rng.next_float() * 0.3)))
			if th.snow or rng.next_float() < 0.55:
				pines.append(Transform3D(b, p))
			else:
				leafy.append(Transform3D(b.scaled(Vector3(0.9, 0.75, 0.9)), p))
		s += 8.0
	# chunked by 200 m cells: off-screen chunks are culled and only chunks near the camera are drawn
	# again for sun shadows (one big MultiMesh drew every tree in both passes: +100 k triangles)
	# Blender vegetation kit (art/blender/env/vegetation.py): detailed near, light far, per 100 m cell
	EnvKit.scatter(node, "vegetation", "PineSnow" if th.snow else "Pine", pines, rng, EnvKit.foliage_material())
	EnvKit.scatter(node, "vegetation", "Broadleaf", leafy, rng, EnvKit.foliage_material())


static func _tinted_multimesh(name: String, mesh: Mesh, xforms: Array[Transform3D], rng: Rng) -> MultiMeshInstance3D:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		var k: float = 0.85 + rng.next_float() * 0.25
		mm.set_instance_color(i, Color(k, k * (0.95 + rng.next_float() * 0.1), k))
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	var m: StandardMaterial3D = _mat(Color.WHITE, Color(0, 0, 0), true)
	m.roughness = 0.95
	mmi.material_override = m
	return mmi


## Unit-height conifer: trunk + three stacked cone tiers (flat shaded); snow caps optional.
static func _pine_mesh(snow: bool) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = Color(0.36, 0.25, 0.17)
	_prism(st, 0.0, 0.2, 0.045, 6, bark)
	var greens: Array[Color] = [Color(0.12, 0.34, 0.2), Color(0.15, 0.4, 0.22), Color(0.18, 0.45, 0.24)]
	var tiers: Array[Vector3] = [Vector3(0.14, 0.55, 0.36), Vector3(0.38, 0.8, 0.28), Vector3(0.6, 1.0, 0.19)] # y0, y1, radius
	for k: int in tiers.size():
		var t: Vector3 = tiers[k]
		var cap: Color = Color(0.93, 0.95, 1.0) if snow else greens[k].lightened(0.15)
		_tier(st, t.x, t.y, t.z, 8, greens[k], cap, float(k) * 0.4)
	st.generate_normals()
	return st.commit()


## Unit-height broadleaf tree: trunk + three overlapping low-poly blobs.
static func _broadleaf_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_prism(st, 0.0, 0.45, 0.05, 6, Color(0.38, 0.27, 0.18))
	_blob(st, Vector3(0, 0.62, 0), 0.3, Color(0.25, 0.52, 0.2))
	_blob(st, Vector3(0.16, 0.5, 0.08), 0.22, Color(0.29, 0.56, 0.22))
	_blob(st, Vector3(-0.14, 0.52, -0.1), 0.22, Color(0.22, 0.48, 0.19))
	st.generate_normals()
	return st.commit()


static func _prism(st: SurfaceTool, y0: float, y1: float, r: float, n: int, c: Color) -> void:
	for i: int in n:
		var a0: float = TAU * float(i) / float(n)
		var a1: float = TAU * float(i + 1) / float(n)
		var p0: Vector3 = Vector3(cos(a0) * r, y0, sin(a0) * r)
		var p1: Vector3 = Vector3(cos(a1) * r, y0, sin(a1) * r)
		var q0: Vector3 = Vector3(p0.x * 0.8, y1, p0.z * 0.8)
		var q1: Vector3 = Vector3(p1.x * 0.8, y1, p1.z * 0.8)
		for v: Vector3 in [p0, q0, p1, p1, q0, q1]:
			st.set_color(c)
			st.add_vertex(v)


## One cone tier: green lower band, `cap` coloured tip (snow or lighter needles), closed bottom.
static func _tier(st: SurfaceTool, y0: float, y1: float, r: float, n: int, c: Color, cap: Color, rot: float) -> void:
	var ym: float = y0 + (y1 - y0) * 0.5
	var rm: float = r * 0.5
	var apex: Vector3 = Vector3(0, y1, 0)
	for i: int in n:
		var a0: float = rot + TAU * float(i) / float(n)
		var a1: float = rot + TAU * float(i + 1) / float(n)
		var p0: Vector3 = Vector3(cos(a0) * r, y0, sin(a0) * r)
		var p1: Vector3 = Vector3(cos(a1) * r, y0, sin(a1) * r)
		var m0: Vector3 = Vector3(cos(a0) * rm, ym, sin(a0) * rm)
		var m1: Vector3 = Vector3(cos(a1) * rm, ym, sin(a1) * rm)
		for v: Vector3 in [p0, m0, p1, p1, m0, m1]:
			st.set_color(c)
			st.add_vertex(v)
		for v: Vector3 in [m0, apex, m1]:
			st.set_color(cap)
			st.add_vertex(v)


## Low-poly sphere (6 × 4) for leafy canopies.
static func _blob(st: SurfaceTool, c0: Vector3, r: float, c: Color) -> void:
	var n: int = 6
	var rings: int = 4
	for j: int in rings:
		var t0: float = PI * float(j) / float(rings)
		var t1: float = PI * float(j + 1) / float(rings)
		for i: int in n:
			var a0: float = TAU * float(i) / float(n) + float(j) * 0.5
			var a1: float = TAU * float(i + 1) / float(n) + float(j) * 0.5
			var v00: Vector3 = c0 + r * Vector3(sin(t0) * cos(a0), cos(t0), sin(t0) * sin(a0))
			var v01: Vector3 = c0 + r * Vector3(sin(t0) * cos(a1), cos(t0), sin(t0) * sin(a1))
			var v10: Vector3 = c0 + r * Vector3(sin(t1) * cos(a0), cos(t1), sin(t1) * sin(a0))
			var v11: Vector3 = c0 + r * Vector3(sin(t1) * cos(a1), cos(t1), sin(t1) * sin(a1))
			var shade: Color = c.lightened(0.12) if j == 0 else (c if j < 3 else c.darkened(0.2))
			for v: Vector3 in [v00, v01, v10, v10, v01, v11]:
				st.set_color(shade)
				st.add_vertex(v)


const TREE_CHUNK: float = 200.0
const MOUNTAIN_NEAR: float = 420.0 # metres beyond the track's radius
const MOUNTAIN_FAR: float = 700.0


## Horizon (graphics pass 5): two rings of real terrain around the track — near hills and far
## mountains — from ridged fractal noise (sharp crests, valleys), smooth-shaded, coloured by height
## and slope (grass/forest low, rock on steep faces, snow only high up; Frosty: snowy; Desert:
## terraced sandstone mesas), with aerial haze toward the horizon colour baked in. No shadows.
static func _mountains(tr: Track, th: TrackTheme, rng: Rng, min_y: float) -> MeshInstance3D:
	var b: Vector4 = _bounds(tr)
	var centre: Vector3 = Vector3(b.x, min_y - 1.0, b.z)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var desert: bool = th.terrain == "desert"
	var base_index: int = 0
	for ridge: int in 2:
		var r0: float = b.w + (MOUNTAIN_NEAR - 140.0 if ridge == 0 else MOUNTAIN_FAR - 160.0)
		var r1: float = b.w + (MOUNTAIN_NEAR + 230.0 if ridge == 0 else MOUNTAIN_FAR + 520.0)
		var hmax: float = (85.0 if ridge == 0 else 240.0) * (0.7 if desert else 1.0)
		var noise: FastNoiseLite = FastNoiseLite.new()
		noise.seed = rng.next_int(100000)
		noise.frequency = 0.0042 if ridge == 0 else 0.0026
		noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		noise.fractal_octaves = 5
		noise.fractal_gain = 0.5
		var big: FastNoiseLite = FastNoiseLite.new()
		big.seed = noise.seed + 1
		big.frequency = 0.0012
		var na: int = 200
		var nr: int = 12
		var hs: PackedFloat32Array = PackedFloat32Array()
		var ps: PackedVector3Array = PackedVector3Array()
		for i: int in na:
			var a: float = TAU * float(i) / float(na)
			for j: int in nr:
				var u: float = float(j) / float(nr - 1)
				var r: float = lerpf(r0, r1, u)
				var x: float = cos(a) * r
				var z: float = sin(a) * r
				var ridged: float = noise.get_noise_2d(x, z) * 0.5 + 0.5
				var mass: float = big.get_noise_2d(x, z) * 0.5 + 0.5
				var env: float = smoothstep(0.0, 0.4, u) * (1.0 - 0.35 * smoothstep(0.75, 1.0, u))
				var h: float = env * hmax * (0.25 + 0.75 * ridged) * (0.45 + 0.75 * mass)
				if desert: # terraced mesas: flat tops, steep layered walls
					var step: float = 32.0
					var t: float = h / step
					h = (floorf(t) + smoothstep(0.72, 0.95, t - floorf(t))) * step
				hs.append(h)
				ps.append(Vector3(x, h, z))
		# per-vertex normals by finite differences (smooth shading), colours by height/slope
		var haze: float = 0.1 if ridge == 0 else 0.3
		for i: int in na:
			for j: int in nr:
				var k: int = i * nr + j
				var p: Vector3 = ps[k]
				var pa: Vector3 = ps[((i + 1) % na) * nr + j] - ps[((i - 1 + na) % na) * nr + j]
				var pr: Vector3 = ps[i * nr + mini(j + 1, nr - 1)] - ps[i * nr + maxi(j - 1, 0)]
				var n: Vector3 = pr.cross(pa).normalized()
				if n.y < 0.0:
					n = -n
				var slope: float = 1.0 - n.y
				var hf: float = p.y / hmax
				var c: Color = _mountain_color(th, ridge, hf, slope, p)
				st.set_color(c.lerp(th.sky_horizon, haze * (0.6 + 0.4 * float(j) / float(nr - 1))))
				st.set_normal(n)
				st.add_vertex(centre + p)
		for i: int in na:
			var i2: int = (i + 1) % na
			for j: int in nr - 1:
				var a0: int = base_index + i * nr + j
				var a1: int = base_index + i2 * nr + j
				var c0: int = a0 + 1
				var c1: int = a1 + 1
				for idx: int in [a0, c0, a1, a1, c0, c1]:
					st.add_index(idx)
		base_index += na * nr
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = st.commit()
	var m: StandardMaterial3D = _mat(Color.WHITE, Color(0, 0, 0), true)
	m.roughness = 1.0
	m.disable_fog = true # scene fog would wash them out completely at 1 km
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _mountain_color(th: TrackTheme, ridge: int, hf: float, slope: float, p: Vector3) -> Color:
	var v: float = sin(p.x * 0.013 + p.z * 0.017) * 0.5 + 0.5
	if th.terrain == "desert":
		var strata: Array[Color] = [Color(0.46, 0.27, 0.18), Color(0.56, 0.34, 0.22), Color(0.4, 0.23, 0.17), Color(0.6, 0.4, 0.27)]
		var c: Color = strata[int(p.y / 9.0 + v) % strata.size()]
		return c.darkened(0.3 * smoothstep(0.35, 0.7, slope)) if ridge == 0 else c.darkened(0.25)
	if th.snow:
		var rock: Color = Color(0.42, 0.47, 0.56).lerp(Color(0.52, 0.56, 0.64), v)
		var snow: Color = Color(0.93, 0.95, 1.0)
		return snow.lerp(rock, smoothstep(0.45, 0.75, slope) * (1.0 - smoothstep(0.85, 1.0, hf) * 0.5))
	var grass: Color = th.ground.darkened(0.12).lerp(Color(0.36, 0.52, 0.28), 0.3)
	var forest: Color = Color(0.16, 0.3, 0.17).lerp(Color(0.2, 0.34, 0.2), v)
	var rock2: Color = Color(0.46, 0.47, 0.5).lerp(Color(0.55, 0.55, 0.57), v)
	var c2: Color = grass.lerp(forest, smoothstep(0.15, 0.4, hf) * (1.0 - smoothstep(0.55, 0.75, hf)) * (0.6 + 0.4 * v))
	c2 = c2.lerp(rock2, maxf(smoothstep(0.35, 0.65, slope), smoothstep(0.55, 0.75, hf)))
	if ridge == 1 and hf > 0.72: # snowy peaks only on the far mountains
		c2 = c2.lerp(Color(0.95, 0.96, 1.0), smoothstep(0.72, 0.8, hf) * (1.0 - smoothstep(0.55, 0.8, slope) * 0.6))
	return c2


## Roadside billboards: coloured board + white stripe on two posts, angled toward oncoming cars.
## Built into one vertex-coloured mesh (one draw call, no shadows).
static func _billboards(tr: Track, rng: Rng) -> MeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colors: Array[Color] = [Color(0.86, 0.2, 0.18), Color(0.16, 0.42, 0.85), Color(0.98, 0.76, 0.12), Color(0.2, 0.68, 0.4)]
	var post: Color = Color(0.4, 0.42, 0.45)
	var sv: float = 60.0
	var i: int = 0
	while sv < tr.length - 30.0:
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var h: float = tr.half_width(sv)
		var p: Vector3 = tr.world(sv, side * (h + WALL_GAP + 6.0), 0.0)
		if not _too_close(tr, p, 4.0):
			var smp: Track.Sample = tr.at(sv)
			var t: Vector3 = Vector3(smp.tx, 0.0, smp.tz).normalized()
			var q: Vector3 = tr.world(sv, side * h, 0.0)
			var to_road: Vector3 = Vector3(q.x - p.x, 0.0, q.z - p.z).normalized()
			var z: Vector3 = (-t + to_road * 0.6).normalized()
			var x: Vector3 = Vector3.UP.cross(z).normalized()
			var xf: Transform3D = Transform3D(Basis(x, Vector3.UP, z), p)
			var col: Color = colors[rng.next_int(colors.size())]
			_box(st, Vector3(-2.2, 1.6, 0), Vector3(0.12, 1.6, 0.12), post, xf)
			_box(st, Vector3(2.2, 1.6, 0), Vector3(0.12, 1.6, 0.12), post, xf)
			_box(st, Vector3(0, 4.4, 0), Vector3(3.6, 1.5, 0.1), col, xf)
			_box(st, Vector3(-0.6, 4.4, 0.12), Vector3(2.4, 0.32, 0.02), Color(0.97, 0.97, 0.95), xf)
		sv += 130.0 + rng.next_float() * 60.0
		i += 1
	var mi: MeshInstance3D = _mesh_instance("Billboards", st, _two_sided(_mat(Color.WHITE, Color(0, 0, 0), true)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Flattened cloud puffs on a ring around the track (one unshaded MultiMesh, no shadows).
static func _clouds(tr: Track, rng: Rng) -> Node3D:
	var cx: float = 0.0
	var cz: float = 0.0
	var k: int = 0
	var s: float = 0.0
	while s < tr.length:
		var smp: Track.Sample = tr.at(s)
		cx += smp.px
		cz += smp.pz
		k += 1
		s += 20.0
	cx /= float(k)
	cz /= float(k)
	# three cumulus shapes, each instanced around the sky
	var node: Node3D = Node3D.new()
	node.name = "Clouds"
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	var lists: Array = [[] as Array[Transform3D], [] as Array[Transform3D], [] as Array[Transform3D]]
	for i: int in 20:
		var a: float = TAU * (float(i) + rng.next_float() * 0.6) / 20.0
		var r: float = 380.0 + rng.next_float() * 280.0
		var size: float = 26.0 + rng.next_float() * 26.0
		var pos: Vector3 = Vector3(cx + cos(a) * r, 95.0 + rng.next_float() * 70.0, cz + sin(a) * r)
		var b: Basis = Basis(Vector3.UP, rng.next_float() * TAU).scaled(Vector3(size, size * (0.8 + rng.next_float() * 0.4), size))
		(lists[i % 3] as Array[Transform3D]).append(Transform3D(b, pos))
	for v: int in 3:
		var mmi: MultiMeshInstance3D = _multimesh("Cloud%d" % v, _cloud_mesh(rng), lists[v] as Array[Transform3D], mat)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
	return node


## One cumulus (unit size): 7–9 noise-displaced blobs on a flat base, bright tops, cool grey-blue
## undersides (vertex colours; drawn unshaded so the sky look stays consistent).
static func _cloud_mesh(rng: Rng) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = rng.next_int(10000)
	noise.frequency = 1.6
	var blobs: int = 7 + rng.next_int(3)
	for bi: int in blobs:
		var t: float = float(bi) / float(blobs - 1) - 0.5
		var c: Vector3 = Vector3(t * 1.5 + (rng.next_float() - 0.5) * 0.2, 0.0, (rng.next_float() - 0.5) * 0.5)
		var rad: float = (0.45 - absf(t) * 0.35) * (0.8 + rng.next_float() * 0.4)
		c.y = rad * 0.55
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 10
		sphere.rings = 5
		var arr: Array = sphere.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for ii: int in idx:
			var d: Vector3 = verts[ii]
			var w: Vector3 = c + d * rad * (1.0 + 0.22 * noise.get_noise_3d(d.x + c.x * 3.0, d.y, d.z + c.z * 3.0))
			w.y = maxf(w.y, 0.0) # flat base
			var top: float = clampf(w.y / 0.6, 0.0, 1.0)
			var col: Color = Color(0.72, 0.77, 0.86).lerp(Color(1.0, 1.0, 1.0), smoothstep(0.05, 0.6, top))
			st.set_color(col)
			st.add_vertex(w)
	return st.commit()


static func _multimesh(name: String, mesh: Mesh, xforms: Array[Transform3D], mat: Material) -> MultiMeshInstance3D:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi


## Street lamps behind the rails, alternating sides, arm reaching toward the road.
static func _lamps(tr: Track, th: TrackTheme) -> MultiMeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pole: Color = Color(0.42, 0.44, 0.48)
	var head: Color = Color(1.0, 0.95, 0.8)
	_box(st, Vector3(0, 3.6, 0), Vector3(0.09, 3.6, 0.09), pole) # pole, 7.2 m
	_box(st, Vector3(0.9, 7.15, 0), Vector3(0.9, 0.06, 0.06), pole) # arm along +X (toward road)
	_box(st, Vector3(1.75, 7.05, 0), Vector3(0.32, 0.06, 0.14), head) # lamp head
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var xforms: Array[Transform3D] = []
	var count: int = int(tr.length / LAMP_EVERY)
	for i: int in count:
		var sv: float = float(i) * LAMP_EVERY + 7.0
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var h: float = tr.half_width(sv)
		var p: Vector3 = tr.world(sv, side * (h + WALL_GAP + 1.0), 0.0)
		var q: Vector3 = tr.world(sv, side * (h + WALL_GAP), 0.0)
		var x: Vector3 = Vector3(q.x - p.x, 0.0, q.z - p.z).normalized()
		var z: Vector3 = x.cross(Vector3.UP)
		xforms.append(Transform3D(Basis(x, Vector3.UP, z), p))
	var mat: StandardMaterial3D = _two_sided(_mat(Color.WHITE, Color(0, 0, 0), true))
	if th.wall_emission != Color(0, 0, 0):
		mat.emission_enabled = true
		mat.emission = th.wall_emission * 0.25
	var mmi: MultiMeshInstance3D = _multimesh("Lamps", mesh, xforms, mat)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Axis-aligned box (centre c, half extents h) into a vertex-coloured SurfaceTool.
static func _box(st: SurfaceTool, c: Vector3, h: Vector3, col: Color, xf: Transform3D = Transform3D.IDENTITY) -> void:
	var v: Array[Vector3] = []
	for k: int in 8:
		v.append(xf * (c + Vector3(h.x * (1.0 if k & 1 else -1.0), h.y * (1.0 if k & 2 else -1.0), h.z * (1.0 if k & 4 else -1.0))))
	_quad(st, v[0], v[4], v[2], v[6], col)
	_quad(st, v[1], v[3], v[5], v[7], col)
	_quad(st, v[0], v[1], v[4], v[5], col)
	_quad(st, v[2], v[6], v[3], v[7], col)
	_quad(st, v[0], v[2], v[1], v[3], col)
	_quad(st, v[4], v[5], v[6], v[7], col)


static func _too_close(tr: Track, p: Vector3, margin: float) -> bool:
	var s: float = 0.0
	while s < tr.length:
		var smp: Track.Sample = tr.at(s)
		var dx: float = p.x - smp.px
		var dz: float = p.z - smp.pz
		if dx * dx + dz * dz < (smp.half_width + margin) * (smp.half_width + margin):
			return true
		s += 6.0
	return false


static func _environment(th: TrackTheme) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = "Lighting"
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = th.sun_color
	sun.light_energy = th.sun_energy
	sun.rotation_degrees = th.sun_rot
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	node.add_child(sun)
	# rim/fill light from the opposite side, no shadows (GAME_PLAN §4.1: "rim light on cars")
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_color = th.sky_horizon.lerp(Color.WHITE, 0.5)
	rim.light_energy = th.sun_energy * 0.45
	rim.rotation_degrees = Vector3(-25, th.sun_rot.y + 180.0, 0)
	rim.shadow_enabled = false
	node.add_child(rim)
	var env: Environment = Environment.new()
	var sky: Sky = Sky.new()
	if th.night: # stars + city glow (night_sky.gdshader)
		var night: ShaderMaterial = ShaderMaterial.new()
		night.shader = preload("res://src/render/night_sky.gdshader")
		sky.sky_material = night
	else:
		var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = th.sky_top
		sky_mat.sky_horizon_color = th.sky_horizon
		sky_mat.ground_horizon_color = th.sky_horizon
		sky_mat.ground_bottom_color = th.ground
		sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = th.ambient
	# AgX: natural highlight roll-off (bright snow/sky no longer clip; matte cars keep their
	# colour instead of the glossy "plastic" look), a touch of contrast for shape on the boxes
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.15
	env.fog_enabled = true
	env.fog_sky_affect = 0.25 # fog greyed the whole sky (worse under AgX); keep it near the horizon
	env.fog_light_color = th.fog
	env.fog_density = th.fog_density
	env.glow_enabled = th.wall_emission.r + th.wall_emission.g + th.wall_emission.b > 0.0
	if Engine.get_main_loop() != null and (Engine.get_main_loop() as SceneTree).root.has_node("Quality"):
		(Engine.get_main_loop() as SceneTree).root.get_node("Quality").call("configure_environment", env, sun)
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	node.add_child(we)
	return node


## Map hazards (A3): glossy patches on the road (ice, water, oil; one mesh + material per
## kind) and red/white striped concrete road blocks (one vertex-coloured mesh).
static func _hazards(tr: Track) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var looks: Dictionary = {"ice": 0, "water": 1, "oil": 2} # surface_patch.gdshader kinds
	for kind: String in looks:
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any: bool = false
		for h: Dictionary in tr.hazards:
			if h["kind"] != kind:
				continue
			any = true
			_patch(st, tr, h)
		if not any:
			continue
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = load("res://src/render/surface_patch.gdshader") as Shader
		m.set_shader_parameter("kind", int(looks[kind]))
		m.set_shader_parameter("noise", _noise_tex("blotch", 0.012, 256, false))
		m.set_shader_parameter("ripple_normal", _noise_tex("ripple_n", 0.05, 256, true))
		st.index() # shared vertices → smooth normals (flat per-cell normals made the mirror-like water look blocky)
		st.generate_normals()
		st.generate_tangents()
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Hazard_" + kind
		mi.mesh = st.commit()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(mi)
	var blocks: SurfaceTool = SurfaceTool.new()
	blocks.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Dictionary in tr.blocks:
		_block(blocks, tr, b)
	if not tr.blocks.is_empty():
		var bm: StandardMaterial3D = _two_sided(_mat(Color.WHITE, Color(0, 0, 0), true))
		bm.roughness = 0.6
		out.append(_mesh_instance("RoadBlocks", blocks, bm))
	return out


## Jump ramp (graphics pass 5): a kicker that curves up to the lip — dark grippy deck, yellow/black
## hazard stripes along both edges, three yellow chevrons pointing at the lip, a steel lip edge,
## concrete side walls and a striped back face. Visual only (physics launches from the lip).
static func _ramp(st: SurfaceTool, tr: Track, r: Dictionary) -> void:
	var s0: float = float(r["s"])
	var s1: float = s0 + float(r["length"])
	var hw: float = tr.half_width(s0) - 0.3
	var h: float = float(r["height"])
	var deck: Color = Color(0.2, 0.2, 0.22)
	var yellow: Color = Color(1.0, 0.76, 0.08)
	var black: Color = Color(0.06, 0.06, 0.07)
	var concrete: Color = Color(0.6, 0.6, 0.62)
	var steps: int = 12
	var band: float = 0.9 # hazard stripe width at each edge
	var y: Callable = func(t: float) -> float: return h * pow(t, 1.4) + ROAD_LIFT + 0.01
	for k: int in steps:
		var ta: float = float(k) / steps
		var tb: float = float(k + 1) / steps
		var sa: float = lerpf(s0, s1, ta)
		var sb: float = lerpf(s0, s1, tb)
		var ya: float = y.call(ta)
		var yb: float = y.call(tb)
		var stripe: Color = yellow if k % 2 == 0 else black
		_quad(st, tr.world(sa, -hw, ya), tr.world(sb, -hw, yb), tr.world(sa, -hw + band, ya), tr.world(sb, -hw + band, yb), stripe)
		_quad(st, tr.world(sa, hw - band, ya), tr.world(sb, hw - band, yb), tr.world(sa, hw, ya), tr.world(sb, hw, yb), stripe)
		_quad(st, tr.world(sa, -hw + band, ya), tr.world(sb, -hw + band, yb), tr.world(sa, hw - band, ya), tr.world(sb, hw - band, yb),
			deck.lightened(0.04 * float(k % 2)))
		# side walls (concrete), from the road up to the deck edge
		for sd: float in [-hw, hw]:
			_quad(st, tr.world(sa, sd, 0.0), tr.world(sb, sd, 0.0), tr.world(sa, sd, ya), tr.world(sb, sd, yb), concrete.darkened(0.15))
	# chevrons painted on the deck (slightly above it), pointing toward the lip
	for c: int in 3:
		var t0: float = 0.25 + 0.22 * float(c)
		var sc: float = lerpf(s0, s1, t0)
		var len: float = (s1 - s0) * 0.08
		var w: float = (hw - band) * 0.55
		for sgn: float in [-1.0, 1.0]:
			var a0: Vector3 = tr.world(sc, sgn * w, y.call(t0) + 0.02)
			var a1: Vector3 = tr.world(sc + len, 0.0, y.call(t0 + 0.08) + 0.02)
			var b0: Vector3 = tr.world(sc + len * 0.6, sgn * w, y.call(t0 + 0.05) + 0.02)
			var b1: Vector3 = tr.world(sc + len * 1.6, 0.0, y.call(t0 + 0.13) + 0.02)
			if sgn < 0.0:
				_quad(st, a0, b0, a1, b1, yellow)
			else:
				_quad(st, a1, b1, a0, b0, yellow)
	# steel lip edge and the striped back face
	var top: float = h + ROAD_LIFT + 0.01
	_quad(st, tr.world(s1 - 0.25, -hw, top - 0.02), tr.world(s1, -hw, top + 0.03), tr.world(s1 - 0.25, hw, top - 0.02), tr.world(s1, hw, top + 0.03), Color(0.78, 0.8, 0.84))
	var n: int = 10
	for k: int in n:
		var da: float = lerpf(-hw, hw, float(k) / n)
		var db: float = lerpf(-hw, hw, float(k + 1) / n)
		_quad(st, tr.world(s1, da, top), tr.world(s1, db, top), tr.world(s1, da, 0.0), tr.world(s1, db, 0.0), yellow if k % 2 == 0 else black)


## Patch hugging the road: a grid over the hazard's footprint (slightly larger: the shader cuts
## the irregular outline and soft edge). UV = (across −1…1, along 0…1), UV2 = metres (d, s).
static func _patch(st: SurfaceTool, tr: Track, h: Dictionary) -> void:
	var s0: float = float(h["s"])
	var L: float = float(h["len"])
	var d: float = float(h["d"])
	var hw: float = float(h["halfW"]) * 1.08
	var rows: int = maxi(8, int(L / 1.2))
	var cols: int = 8
	var lift: float = ROAD_LIFT + 0.035 # above the lane markings
	for k: int in rows:
		for c: int in cols:
			var corners: Array[Vector2] = []
			for e: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)]:
				var u: float = lerpf(-1.0, 1.0, float(c + e.y) / cols)
				var v: float = float(k + e.x) / rows
				corners.append(Vector2(u, v))
			for uv: Vector2 in corners:
				var dd: float = d + uv.x * hw
				var ss: float = s0 + L * uv.y
				st.set_uv(uv)
				st.set_uv2(Vector2(dd, ss))
				st.add_vertex(tr.world(ss, dd, lift))


## Road block (graphics pass 4), all inside the physics footprint (s0…s0+len, d ± halfW):
## front row of red/white plastic water barriers, a yellow/black chevron sign on two posts
## pointing to the free side, and a grey concrete Jersey barrier at the back.
static func _block(st: SurfaceTool, tr: Track, b: Dictionary) -> void:
	var s0: float = float(b["s"])
	var s1: float = s0 + float(b["len"])
	var d0: float = float(b["d"]) - float(b["halfW"])
	var d1: float = float(b["d"]) + float(b["halfW"])
	var red: Color = Color(0.86, 0.1, 0.08)
	var white: Color = Color(0.94, 0.94, 0.92)
	# front: water barriers ~1 m wide, tapered profile, a moulded rib across each
	var units: int = maxi(3, roundi((d1 - d0) / 1.0))
	for k: int in units:
		var da: float = lerpf(d0, d1, float(k) / units) + 0.03
		var db: float = lerpf(d0, d1, float(k + 1) / units) - 0.03
		var c: Color = red if k % 2 == 0 else white
		_bar(st, tr, s0, s0 + 0.62, 0.16, da, db, ROAD_LIFT, 0.92, c)
		_bar(st, tr, s0 + 0.03, s0 + 0.59, 0.12, da + 0.08, db - 0.08, 0.48, 0.6, c.darkened(0.2))
	# sign on two posts
	var ss: float = s0 + 1.1
	for pd: float in [d0 + 0.5, d1 - 0.5]:
		_bar(st, tr, ss, ss + 0.1, 0.0, pd - 0.05, pd + 0.05, ROAD_LIFT, 1.95, Color(0.35, 0.36, 0.38))
	var y0: float = 1.05
	var y1: float = 1.85
	_bar(st, tr, ss - 0.05, ss, 0.0, d0 + 0.2, d1 - 0.2, y0, y1, Color(1.0, 0.78, 0.05))
	# chevrons point to the free side (toward the road centre)
	var sgn: float = -1.0 if float(b["d"]) > 0.0 else 1.0
	var n_chev: int = maxi(3, int((d1 - d0 - 0.4) / 1.1))
	var w: float = (d1 - d0 - 0.6) / n_chev
	var sf: float = ss - 0.06 # just in front of the panel
	var ink: Color = Color(0.05, 0.05, 0.06)
	for c2: int in n_chev:
		var cx: float = d0 + 0.3 + w * (float(c2) + 0.5)
		var xb: float = cx - sgn * w * 0.3
		var xt: float = cx + sgn * w * 0.3
		var t: float = w * 0.28
		var top: float = y1 - 0.1
		var mid: float = (y0 + y1) * 0.5
		var bot: float = y0 + 0.1
		_quad(st, tr.world(sf, xb, top), tr.world(sf, xb + sgn * t, top), tr.world(sf, xt - sgn * t, mid), tr.world(sf, xt, mid), ink)
		_quad(st, tr.world(sf, xt - sgn * t, mid), tr.world(sf, xt, mid), tr.world(sf, xb, bot), tr.world(sf, xb + sgn * t, bot), ink)
	# back: concrete Jersey barrier on a wider foot
	_bar(st, tr, s1 - 0.72, s1, 0.24, d0, d1, ROAD_LIFT, 0.86, Color(0.66, 0.66, 0.64))
	_bar(st, tr, s1 - 0.8, s1 + 0.04, 0.0, d0 - 0.02, d1 + 0.02, ROAD_LIFT, 0.14, Color(0.55, 0.55, 0.53))


## Box spanning s0…s1 (along the track) and da…db (across), y0…y1, with its top inset by
## `taper` metres front and back (barrier profile).
static func _bar(st: SurfaceTool, tr: Track, s0: float, s1: float, taper: float, da: float, db: float, y0: float, y1: float, c: Color) -> void:
	var t0: float = s0 + taper
	var t1: float = s1 - taper
	var top: Color = c.lightened(0.06)
	var side: Color = c.darkened(0.08)
	_quad(st, tr.world(s0, da, y0), tr.world(s0, db, y0), tr.world(t0, da, y1), tr.world(t0, db, y1), c) # front
	_quad(st, tr.world(s1, db, y0), tr.world(s1, da, y0), tr.world(t1, db, y1), tr.world(t1, da, y1), c) # back
	_quad(st, tr.world(t0, da, y1), tr.world(t0, db, y1), tr.world(t1, da, y1), tr.world(t1, db, y1), top) # top
	_quad(st, tr.world(s1, da, y0), tr.world(s0, da, y0), tr.world(t1, da, y1), tr.world(t0, da, y1), side) # end
	_quad(st, tr.world(s0, db, y0), tr.world(s1, db, y0), tr.world(t0, db, y1), tr.world(t1, db, y1), side) # end
