class_name CarView
extends Node3D

## One car's visual (GAME_PLAN §4.4). The same scene serves all 8 vehicles; configure() sets
## colour and name from vehicles.json. Placeholder body until the M8 Blender cars.

const RIDE_HEIGHT: float = 0.55
const MAX_SPIN_STEP: float = 0.3 # rad per frame (< half the gap of a 5-spoke rim, 0.63)

@onready var _body: MeshInstance3D = $Body
@onready var _cabin: MeshInstance3D = $Cabin
@onready var _tag: Label3D = $Tag

var vehicle_id: String = ""


var _model: Node3D = null
var _wheels: Array[Node3D] = []
var _front: Array[Node3D] = []
var _rest: Dictionary = {} # wheel → rest Basis (as exported)
var _wheel_spin: float = 0.0
var _steer: float = 0.0
var _wheel_r: float = 0.4
var _last_s: float = -1.0
var _last_yaw: float = 0.0


func configure(vehicle: String, display_name: String, is_you: bool) -> void:
	vehicle_id = vehicle
	var v: Dictionary = GameData.vehicle(vehicle)
	_load_model(vehicle)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color.html(v.get("color", "#cccccc") as String)
	mat.roughness = 0.4
	_body.material_override = mat
	var cab: StandardMaterial3D = StandardMaterial3D.new()
	cab.albedo_color = Color(0.1, 0.12, 0.16)
	cab.roughness = 0.2
	_cabin.material_override = cab
	if is_you:
		force_lod0 = true
		_apply_lod(0)
	_tag.text = ("▼ " if is_you else "") + display_name
	_tag.modulate = Color(1, 0.9, 0.3) if is_you else Color(1, 1, 1)
	_tag.visible = false # names are drawn by the 2D HUD (≤ 4 nearest); kept for spectator/debug use


## Uses the Blender model (art/blender/cars/<id>.py → assets/cars/<id>.glb) when present;
## the placeholder boxes stay as a fallback.
func _load_model(vehicle: String) -> void:
	var path: String = "res://assets/cars/%s.glb" % vehicle
	if _model != null or not ResourceLoader.exists(path):
		return
	_model = (load(path) as PackedScene).instantiate() as Node3D
	add_child(_model)
	_model.position.y = -RIDE_HEIGHT
	_body.visible = false
	_cabin.visible = false
	# A1 models carry their own PBR materials (paint, glass, chrome, lights): keep them, and give
	# this car its own copy of "Paint" so effect visuals (ghost, boost glow) don't leak to others.
	for mi: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i: int in m.mesh.get_surface_count():
			var mat: Material = m.mesh.surface_get_material(i)
			if mat != null and mat.resource_name == "Body": # boxy cars (boxkit): one matte surface per car
				if _body_mat == null:
					_body_mat = ShaderMaterial.new()
					_body_mat.shader = preload("res://src/render/car_body.gdshader")
					_ghost_mat = ShaderMaterial.new()
					_ghost_mat.shader = preload("res://src/render/car_body_ghost.gdshader")
				m.set_surface_override_material(i, _body_mat)
				_body_surfaces.append([m, i])
			elif mat != null and mat.resource_name in ["Detail", "Lamp", "GlassClear"]:
				m.set_surface_override_material(i, _shared(mat.resource_name))
			elif mat != null and mat.resource_name == "Paint" and mat is StandardMaterial3D:
				if _paint == null:
					_paint = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.set_surface_override_material(i, _paint)
	for mi: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		if m.name.ends_with("_lod1"):
			_lod1.append(m)
		else:
			_lod0.append(m)
		if m.name.begins_with("Wheel_"):
			_wheels.append(m)
			_rest[m] = m.basis
			if m.name.contains("FL") or m.name.contains("FR"):
				_front.append(m)
			_wheel_r = maxf(_wheel_r, m.get_aabb().size.y / 2.0)
	_apply_lod(0 if not _lod1.is_empty() and (force_lod0 or _quality_tier() != "low") else 1)


var _paint: StandardMaterial3D = null

