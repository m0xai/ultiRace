extends Node3D

## M4 "connect & watch": joins a room, renders all cars interpolated from snapshots
## (no prediction yet) with a chase camera. Crude input until M5's touch controls:
## throttle always on, steer with ←/→ or by touching the left/right half of the screen.
## User args: --server <url>  --mode practice|quick  --laps 2|3  (+ DevTools --shot)

const INPUT_HZ: float = 30.0
const CAM_BACK: float = 7.0
const CAM_UP: float = 2.8

var _conn: Connection
var _track: Track = null
var _track_node: Node3D = null
var _interp: Interpolation = null
var _cars: Array[CarView] = []
var _grid: Array = []
var _you: int = -1
var _follow: int = 0
var _state: String = "CONNECTING"
var _seq: int = 0
var _input_t: float = 0.0
var _steer_touch: int = 0
var _locked: bool = false
var _set_laps: bool = false
var _laps: int = 2
var _results: String = ""
var _snap_count: int = 0

@onready var _cam: Camera3D = $Camera3D
@onready var _hud: Label = $HUD/Info
@onready var _big: Label = $HUD/Big


func _ready() -> void:
	_laps = int(Config.arg("--laps", "2"))
	_conn = Connection.new()
	add_child(_conn)
	_conn.message.connect(_on_message)
	_conn.snapshot.connect(_on_snapshot)
	_conn.closed.connect(func(code: int, reason: String) -> void: _state = "DISCONNECTED (%d %s)" % [code, reason])
	var mode: String = Config.arg("--mode", "practice")
	var opts: Dictionary = {"practice": mode == "practice", "quick": mode == "quick"}
	var err: Error = _conn.connect_to(Config.server_url(), Protocol.hello("Watcher", opts))
	if err != OK:
		_state = "CONNECT FAILED %d" % err


func _on_message(m: Dictionary) -> void:
	match m["t"] as String:
		Protocol.T_ROOM:
			_on_room(m)
		Protocol.T_SELECT:
			_on_select(m)
		Protocol.T_RACE_START:
			_on_race_start(m)
		Protocol.T_EV:
			if m.get("kind", "") == "state":
				_state = m.get("state", _state) as String
		Protocol.T_RESULTS:
			_on_results(m)
		Protocol.T_ERR:
			print("server error: ", m)


func _on_room(m: Dictionary) -> void:
	_state = m["state"] as String
	if _state != "LOBBY":
		return
	_locked = false
	var me: Dictionary = {}
	for p: Variant in m["players"] as Array:
		var pd: Dictionary = p as Dictionary
		if pd["id"] == _conn.player_id:
			me = pd
	if me.is_empty():
		return
	if me.get("host", false) and not _set_laps:
		_set_laps = true
		_conn.send(Protocol.settings(m["map"] as String, _laps, true, m["visibility"] as String))
	if not me.get("ready", false):
		_conn.send(Protocol.ready(true))
	elif me.get("host", false) and m["visibility"] == Protocol.PRIVATE:
		_conn.send(Protocol.start())


func _on_select(m: Dictionary) -> void:
	if _locked:
		return
	var taken: Dictionary = {}
	for c: Variant in m["claims"] as Array:
		taken[(c as Dictionary)["vehicle"]] = true
	for v: Variant in GameData.vehicles():
		var vid: String = (v as Dictionary)["id"] as String
		if not taken.has(vid):
			_conn.send(Protocol.lock(vid))
			_locked = true
			return


func _on_race_start(m: Dictionary) -> void:
	_results = ""
	_you = int(m["you"])
	_follow = max(_you, 0)
	_grid = m["grid"] as Array
	if _track == null or _track.id != m["map"]:
		if _track_node != null:
			_track_node.queue_free()
		_track = Track.load_map(m["map"] as String)
		_track_node = TrackBuilder.build(_track)
		add_child(_track_node)
	for c: CarView in _cars:
		c.queue_free()
	_cars.clear()
	var scene: PackedScene = load("res://src/render/CarView.tscn") as PackedScene
	for slot: Variant in _grid:
		var sd: Dictionary = slot as Dictionary
		var cv: CarView = scene.instantiate() as CarView
		add_child(cv)
		cv.configure(sd["vehicle"] as String, sd["name"] as String, int(sd["car"]) == _you)
		_cars.append(cv)
	_interp = Interpolation.new(_track.length)
	_state = "COUNTDOWN"


func _on_snapshot(snap: Protocol.Snapshot) -> void:
	_snap_count += 1
	if _interp != null:
		_interp.push(snap, float(Time.get_ticks_msec()))


func _on_results(m: Dictionary) -> void:
	var lines: PackedStringArray = []
	for r: Variant in m["rows"] as Array:
		var rd: Dictionary = r as Dictionary
		var t: String = ("%.2fs" % (float(rd["timeMs"]) / 1000.0)) if rd["finished"] else "DNF"
		lines.append("%d. %s (%s) %s" % [int(rd["pos"]), rd["name"], rd["vehicle"], t])
	_results = "\n".join(lines)
	print("RESULTS\n", _results)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		if t.pressed:
			_steer_touch = -1 if t.position.x < get_viewport().get_visible_rect().size.x / 2.0 else 1
		else:
			_steer_touch = 0
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_TAB:
		_follow = (_follow + 1) % max(_cars.size(), 1)


func _process(delta: float) -> void:
	_send_input(delta)
	if _interp != null and _track != null:
		_interp.advance(delta)
		for i: int in _cars.size():
			var st: Physics.CarState = _interp.sample(i)
			if st != null:
				_cars[i].show_state(st, _track)
		_update_camera(delta)
	_update_hud()


func _send_input(delta: float) -> void:
	if _you < 0 or _state != "RACING":
		return
	_input_t += delta
	if _input_t < 1.0 / INPUT_HZ:
		return
	_input_t = 0.0
	var steer: int = _steer_touch
	if Input.is_key_pressed(KEY_LEFT):
		steer = -1
	elif Input.is_key_pressed(KEY_RIGHT):
		steer = 1
	_seq += 1
	_conn.send(Protocol.input(_seq, steer, 1, false))


func _update_camera(delta: float) -> void:
	if _follow >= _cars.size():
		return
	var car: CarView = _cars[_follow]
	var fwd: Vector3 = -car.global_transform.basis.z
	var want: Vector3 = car.global_position - fwd * CAM_BACK + Vector3.UP * CAM_UP
	var k: float = 1.0 - exp(-delta * 6.0)
	_cam.global_position = _cam.global_position.lerp(want, k) if _cam.global_position.distance_to(want) < 40.0 else want
	_cam.look_at(car.global_position + fwd * 6.0 + Vector3.UP * 0.8, Vector3.UP)


func _update_hud() -> void:
	var lap: String = ""
	if _interp != null and _you >= 0:
		var st: Physics.CarState = _interp.sample(_you)
		if st != null:
			lap = "  lap %d/%d" % [clampi(st.lap + 1, 1, _laps), _laps]
	var delay: String = ("  buffer %d ms" % int(_interp.delay_ms)) if _interp != null else ""
	_hud.text = "%s  room %s  ping %d ms%s%s  snaps %d" % [_state, _conn.room_code, _conn.ping_ms, lap, delay, _snap_count]
	_big.text = _results if _results != "" else ("GET READY" if _state == "COUNTDOWN" else "")
