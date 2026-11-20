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


static func theme_for(theme_id: String) -> TrackTheme:
	var t: TrackTheme = TrackTheme.new()
	match theme_id:
		"neon":
			t.road = Color(0.09, 0.09, 0.12)
			t.curb_a = Color(0.95, 0.2, 0.75)
			t.curb_b = Color(0.15, 0.85, 1.0)
			t.wall = Color(0.12, 0.12, 0.18)
			t.wall_emission = Color(0.2, 0.9, 1.0)
			t.ground = Color(0.04, 0.04, 0.07)
			t.skirt = Color(0.1, 0.1, 0.14)
			t.sky_top = Color(0.02, 0.02, 0.08)
			t.sky_horizon = Color(0.25, 0.08, 0.35)
			t.sun_color = Color(0.6, 0.6, 1.0)
			t.sun_energy = 0.6
			t.sun_rot = Vector3(-50, 30, 0)
			t.ambient = 1.1
			t.fog = Color(0.12, 0.05, 0.2)
			t.fog_density = 0.0008
			t.pillars = true
			t.prop_color = Color(0.1, 0.1, 0.16)
			t.prop_emission = Color(1.0, 0.3, 0.8)
			t.night = true
		"frosty":
			t.road = Color(0.26, 0.28, 0.32)
			t.curb_a = Color(0.85, 0.15, 0.15)
			t.curb_b = Color(0.95, 0.95, 0.97)
			t.wall = Color(0.75, 0.82, 0.9)
			t.wall_emission = Color(0, 0, 0)
			t.ground = Color(0.9, 0.93, 0.97)
			t.skirt = Color(0.55, 0.58, 0.64)
			t.sky_top = Color(0.35, 0.5, 0.75)
			t.sky_horizon = Color(0.82, 0.88, 0.95)
			t.sun_color = Color(1.0, 0.95, 0.9)
			t.sun_energy = 1.1
			t.sun_rot = Vector3(-35, -40, 0)
			t.ambient = 0.6
			t.fog = Color(0.85, 0.9, 0.96)
			t.fog_density = 0.0009
			t.pillars = false
			t.prop_color = Color(0.13, 0.3, 0.2)
			t.prop_emission = Color(0, 0, 0)
			t.snow = true
		_:
			t.road = Color(0.24, 0.24, 0.26)
			t.curb_a = Color(0.9, 0.15, 0.12)
			t.curb_b = Color(0.97, 0.97, 0.97)
			t.wall = Color(0.95, 0.95, 0.95)
			t.wall_emission = Color(0, 0, 0)
			t.ground = Color(0.35, 0.62, 0.25)
			t.skirt = Color(0.45, 0.36, 0.25)
			t.sky_top = Color(0.25, 0.5, 0.9)
			t.sky_horizon = Color(0.75, 0.85, 0.95)
			t.sun_color = Color(1.0, 0.92, 0.78)
			t.sun_energy = 1.2
			t.sun_rot = Vector3(-40, 50, 0)
			t.ambient = 0.5
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
		var a0: Vector3 = tr.world(sa, -ha, ROAD_LIFT)
		var a1: Vector3 = tr.world(sa, ha, ROAD_LIFT)
		var b0: Vector3 = tr.world(sb, -hb, ROAD_LIFT)
		var b1: Vector3 = tr.world(sb, hb, ROAD_LIFT)
		road.add_vertex(a0)
		road.add_vertex(a1)
		road.add_vertex(b0)
		road.add_vertex(a1)
		road.add_vertex(b1)
		road.add_vertex(b0)
	root.add_child(_mesh_instance("Road", road, _asphalt(th.road)))
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
			# curb: inner strip just inside the road edge, slightly raised
			_quad(curbs, tr.world(sa, side * (ha - CURB_W), ROAD_LIFT + 0.03), tr.world(sb, side * (hb - CURB_W), ROAD_LIFT + 0.03),
				tr.world(sa, side * ha, ROAD_LIFT + 0.03), tr.world(sb, side * hb, ROAD_LIFT + 0.03), curb_col)
			# wall: vertical face at the edge
			var wa: float = side * (ha + WALL_GAP)
			var wb: float = side * (hb + WALL_GAP)
			if guard_rails:
				# W-beam guard rail on posts (reference look): a steel band plus its top lip
				_quad(walls, tr.world(sa, wa, RAIL_Z0), tr.world(sb, wb, RAIL_Z0), tr.world(sa, wa, RAIL_Z1), tr.world(sb, wb, RAIL_Z1), th.wall)
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
		var s0: float = float(r["s"])
		var s1: float = s0 + float(r["length"])
		var hw0: float = tr.half_width(s0) - 0.3
		var h: float = float(r["height"])
		var steps: int = 6
		for k: int in steps:
			var sa: float = lerpf(s0, s1, float(k) / steps)
			var sb: float = lerpf(s0, s1, float(k + 1) / steps)
			var ya: float = h * float(k) / steps + ROAD_LIFT + 0.01
			var yb: float = h * float(k + 1) / steps + ROAD_LIFT + 0.01
			_quad(ramps, tr.world(sa, -hw0, ya), tr.world(sb, -hw0, yb), tr.world(sa, hw0, ya), tr.world(sb, hw0, yb), Color(1, 0.75, 0.1))
		_quad(ramps, tr.world(s1, -hw0, h + ROAD_LIFT + 0.01), tr.world(s1, hw0, h + ROAD_LIFT + 0.01), tr.world(s1, -hw0, 0.0), tr.world(s1, hw0, 0.0), Color(0.3, 0.3, 0.3))
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
	ground.position = Vector3(bounds.x, min_y - 0.5, bounds.z)
	ground.material_override = _ground_mat(th)
	root.add_child(ground)

	root.add_child(_scenery(tr, th, min_y))
	root.add_child(_environment(th))
	return root


