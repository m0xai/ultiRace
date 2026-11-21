class_name ExhaustFx
extends Node3D

## Exhaust smoke and boost flames at a car's real exhaust tips (the models carry "ExhaustTip_<i>"
## empties from art/blender/lib/carkit4.py exhausts(); their −Z points out of the pipe).
## One smoke emitter + one flame emitter per car, emitting at all tips (emission points), so a
## car costs at most two draw calls, and only while it is near the camera / boosting.
## Smoke: soft noisy puffs that grow, rise and fade; heavier when pulling away under load,
## thinner at speed, none when coasting. Purely cosmetic.

const NEAR_M: float = 50.0 # smoke only for cars this close to the camera

## Per-car look: smoke colour (alpha = density), puff size, flame colour. Volt is electric:
## no smoke, cyan sparks.
const STYLE: Dictionary = {
	"bolt": {"smoke": Color(0.86, 0.86, 0.9, 0.14), "size": 0.42, "flame": Color(0.45, 0.62, 1.0)},
	"rhino": {"smoke": Color(0.32, 0.32, 0.34, 0.26), "size": 0.55, "flame": Color(1.0, 0.5, 0.15)},
	"glacier": {"smoke": Color(0.88, 0.93, 1.0, 0.16), "size": 0.42, "flame": Color(0.55, 0.85, 1.0)},
	"volt": {"smoke": Color(0, 0, 0, 0), "size": 0.0, "flame": Color(0.35, 0.95, 1.0)},
	"hook": {"smoke": Color(0.28, 0.28, 0.29, 0.28), "size": 0.5, "flame": Color(1.0, 0.55, 0.18)},
	"goo": {"smoke": Color(0.5, 0.58, 0.42, 0.24), "size": 0.5, "flame": Color(0.75, 1.0, 0.25)},
	"phantom": {"smoke": Color(0.85, 0.9, 0.98, 0.1), "size": 0.38, "flame": Color(0.6, 0.9, 1.0)},
	"twister": {"smoke": Color(0.72, 0.76, 0.82, 0.18), "size": 0.42, "flame": Color(1.0, 0.42, 0.12)},
}

static var _puff_tex: ImageTexture = null
static var _dot_tex: Texture2D = null

var _tips: Array[Transform3D] = [] # car-local
var _smoke: GPUParticles3D = null
var _flame: GPUParticles3D = null
var _style: Dictionary = {}


## tips: car-local transforms of the exhaust openings (empty → rear centre, low; e.g. Volt).
func setup(vehicle_id: String, tips: Array[Transform3D]) -> void:
	_style = STYLE.get(vehicle_id, STYLE["bolt"]) as Dictionary
	_tips = tips
	if _tips.is_empty():
		_tips.append(Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0, -0.15, 2.1)))
	var pts: PackedVector3Array = PackedVector3Array()
	var dir: Vector3 = Vector3.ZERO
	for t: Transform3D in _tips:
		pts.append(t.origin)
		dir += -t.basis.z
	dir = dir.normalized()
	if (_style["smoke"] as Color).a > 0.0:
		_smoke = _make_smoke(pts, dir)
		add_child(_smoke)
	_flame = _make_flame(pts, dir)
	add_child(_flame)


## speed m/s, load 0–1 (EngineSound), top speed, boosting flag, distance to the camera.
func update(speed: float, load: float, top: float, boosting: bool, cam_dist: float) -> void:
	if _smoke != null:
		var near: bool = cam_dist < NEAR_M
		var x: float = clampf(speed / maxf(top, 1.0), 0.0, 1.0)
		# idle puffs → thick when pulling away under load → thin at speed; none when coasting
		var rate: float = (0.35 + 0.9 * load * (1.0 - x)) * (0.25 + 0.75 * load) * (1.0 - 0.6 * x)
		_smoke.visible = near
		_smoke.emitting = near and rate > 0.05
		_smoke.amount_ratio = clampf(rate, 0.05, 1.0)
	_flame.visible = boosting
	_flame.emitting = boosting


