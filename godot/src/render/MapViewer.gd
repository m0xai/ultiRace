extends Node3D

## M3 map viewer: builds a map from JSON and flies a free camera.
## Desktop: WASD/QE move, right mouse look, Shift fast, 1/2/3 switch map.
## Touch: one finger looks, two fingers move forward/back.
## User args (after `--`): --map <id>  --cam overview|start|bridge  --at <s>  (+ DevTools --shot <png>)

const SPEED: float = 40.0
const LOOK_SENS: float = 0.004

var _track_node: Node3D = null
var _track: Track = null
var _yaw: float = 0.0
var _pitch: float = -0.3
var _looking: bool = false
var _touches: Dictionary = {}

@onready var _cam: Camera3D = $Camera3D
@onready var _label: Label = $HUD/Label


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var map_id: String = _arg(args, "--map", "sunny")
	_load_map(map_id)
	_set_cam(_arg(args, "--cam", "start"))
	_place_grid_cars()


func _arg(args: PackedStringArray, key: String, def: String) -> String:
	var i: int = args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def


func _load_map(map_id: String) -> void:
	if _track_node != null:
		_track_node.queue_free()
	_track = Track.load_map(map_id)
	_track_node = TrackBuilder.build(_track)
	add_child(_track_node)
	_label.text = "%s — %.0f m — WASD/QE, right-drag look, 1/2/3 maps" % [_track.display_name, _track.length]


func _set_cam(mode: String) -> void:
	match mode:
		"overview":
			var c: Vector3 = Vector3.ZERO
			var n: int = 64
			for i: int in n:
				c += _track.world(_track.length * float(i) / float(n), 0.0, 0.0)
			c /= float(n)
			var radius: float = 0.0
			for i: int in n:
				radius = maxf(radius, c.distance_to(_track.world(_track.length * float(i) / float(n), 0.0, 0.0)))
			_cam.position = c + Vector3(0, radius * 0.85, radius * 0.75)
			_cam.far = 4000.0
			_cam.look_at(c, Vector3.UP)
		"bridge":
			var s_hi: float = 0.0
			var best_y: float = -INF
			var i: int = 0
			while i < 400:
				var s: float = _track.length * float(i) / 400.0
				var y: float = _track.at(s).py
				if y > best_y:
					best_y = y
					s_hi = s
				i += 1
			var p: Vector3 = _track.world(s_hi, 0.0, 0.0)
			var lat: Vector3 = _track.lateral(s_hi)
			_cam.position = p + lat * 45.0 + Vector3(0, -6, 0)
			_cam.look_at(p + Vector3(0, -3, 0), Vector3.UP)
		_:
			# --at <s>: chase-camera view of that point (hazards, ramps); default: the start line
			var at: float = float(_arg(OS.get_cmdline_user_args(), "--at", "0"))
			var near: bool = OS.get_cmdline_user_args().has("--near") # race-camera distance (art reviews)
			var behind: Vector3 = _track.world(at - (12.0 if near else 30.0), 0.0, 2.8 if near else 6.0)
			var ahead: Vector3 = _track.world(at + (12.0 if near else 25.0), 0.0, 0.6 if near else 1.0)
			_cam.position = behind
			_cam.look_at(ahead, Vector3.UP)
	_yaw = _cam.rotation.y
	_pitch = _cam.rotation.x


## Placeholder cars (vehicle colours) on the grid for scale until CarView exists (M4/M8).
func _place_grid_cars() -> void:
	var bal: Dictionary = GameData.balance()
	var race: Dictionary = bal["race"] as Dictionary
	var vs: Array = GameData.vehicles()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(2.0, 1.1, 3.6)
	for i: int in vs.size():
		var row: int = i / 2
		var col: int = i % 2
		var s: float = _track.length - float(race["gridStartGap"]) - float(row) * float(race["gridRowSpacing"]) - float(col) * float(race["gridRowSpacing"]) / 2.0
		var d: float = -float(race["gridColumnOffset"]) if col == 0 else float(race["gridColumnOffset"])
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = box
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color.html((vs[i] as Dictionary)["color"] as String)
		mi.material_override = mat
		var p: Vector3 = _track.world(s, d, 0.6)
		var fwd: Vector3 = _track.world(s + 1.0, d, 0.6) - p
		mi.transform = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), p)
		_track_node.add_child(mi)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
	elif event is InputEventMouseMotion and _looking:
		_rotate_cam((event as InputEventMouseMotion).relative)
	elif event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
	elif event is InputEventScreenDrag:
		var dr: InputEventScreenDrag = event as InputEventScreenDrag
		if _touches.size() == 1:
			_rotate_cam(dr.relative)
		elif _touches.size() >= 2:
			_cam.position += -_cam.global_transform.basis.z * (-dr.relative.y * 0.3)
		_touches[dr.index] = dr.position
	elif event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_1:
				_load_map("sunny")
				_place_grid_cars()
			KEY_2:
				_load_map("neon")
				_place_grid_cars()
			KEY_3:
				_load_map("frosty")
				_place_grid_cars()


func _rotate_cam(rel: Vector2) -> void:
	_yaw -= rel.x * LOOK_SENS
	_pitch = clampf(_pitch - rel.y * LOOK_SENS, -1.5, 1.5)
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	var dir: Vector3 = Vector3.ZERO
	var b: Basis = _cam.global_transform.basis
	if Input.is_key_pressed(KEY_W):
		dir -= b.z
	if Input.is_key_pressed(KEY_S):
		dir += b.z
	if Input.is_key_pressed(KEY_A):
		dir -= b.x
	if Input.is_key_pressed(KEY_D):
		dir += b.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	var speed: float = SPEED * (4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if dir != Vector3.ZERO:
		_cam.position += dir.normalized() * speed * delta
