class_name RaceView
extends Node3D

## The 3D race: track, all cars interpolated from snapshots (no prediction until M7), chase
## camera (GAME_PLAN §4.4). Pure presentation: positions, laps and ranking come from the server.

const CAM_BACK: float = 6.0
const CAM_UP: float = 2.6
const CAM_LOOK_AHEAD: float = 7.0

var track: Track = null
var interp: Interpolation = null
var cars: Array[CarView] = []
var grid: Array = []
var you: int = -1
var follow: int = 0
var go_tick: int = 0
var latest: Protocol.Snapshot = null

var _track_node: Node3D = null
var _cam: Camera3D
var _car_scene: PackedScene = preload("res://src/render/CarView.tscn")
var _states: Array[Physics.CarState] = []


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 3000.0
	add_child(_cam)
	_cam.current = true


func start_race(m: Dictionary) -> void:
	you = int(m["you"])
	follow = max(you, 0)
	grid = m["grid"] as Array
	go_tick = int(m["tick"])
	if track == null or track.id != m["map"]:
		if _track_node != null:
			_track_node.queue_free()
		track = Track.load_map(m["map"] as String)
		_track_node = TrackBuilder.build(track)
		add_child(_track_node)
	for c: CarView in cars:
		c.queue_free()
	cars.clear()
	_states.clear()
	for slot: Variant in grid:
		var sd: Dictionary = slot as Dictionary
		var cv: CarView = _car_scene.instantiate() as CarView
		add_child(cv)
		cv.configure(sd["vehicle"] as String, sd["name"] as String, int(sd["car"]) == you)
		cars.append(cv)
		_states.append(null)
	interp = Interpolation.new(track.length)
	latest = null


func clear() -> void:
	for c: CarView in cars:
		c.queue_free()
	cars.clear()
	_states.clear()
	interp = null
	latest = null


func push_snapshot(snap: Protocol.Snapshot) -> void:
	latest = snap
	if interp != null:
		interp.push(snap, float(Time.get_ticks_msec()))


## Interpolated state of car i this frame (null if unknown).
func state_of(i: int) -> Physics.CarState:
	return _states[i] if i >= 0 and i < _states.size() else null


## Server-side race position of car i from the latest snapshot (0 = unknown).
func position_of(i: int) -> int:
	if latest == null:
		return 0
	for c: Protocol.SnapCar in latest.cars:
		if c.id == i:
			return Protocol.pos_of(c.flags)
	return 0


func finished(i: int) -> bool:
	if latest == null:
		return false
	for c: Protocol.SnapCar in latest.cars:
		if c.id == i:
			return (c.flags & Protocol.FLAG_FINISHED) != 0
	return false


## Seconds since GO in server time (negative during the countdown).
func race_time() -> float:
	if interp == null or interp.render_tick < 0.0:
		return -999.0
	return (interp.render_tick - float(go_tick)) / Interpolation.TICK_RATE


func camera() -> Camera3D:
	return _cam


func _process(delta: float) -> void:
	if interp == null or track == null:
		return
	interp.advance(delta)
	for i: int in cars.size():
		var st: Physics.CarState = interp.sample(i)
		_states[i] = st
		if st != null:
			cars[i].show_state(st, track)
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	if follow >= cars.size() or _states[follow] == null:
		return
	var car: CarView = cars[follow]
	var fwd: Vector3 = -car.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var want: Vector3 = car.global_position - fwd * CAM_BACK + Vector3.UP * CAM_UP
	if _cam.global_position.distance_to(want) > 40.0:
		_cam.global_position = want
	else:
		_cam.global_position = _cam.global_position.lerp(want, 1.0 - exp(-delta * 8.0))
	_cam.look_at(car.global_position + fwd * CAM_LOOK_AHEAD + Vector3.UP * 0.6, Vector3.UP)
	var st: Physics.CarState = _states[follow]
	var target_fov: float = 70.0 + clampf((st.speed - 38.0) / 6.0, 0.0, 1.0) * 10.0 # FOV kick at high speed
	_cam.fov = lerpf(_cam.fov, target_fov, 1.0 - exp(-delta * 3.0))