## Asphalt: the theme colour broken up by fine world-space noise (no flat placeholder grey).
static func _asphalt(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = _mat(c)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(0.82, 0.82, 0.84))
	ramp.set_color(1, Color(1.06, 1.06, 1.06))
	var tex: NoiseTexture2D = NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.12, 0.12, 0.12)
	m.roughness = 0.85
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


static func _gate(tr: Track, th: TrackTheme) -> Node3D:
	var gate: Node3D = Node3D.new()
	gate.name = "StartGate"
	var hw: float = tr.half_width(0.0) + WALL_GAP + 0.6
	var post: BoxMesh = BoxMesh.new()
	post.size = Vector3(0.8, 7.0, 0.8)
	var mat: StandardMaterial3D = _mat(Color(0.15, 0.15, 0.18), th.wall_emission)
	for side: float in [-1.0, 1.0]:
		var p: Vector3 = tr.world(0.0, side * hw, 3.5)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = post
		mi.material_override = mat
		mi.position = p
		gate.add_child(mi)
	var bar: BoxMesh = BoxMesh.new()
	bar.size = Vector3(2.0 * hw + 0.8, 1.2, 0.8)
	var mb: MeshInstance3D = MeshInstance3D.new()
	mb.mesh = bar
	mb.material_override = _mat(Color(0.95, 0.75, 0.1), th.wall_emission)
	var center: Vector3 = tr.world(0.0, 0.0, 7.0)
	var lat: Vector3 = tr.lateral(0.0)
	mb.transform = Transform3D(Basis.looking_at(lat.cross(Vector3.UP).normalized(), Vector3.UP), center)
	gate.add_child(mb)
	return gate


## Deterministic placeholder scenery (trees / pines / towers) kept clear of the track.
static func _scenery(tr: Track, th: TrackTheme, min_y: float) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = "Scenery"
	var rng: Rng = Rng.new(hash(tr.id) & 0x7FFFFFFF)
	if tr.theme == "neon":
		node.add_child(_city(tr, rng, min_y))
	else:
		_forest(node, tr, th, rng, min_y)
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
static func _forest(node: Node3D, tr: Track, th: TrackTheme, rng: Rng, min_y: float) -> void:
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
			var p: Vector3 = Vector3(smp.px + smp.nx * side * dist, min_y - 0.5, smp.pz + smp.nz * side * dist)
			if _too_close(tr, p, 14.0):
				continue
			var h: float = 6.0 + rng.next_float() * 8.0
			var b: Basis = Basis(Vector3.UP, rng.next_float() * TAU).scaled(Vector3(h * (0.85 + rng.next_float() * 0.3), h, h * (0.85 + rng.next_float() * 0.3)))
			if th.snow or rng.next_float() < 0.55:
				pines.append(Transform3D(b, p))
			else:
				leafy.append(Transform3D(b.scaled(Vector3(0.9, 0.75, 0.9)), p))
		s += 8.0
	# chunked by 200 m cells: off-screen chunks are culled and only chunks near the camera are drawn
	# again for sun shadows (one big MultiMesh drew every tree in both passes: +100 k triangles)
	var pine_mesh: ArrayMesh = _pine_mesh(th.snow)
	var leaf_mesh: ArrayMesh = _broadleaf_mesh()
	for kind: int in 2:
		var cells: Dictionary = {}
		for t: Transform3D in (pines if kind == 0 else leafy):
			var key: Vector2i = Vector2i(floori(t.origin.x / TREE_CHUNK), floori(t.origin.z / TREE_CHUNK))
			if not cells.has(key):
				cells[key] = [] as Array[Transform3D]
			(cells[key] as Array[Transform3D]).append(t)
		for key: Vector2i in cells:
			node.add_child(_tinted_multimesh("Pines" if kind == 0 else "Broadleaf", pine_mesh if kind == 0 else leaf_mesh,
				cells[key] as Array[Transform3D], rng))


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


