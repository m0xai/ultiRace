class_name CarView
extends Node3D

## One car's visual (GAME_PLAN §4.4). The same scene serves all 8 vehicles; configure() sets
## colour and name from vehicles.json. Placeholder body until the M8 Blender cars.

const RIDE_HEIGHT: float = 0.55

@onready var _body: MeshInstance3D = $Body
@onready var _cabin: MeshInstance3D = $Cabin
@onready var _tag: Label3D = $Tag

var vehicle_id: String = ""


func configure(vehicle: String, display_name: String, is_you: bool) -> void:
	vehicle_id = vehicle
	var v: Dictionary = GameData.vehicle(vehicle)
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


## Places the car from a track-space state (rendering only; no game rules).
func show_state(st: Physics.CarState, tr: Track) -> void:
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
	var mat: StandardMaterial3D = _body.material_override as StandardMaterial3D
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