func _make_smoke(pts: PackedVector3Array, dir: Vector3) -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.amount = 40 * pts.size()
	p.lifetime = 1.1
	p.local_coords = false # puffs stay in the world: they trail behind the moving car
	p.fixed_fps = 30
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 8, 30))
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = _points_tex(pts)
	pm.emission_point_count = pts.size()
	pm.direction = dir
	pm.spread = 14.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0, 0.7, 0) # warm exhaust rises a little
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -40.0
	pm.angular_velocity_max = 40.0
	var s: float = float(_style["size"])
	pm.scale_min = s * 0.8
	pm.scale_max = s * 1.2
	pm.scale_curve = _curve([Vector2(0, 0.2), Vector2(0.3, 0.9), Vector2(1, 2.9)])
	var c: Color = _style["smoke"] as Color
	pm.color = Color(c.r, c.g, c.b, 1.0)
	pm.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.0)], [0.06, Color(1, 1, 1, c.a)], [0.4, Color(1, 1, 1, c.a * 0.45)], [1.0, Color(1, 1, 1, 0.0)]])
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	p.process_material = pm
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1, 1)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = puff_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX # lit like the scene (dark at night)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.disable_receive_shadows = true
	m.proximity_fade_enabled = true # no hard cut where puffs touch the road
	m.proximity_fade_distance = 0.4
	quad.material = m
	p.draw_pass_1 = quad
	return p


func _make_flame(pts: PackedVector3Array, dir: Vector3) -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.amount = 30 * pts.size()
	p.lifetime = 0.2
	p.local_coords = true # flames stick to the pipe
	p.emitting = false
	p.visible = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = _points_tex(pts)
	pm.emission_point_count = pts.size()
	pm.direction = dir
	pm.spread = 6.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.7
	pm.scale_max = 1.1
	pm.scale_curve = _curve([Vector2(0, 0.7), Vector2(0.15, 1.0), Vector2(1, 0.2)])
	var f: Color = _style["flame"] as Color
	# white-hot core → the car's flame colour → transparent
	pm.color_ramp = _ramp([[0.0, Color(1, 1, 1, 1)], [0.25, Color(f, 0.95)], [1.0, Color(f.darkened(0.3), 0.0)]])
	p.process_material = pm
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.62, 0.62)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _dot()
	quad.material = m
	p.draw_pass_1 = quad
	return p


## Soft, lumpy smoke puff (alpha): radial falloff × fractal noise, cached.
static func puff_texture() -> ImageTexture:
	if _puff_tex != null:
		return _puff_tex
	var n: int = 64
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.09
	noise.fractal_octaves = 4
	for y: int in n:
		for x: int in n:
			var d: float = Vector2(float(x) - n / 2.0 + 0.5, float(y) - n / 2.0 + 0.5).length() / (n / 2.0)
			var nv: float = noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var a: float = clampf(1.0 - smoothstep(0.35 + 0.35 * nv, 1.0, d), 0.0, 1.0) * (0.55 + 0.45 * nv)
			var shade: float = 0.85 + 0.15 * nv # a little self-shadowing inside the puff
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex


static func _dot() -> Texture2D:
	if _dot_tex == null:
		_dot_tex = Vfx.soft_dot()
	return _dot_tex


static func _points_tex(pts: PackedVector3Array) -> ImageTexture:
	var img: Image = Image.create(pts.size(), 1, false, Image.FORMAT_RGBF)
	for i: int in pts.size():
		img.set_pixel(i, 0, Color(pts[i].x, pts[i].y, pts[i].z))
	return ImageTexture.create_from_image(img)


static func _curve(points: Array[Vector2]) -> CurveTexture:
	var c: Curve = Curve.new()
	c.max_value = 3.0
	for v: Vector2 in points:
		c.add_point(v)
	var t: CurveTexture = CurveTexture.new()
	t.curve = c
	return t


static func _ramp(stops: Array) -> GradientTexture1D:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for st: Variant in stops:
		var a: Array = st as Array
		g.add_point(float(a[0]), a[1] as Color)
	var t: GradientTexture1D = GradientTexture1D.new()
	t.gradient = g
	return t