## Mid-poly cars (A1 v4) ship two detail levels: LOD0 (25–50 k tris) and LOD1 (≈ 5 k,
## nodes named *_lod1). Near cars and your own car use LOD0; LOD1 always draws the shadow
## (cheap). Switching uses hysteresis so a car at the boundary never flips every frame.
const LOD0_UNTIL: float = 26.0 # m: switch to LOD1 beyond this …
const LOD1_UNTIL: float = 20.0 # … and back to LOD0 only nearer than this
var force_lod0: bool = false # own car, showroom
var _lod0: Array[MeshInstance3D] = []
var _lod1: Array[MeshInstance3D] = []
var _lod: int = -1


func _apply_lod(level: int) -> void:
	if level == _lod or _lod1.is_empty():
		return
	_lod = level
	for m: MeshInstance3D in _lod0:
		m.visible = level == 0
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for m: MeshInstance3D in _lod1:
		m.visible = true
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if level == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func _quality_tier() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root.has_node("Quality"):
		return str(tree.root.get_node("Quality").get("tier"))
	return "high"


## Picks LOD0/LOD1 from the distance to the active camera (low tier: LOD1 unless forced).
func _update_lod() -> void:
	if _lod1.is_empty():
		return
	if force_lod0:
		_apply_lod(0)
		return
	if _quality_tier() == "low":
		_apply_lod(1)
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var dist: float = cam.global_position.distance_to(global_position)
	if _lod == 0 and dist > LOD0_UNTIL:
		_apply_lod(1)
	elif _lod == 1 and dist < LOD1_UNTIL:
		_apply_lod(0)
var _body_mat: ShaderMaterial = null # boxy cars: this car's body material (effects stay per car)
var _ghost_mat: ShaderMaterial = null
var _body_surfaces: Array = [] # [MeshInstance3D, surface index]
var _ghosted: bool = false

static var _shared_mats: Dictionary = {}


## One Detail (vertex-coloured trim/chrome/rubber) and one Lamp (emissive vertex colour) material
## shared by all cars: fewer state changes, consistent look.
static func _shared(kind: String) -> Material:
	if not _shared_mats.has(kind):
		if kind == "GlassClear": # see-through cabin glass with Fresnel (car_glass.gdshader)
			var gm: ShaderMaterial = ShaderMaterial.new()
			gm.shader = preload("res://src/render/car_glass.gdshader")
			_shared_mats[kind] = gm
		elif kind == "Lamp":
			var m: StandardMaterial3D = StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # lamps read as glowing
			_shared_mats[kind] = m
		else: # metallic/roughness per part come from the vertex alpha (car_detail.gdshader)
			var sm: ShaderMaterial = ShaderMaterial.new()
			sm.shader = preload("res://src/render/car_detail.gdshader")
			_shared_mats[kind] = sm
	return _shared_mats[kind] as Material


## Places the car from a track-space state (rendering only; no game rules).
func show_state(st: Physics.CarState, tr: Track) -> void:
	_animate_wheels(st, tr)
	_update_lod()
	var smp: Track.Sample = tr.at(st.s)
	var grounded: bool = st.y <= 0.0 and st.vy <= 0.0
	var ramp: float = tr.ramp_height(st.s) if grounded else 0.0 # drive up the wedge, not through it
	var p: Vector3 = tr.world(st.s, st.d, st.y + ramp + RIDE_HEIGHT)
	var cy: float = cos(st.yaw_rel)
	var sy: float = sin(st.yaw_rel)
	var pitch: float = tr.ramp_slope(st.s) if grounded else 0.0
	var fwd: Vector3 = Vector3(smp.tx * cy + smp.nx * sy, smp.ty + pitch, smp.tz * cy + smp.nz * sy).normalized()
	var up: Vector3 = tr.lateral(st.s).cross(fwd).normalized()
	if up.y < 0.0:
		up = -up
	transform = Transform3D(Basis.looking_at(fwd, up), p)


var _spin: float = 0.0
var _flash_t: float = 0.0