## Horizon: a ring of green hills and a ring of taller blue-grey mountains with snow tops (Frosty:
## all snowy), one vertex-coloured flat-shaded mesh, no shadows. Fog hazes it into the sky.
static func _mountains(tr: Track, th: TrackTheme, rng: Rng, min_y: float) -> MeshInstance3D:
	var b: Vector4 = _bounds(tr)
	var centre: Vector3 = Vector3(b.x, min_y - 1.0, b.z)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 96
	for ridge: int in 2:
		var r: float = b.w + (MOUNTAIN_NEAR if ridge == 0 else MOUNTAIN_FAR)
		var hmin: float = 35.0 if ridge == 0 else 90.0
		var hmax: float = 90.0 if ridge == 0 else 230.0
		var ph: Array[float] = [rng.next_float() * TAU, rng.next_float() * TAU, rng.next_float() * TAU]
		var low: Color = th.ground.darkened(0.2) if ridge == 0 else Color(0.3, 0.4, 0.5)
		if th.snow: # bluish rock flanks under the snow, so the peaks read against a pale sky
			low = Color(0.4, 0.46, 0.56) if ridge == 0 else Color(0.28, 0.34, 0.46)
		var rock: Color = Color(0.45, 0.47, 0.52) if ridge == 1 else th.ground.darkened(0.3)
		var crest: Array[Vector3] = []
		for i: int in n:
			var a: float = TAU * float(i) / float(n)
			var wave: float = 0.5 + 0.25 * sin(a * 3.0 + ph[0]) + 0.15 * sin(a * 7.0 + ph[1]) + 0.1 * sin(a * 13.0 + ph[2])
			var h: float = lerpf(hmin, hmax, clampf(wave + (rng.next_float() - 0.5) * 0.25, 0.0, 1.0))
			crest.append(centre + Vector3(cos(a) * r, h, sin(a) * r))
		for i: int in n:
			var j: int = (i + 1) % n
			var a0: Vector3 = crest[i]
			var a1: Vector3 = crest[j]
			var f0: Vector3 = centre + (Vector3(a0.x, 0, a0.z) - Vector3(centre.x, 0, centre.z)) * (1.0 - 120.0 / r) # front foot
			var f1: Vector3 = centre + (Vector3(a1.x, 0, a1.z) - Vector3(centre.x, 0, centre.z)) * (1.0 - 120.0 / r)
			f0.y = centre.y
			f1.y = centre.y
			var top: float = maxf(a0.y, a1.y) - centre.y
			var snowy: bool = th.snow or (ridge == 1 and top > 150.0)
			var cap: Color = Color(0.95, 0.96, 1.0) if snowy else rock
			var haze: float = 0.12 if ridge == 0 else 0.3 # aerial perspective, baked (no scene fog)
			# two bands: rock/grass up to the snow line, then a crisp cap (no washed-out gradient)
			var k: float = 0.62 if snowy else 0.8
			var s0: Vector3 = f0.lerp(a0, k)
			var s1: Vector3 = f1.lerp(a1, k)
			var lo_c: Color = low.lerp(th.sky_horizon, haze)
			var hi_c: Color = cap.lerp(th.sky_horizon, haze * 0.5)
			for v: Vector3 in [f0, s0, f1, f1, s0, s1]:
				st.set_color(lo_c)
				st.add_vertex(v)
			for v: Vector3 in [s0, a0, s1, s1, a0, a1]:
				st.set_color(hi_c)
				st.add_vertex(v)
	st.generate_normals()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = st.commit()
	var m: StandardMaterial3D = _mat(Color.WHITE, Color(0, 0, 0), true)
	m.roughness = 1.0
	m.disable_fog = true # scene fog would wash them out completely at 1 km
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


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
static func _clouds(tr: Track, rng: Rng) -> MultiMeshInstance3D:
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
	var puff: SphereMesh = SphereMesh.new()
	puff.radial_segments = 10
	puff.rings = 5
	var xforms: Array[Transform3D] = []
	for i: int in 22:
		var a: float = TAU * (float(i) + rng.next_float() * 0.6) / 22.0
		var r: float = 380.0 + rng.next_float() * 260.0
		var base: Vector3 = Vector3(cx + cos(a) * r, 90.0 + rng.next_float() * 60.0, cz + sin(a) * r)
		var size: float = 22.0 + rng.next_float() * 22.0
		for j: int in 3: # each cloud = 3 overlapping puffs
			var off: Vector3 = Vector3((float(j) - 1.0) * size * 0.8, rng.next_float() * size * 0.15, (rng.next_float() - 0.5) * size * 0.6)
			var sc: float = size * (1.0 if j == 1 else 0.7)
			xforms.append(Transform3D(Basis.from_scale(Vector3(sc, sc * 0.32, sc * 0.7)), base + off))
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.disable_fog = true
	var mmi: MultiMeshInstance3D = _multimesh("Clouds", puff, xforms, mat)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


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
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
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
	var looks: Dictionary = {
		"ice": [Color(0.78, 0.92, 1.0, 0.78), 0.04, 0.15],
		"water": [Color(0.12, 0.24, 0.36, 0.72), 0.02, 0.35],
		"oil": [Color(0.02, 0.02, 0.03, 0.88), 0.06, 0.25],
	}
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
		var look: Array = looks[kind] as Array
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = look[0] as Color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = float(look[1])
		m.metallic = float(look[2])
		m.specular = 0.9
		var mi: MeshInstance3D = _mesh_instance("Hazard_" + kind, st, m)
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


