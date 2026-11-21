class_name Vfx
extends Node3D

## Pooled visual effects (GAME_PLAN §4.4). Purely cosmetic: driven by server events and
## snapshot effect flags. Small pools keep draw calls bounded.

const SPARK_POOL: int = 4
const RING_POOL: int = 2

var _sparks: Array[GPUParticles3D] = []
var _spark_i: int = 0
var _rings: Array[MeshInstance3D] = []
var _ring_t: Array[float] = []
var _ring_i: int = 0
var _trails: Dictionary = {} # car index → GPUParticles3D (boost flames / wind lines)
var _cable: MeshInstance3D
var _cable_t: float = 0.0
var _cable_from: Node3D = null
var _cable_to: Node3D = null


func _ready() -> void:
	for i: int in SPARK_POOL:
		var p: GPUParticles3D = _burst(Color(1.0, 0.75, 0.25), 0.08, 24, 0.35)
		_sparks.append(p)
		add_child(p)
	for i: int in RING_POOL:
		var mi: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.92
		torus.outer_radius = 1.0
		torus.rings = 32
		torus.ring_segments = 6
		mi.mesh = torus
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.7, 0.4, 1.0, 0.8)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		mi.visible = false
		add_child(mi)
		_rings.append(mi)
		_ring_t.append(0.0)
	_cable = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = 1.0
	cyl.radial_segments = 6
	_cable.mesh = cyl
	var cm: StandardMaterial3D = StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(0.2, 0.9, 0.4)
	_cable.material_override = cm
	_cable.visible = false
	add_child(_cable)


static func _burst(color: Color, size: float, amount: int, life: float) -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -18, 0)
	pm.color = color
	p.process_material = pm
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = m
	p.draw_pass_1 = quad
	return p


static var _soft: GradientTexture2D = null


## Soft round particle sprite (no hard squares).
static func soft_dot() -> GradientTexture2D:
	if _soft == null:
		var g: Gradient = Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft


static func _fade_ramp() -> GradientTexture1D:
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var t: GradientTexture1D = GradientTexture1D.new()
	t.gradient = g
	return t


static func _shrink_curve() -> CurveTexture:
	var c: Curve = Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0.2))
	var t: CurveTexture = CurveTexture.new()
	t.curve = c
	return t


static func _trail(color: Color, size: float) -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.amount = 20
	p.lifetime = 0.3
	p.emitting = false
	p.local_coords = false
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.3, 1)
	pm.spread = 12.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.color = color
	pm.color_ramp = _fade_ramp()
	pm.scale_curve = _shrink_curve()
	p.process_material = pm
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = soft_dot()
	quad.material = m
	p.draw_pass_1 = quad
	return p


func sparks(at: Vector3) -> void:
	var p: GPUParticles3D = _sparks[_spark_i]
	_spark_i = (_spark_i + 1) % _sparks.size()
	p.global_position = at
	p.restart()
	p.emitting = true


func ring(at: Vector3, radius: float, color: Color) -> void:
	var mi: MeshInstance3D = _rings[_ring_i]
	_ring_t[_ring_i] = 0.0
	_ring_i = (_ring_i + 1) % _rings.size()
	mi.global_position = at + Vector3.UP * 0.4
	mi.set_meta("radius", radius)
	(mi.material_override as StandardMaterial3D).albedo_color = color
	mi.visible = true


func cable(from: Node3D, to: Node3D, seconds: float) -> void:
	_cable_from = from
	_cable_to = to
	_cable_t = seconds


## Slipstream (drafting) behind another car, from snapshot flags: thin fast air streaks flowing
## back along both sides and the roof (they read as wind, not smoke). Boost flames come from the
## car's exhaust tips (ExhaustFx).
func car_trail(i: int, car: Node3D, _boost: bool, draft: bool) -> void:
	var raw: Variant = _trails.get(i, null)
	var t: GPUParticles3D = null
	if raw != null and is_instance_valid(raw) and (raw as GPUParticles3D).get_parent() == car:
		t = raw as GPUParticles3D # (cars are rebuilt every race: stale entries are ignored)
	if t == null:
		if not draft:
			return
		t = _streaks()
		car.add_child(t)
		_trails[i] = t
	t.emitting = draft
	t.visible = draft or t.emitting


## Air streaks in the car's frame: long thin quads (one flat, one upright, crossed) along Z, emitted
## at the sides and the roof edges, moving backward (+Z is the car's rear).
static func _streaks() -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.28
	p.local_coords = true
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	var pts: PackedVector3Array = PackedVector3Array([Vector3(-1.12, 0.25, -0.6), Vector3(1.12, 0.25, -0.6),
		Vector3(-0.6, 0.75, 0.0), Vector3(0.6, 0.75, 0.0), Vector3(-1.05, 0.0, 0.8), Vector3(1.05, 0.0, 0.8)])
	var img: Image = Image.create(pts.size(), 1, false, Image.FORMAT_RGBF)
	for k: int in pts.size():
		img.set_pixel(k, 0, Color(pts[k].x, pts[k].y, pts[k].z))
	pm.emission_point_texture = ImageTexture.create_from_image(img)
	pm.emission_point_count = pts.size()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 2.0
	pm.initial_velocity_min = 14.0
	pm.initial_velocity_max = 18.0
	pm.gravity = Vector3.ZERO
	pm.color_ramp = _fade_ramp()
	pm.color = Color(1, 1, 1, 0.35)
	p.process_material = pm
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L: float = 1.6
	var w: float = 0.025
	for q: Array in [[Vector3(-w, 0, -L / 2), Vector3(w, 0, -L / 2), Vector3(w, 0, L / 2), Vector3(-w, 0, L / 2)],
			[Vector3(0, -w, -L / 2), Vector3(0, w, -L / 2), Vector3(0, w, L / 2), Vector3(0, -w, L / 2)]]:
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_uv(Vector2(0.5, 0.5))
			st.add_vertex(q[idx] as Vector3)
	var mesh: ArrayMesh = st.commit()
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, m)
	p.draw_pass_1 = mesh
	return p


func _process(delta: float) -> void:
	for i: int in _rings.size():
		var mi: MeshInstance3D = _rings[i]
		if not mi.visible:
			continue
		_ring_t[i] += delta
		var k: float = _ring_t[i] / 0.45
		var r: float = float(mi.get_meta("radius", 18.0)) * k
		mi.scale = Vector3(r, 1.0, r)
		(mi.material_override as StandardMaterial3D).albedo_color.a = 0.8 * (1.0 - k)
		if k >= 1.0:
			mi.visible = false
	_cable_t -= delta
	_cable.visible = _cable_t > 0.0 and is_instance_valid(_cable_from) and is_instance_valid(_cable_to)
	if _cable.visible:
		var a: Vector3 = _cable_from.global_position + Vector3.UP * 1.2
		var b: Vector3 = _cable_to.global_position + Vector3.UP * 0.8
		var mid: Vector3 = (a + b) / 2.0
		var dir: Vector3 = b - a
		var basis: Basis = Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)
		basis = basis * Basis(Vector3.RIGHT, PI / 2.0) # cylinder axis (Y) → along the cable
		_cable.global_transform = Transform3D(basis.scaled(Vector3(1, dir.length(), 1)), mid)
