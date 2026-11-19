class_name CarView
extends Node3D

## One car's visual (GAME_PLAN §4.4). The same scene serves all 8 vehicles; configure() sets
## colour and name from vehicles.json. Placeholder body until the M8 Blender cars.

const RIDE_HEIGHT: float = 0.55

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
			if mat != null and mat.resource_name in ["Detail", "Lamp"]:
				m.set_surface_override_material(i, _shared(mat.resource_name))
			elif mat != null and mat.resource_name == "Paint" and mat is StandardMaterial3D:
				if _paint == null:
					_paint = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.set_surface_override_material(i, _paint)
	for mi: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		if m.name.begins_with("Wheel_"):
			_wheels.append(m)
			_rest[m] = m.basis
			if m.name.ends_with("FL") or m.name.ends_with("FR"):
				_front.append(m)
			_wheel_r = maxf(_wheel_r, m.get_aabb().size.y / 2.0)


var _paint: StandardMaterial3D = null

static var _shared_mats: Dictionary = {}


## One Detail (vertex-coloured trim/chrome/rubber) and one Lamp (emissive vertex colour) material
## shared by all cars: fewer state changes, consistent look.
static func _shared(kind: String) -> StandardMaterial3D:
	if not _shared_mats.has(kind):
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		if kind == "Lamp":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # lamps read as glowing
		else:
			m.metallic = 0.25
			m.roughness = 0.45
		_shared_mats[kind] = m
	return _shared_mats[kind] as StandardMaterial3D


## Places the car from a track-space state (rendering only; no game rules).
func show_state(st: Physics.CarState, tr: Track) -> void:
	_animate_wheels(st, tr)
	var smp: Track.Sample = tr.at(st.s)
	var p: Vector3 = tr.world(st.s, st.d, st.y + RIDE_HEIGHT)
	var cy: float = cos(st.yaw_rel)
	var sy: float = sin(st.yaw_rel)
	var fwd: Vector3 = Vector3(smp.tx * cy + smp.nx * sy, smp.ty, smp.tz * cy + smp.nz * sy).normalized()
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
	var mat: StandardMaterial3D = _paint if _paint != null else _body.material_override as StandardMaterial3D
	if mat == null:
		return
	var ghost: bool = (flags & Protocol.EFF_GHOST) != 0
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
	_wheel_spin = fmod(_wheel_spin - clampf(ds, -5.0, 5.0) / _wheel_r, TAU)
	var target_steer: float = clampf((st.yaw_rel - _last_yaw) * 8.0, -0.45, 0.45)
	_steer = lerpf(_steer, target_steer, 0.3)
	_last_yaw = st.yaw_rel
	var spin: Basis = Basis(Vector3.RIGHT, _wheel_spin)
	for w: Node3D in _wheels:
		var b: Basis = spin * (_rest[w] as Basis)
		if _front.has(w):
			b = Basis(Vector3.UP, _steer) * b
		w.basis = b