## Irregular rounded puddle/patch hugging the road: rows across s, width tapering at the ends.
static func _patch(st: SurfaceTool, tr: Track, h: Dictionary) -> void:
	var s0: float = float(h["s"])
	var L: float = float(h["len"])
	var d: float = float(h["d"])
	var hw: float = float(h["halfW"])
	var rows: int = 10
	var lift: float = ROAD_LIFT + 0.035 # above the lane markings
	for k: int in rows:
		var ua: float = float(k) / rows
		var ub: float = float(k + 1) / rows
		var wa: float = hw * (0.55 + 0.45 * sin(PI * ua)) * (1.0 + 0.08 * sin(ua * 17.0 + s0))
		var wb: float = hw * (0.55 + 0.45 * sin(PI * ub)) * (1.0 + 0.08 * sin(ub * 17.0 + s0))
		var sa: float = s0 + L * ua
		var sb: float = s0 + L * ub
		_quad(st, tr.world(sa, d - wa, lift), tr.world(sb, d - wb, lift), tr.world(sa, d + wa, lift), tr.world(sb, d + wb, lift), Color.WHITE)


## Concrete road block: 1 m high box over the block's footprint, red/white chevron stripes on
## the faces drivers see, grey top.
static func _block(st: SurfaceTool, tr: Track, b: Dictionary) -> void:
	var s0: float = float(b["s"])
	var s1: float = s0 + float(b["len"])
	var d0: float = float(b["d"]) - float(b["halfW"])
	var d1: float = float(b["d"]) + float(b["halfW"])
	var y0: float = ROAD_LIFT
	var y1: float = 1.0
	var stripes: int = maxi(4, int((d1 - d0) / 0.9))
	var red: Color = Color(0.85, 0.12, 0.1)
	for k: int in stripes:
		var da: float = lerpf(d0, d1, float(k) / stripes)
		var db: float = lerpf(d0, d1, float(k + 1) / stripes)
		var c: Color = red if k % 2 == 0 else Color(0.95, 0.95, 0.95)
		# front (faces oncoming cars) and back
		_quad(st, tr.world(s0, da, y0), tr.world(s0, da, y1), tr.world(s0, db, y0), tr.world(s0, db, y1), c)
		_quad(st, tr.world(s1, db, y0), tr.world(s1, db, y1), tr.world(s1, da, y0), tr.world(s1, da, y1), c)
		_quad(st, tr.world(s0, da, y1), tr.world(s1, da, y1), tr.world(s0, db, y1), tr.world(s1, db, y1), Color(0.6, 0.6, 0.62))
	# sides
	_quad(st, tr.world(s0, d0, y0), tr.world(s1, d0, y0), tr.world(s0, d0, y1), tr.world(s1, d0, y1), Color(0.9, 0.9, 0.9))
	_quad(st, tr.world(s1, d1, y0), tr.world(s0, d1, y0), tr.world(s1, d1, y1), tr.world(s0, d1, y1), Color(0.9, 0.9, 0.9))