## Effect visuals from the server flags (placeholder until M8 VFX): spin-out spins the body,
## ghost is translucent, boost/slow tint.
func show_effects(flags: int, delta: float) -> void:
	if flags & Protocol.EFF_SPINOUT:
		_spin += delta * TAU * 2.0
	else:
		_spin = 0.0
	_body.rotation.y = _spin
	_cabin.rotation.y = _spin
	if _model != null:
		_model.rotation.y = _spin
	var ghost: bool = (flags & Protocol.EFF_GHOST) != 0
	_flash_t = maxf(_flash_t - delta, 0.0) if _body_mat != null else _flash_t
	if _body_mat != null:
		if ghost != _ghosted:
			_ghosted = ghost
			for e: Array in _body_surfaces:
				(e[0] as MeshInstance3D).set_surface_override_material(int(e[1]), _ghost_mat if ghost else _body_mat)
		var g: float = _flash_t * 3.0
		if flags & Protocol.EFF_BOOST:
			g = maxf(g, 0.6)
		var gc: Color = Color(1.0, 0.7, 0.2) * g
		_body_mat.set_shader_parameter("glow", gc)
		_ghost_mat.set_shader_parameter("glow", gc)
		return
	var mat: StandardMaterial3D = _paint if _paint != null else _body.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if ghost else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color.a = 0.35 if ghost else 1.0
	_flash_t = maxf(_flash_t - delta, 0.0)
	var glow: float = _flash_t * 3.0
	if flags & Protocol.EFF_BOOST:
		glow = maxf(glow, 0.6)
	mat.emission_enabled = glow > 0.0
	mat.emission = Color(1.0, 0.7, 0.2) * glow


func flash() -> void:
	_flash_t = 0.4


## Cosmetic only: wheels roll with distance travelled, front wheels show the steering.
var _roll: float = 0.0
var _pitch: float = 0.0
var _last_speed: float = 0.0
var _last_y: float = 0.0


## Cosmetic suspension (client only): body rolls into turns, pitches on speed changes,
## squashes on landing.
func _suspension(st: Physics.CarState) -> void:
	if _model == null:
		return
	var turn: float = clampf((st.yaw_rel - _last_yaw) * 30.0, -1.0, 1.0)
	_roll = lerpf(_roll, -turn * 0.06, 0.15)
	_pitch = lerpf(_pitch, clampf((st.speed - _last_speed) * 0.02, -0.05, 0.05), 0.2)
	var squash: float = 0.0
	if _last_y > 0.3 and st.y <= 0.01:
		squash = 0.12
	_model.rotation = Vector3(_pitch, _model.rotation.y, _roll)
	_model.scale = _model.scale.lerp(Vector3(1.0 + squash * 0.5, 1.0 - squash, 1.0 + squash * 0.5), 0.5).lerp(Vector3.ONE, 0.15)
	_last_speed = st.speed
	_last_y = st.y


func _animate_wheels(st: Physics.CarState, tr: Track) -> void:
	_suspension(st)
	if _wheels.is_empty():
		return
	var ds: float = 0.0 if _last_s < 0.0 else MathX.wrap_delta(_last_s, st.s, tr.length)
	_last_s = st.s
	# Rebuild each wheel from clean angles in car space (no accumulated local rotations):
	# spin around the axle (car X), steering around the vertical axis (front wheels only).
	# Visual spin per frame is capped: at race speed the true rate (2+ rad/frame) aliases with the
	# spoke pattern (wagon-wheel strobing reads as flicker); below half a spoke gap it reads as fast.
	_wheel_spin = fmod(_wheel_spin - clampf(ds / _wheel_r, -MAX_SPIN_STEP, MAX_SPIN_STEP), TAU)
	var target_steer: float = clampf((st.yaw_rel - _last_yaw) * 8.0, -0.45, 0.45)
	_steer = lerpf(_steer, target_steer, 0.3)
	_last_yaw = st.yaw_rel
	var spin: Basis = Basis(Vector3.RIGHT, _wheel_spin)
	for w: Node3D in _wheels:
		var b: Basis = spin * (_rest[w] as Basis)
		if _front.has(w):
			b = Basis(Vector3.UP, _steer) * b
		w.basis = b