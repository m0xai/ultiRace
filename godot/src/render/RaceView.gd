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
var prediction: Prediction = null # own car (M7); other cars are interpolated
var vfx: Vfx
var reduce_motion: bool = false
var laps: int = 3
var _shake: float = 0.0
var _engines: Array[EngineSound] = []
var _smoothed: Dictionary = {} # car index → Physics.CarState shown last frame
var _last_count: int = 99

var _track_node: Node3D = null
var _cam: Camera3D
var _car_scene: PackedScene = preload("res://src/render/CarView.tscn")
var _states: Array[Physics.CarState] = []
var _cam_fwd: Vector3 = Vector3.ZERO
var _fov_speed: float = 0.0
# dev pacing trace (`--trace user://trace.txt` or env ULTI_TRACE=1 → stdout): per frame own car,
# one remote car and camera movement, plus snapshot arrival times
var _trace: bool = OS.get_environment("ULTI_TRACE") == "1" or Config.user_args().has("--trace")
var _trace_file: FileAccess = null
var _trace_last: Vector3 = Vector3.ZERO
var _trace_other: Vector3 = Vector3.ZERO
var _trace_cam: Vector3 = Vector3.ZERO


func _trace_line(line: String) -> void:
	if _trace_file == null and Config.arg("--trace", "") != "":
		_trace_file = FileAccess.open(Config.arg("--trace", ""), FileAccess.WRITE)
	if _trace_file != null:
		_trace_file.store_line(line)
		_trace_file.flush()
	else:
		print(line)


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 3000.0
	add_child(_cam)
	_cam.current = true
	vfx = Vfx.new()
	add_child(vfx)
	reduce_motion = bool(Profile.get_value("reduce_motion", false))


func start_race(m: Dictionary) -> void:
	_finish_cam = false
	laps = int(m.get("laps", 3))
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
	_engines.clear()
	for slot: Variant in grid:
		var sd: Dictionary = slot as Dictionary
		var cv: CarView = _car_scene.instantiate() as CarView
		add_child(cv)
		cv.configure(sd["vehicle"] as String, sd["name"] as String, int(sd["car"]) == you)
		cars.append(cv)
		_states.append(null)
		var es: EngineSound = EngineSound.new()
		cv.add_child(es)
		es.setup(sd["vehicle"] as String, int(sd["car"]) == you)
		_engines.append(es)
	interp = Interpolation.new(track.length)
	latest = null
	prediction = null
	_smoothed.clear()
	_last_count = 99
	if you >= 0:
		prediction = Prediction.new(track, (grid[you] as Dictionary)["vehicle"] as String)


func clear() -> void:
	for c: CarView in cars:
		c.queue_free()
	cars.clear()
	_states.clear()
	interp = null
	latest = null
	prediction = null


func push_snapshot(snap: Protocol.Snapshot) -> void:
	latest = snap
	if _trace:
		_trace_line("SNAP t=%d tick=%d ack=%d" % [Time.get_ticks_usec() / 1000, snap.tick, snap.ack])
	if interp != null:
		interp.push(snap, float(Time.get_ticks_msec()))
	if prediction != null and snap.tick > go_tick:
		for c: Protocol.SnapCar in snap.cars:
			if c.id == you:
				prediction.set_mods(snap.speed_mul, snap.accel_mul, snap.steer_mul)
				prediction.reconcile(c, snap.ack)


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


func flags_of(i: int) -> int:
	if latest == null:
		return 0
	for c: Protocol.SnapCar in latest.cars:
		if c.id == i:
			return c.flags
	return 0


## Brief light flash on a car that used its ULT (telegraph; real VFX in M8).
func flash(i: int) -> void:
	if i >= 0 and i < cars.size():
		cars[i].flash()


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
	var predicting: bool = prediction != null and prediction.started
	# Remote cars: with prediction on, show them at the predicted moment (dead reckoning +
	# smoothing) instead of ~100 ms in the past, so cars meet where the server says they meet.
	if predicting:
		_advance_remote_clock(delta)
	for i: int in cars.size():
		var st: Physics.CarState
		if i == you and predicting:
			st = prediction.visual(delta)
		elif predicting:
			st = _smooth_remote(i, interp.at_tick(i, _rtick, Interpolation.MAX_AHEAD_S * Interpolation.TICK_RATE), delta)
		else:
			st = interp.sample(i)
		_states[i] = st
		if st != null:
			cars[i].show_state(st, track)
			var fl: int = flags_of(i)
			cars[i].show_effects(fl, delta)
			vfx.car_trail(i, cars[i], (fl & Protocol.EFF_BOOST) != 0, (fl & Protocol.EFF_DRAFT) != 0)
	_update_hazards()
	_update_camera(delta)
	_update_audio()
	if _trace and you >= 0 and _states[you] != null:
		var p: Vector3 = cars[you].global_position
		var oi: int = (you + 1) % cars.size()
		var o: Vector3 = cars[oi].global_position
		var ost: Physics.CarState = _states[oi]
		_trace_line("F t=%d dt=%.2f me=%.3f exp=%.3f other=%.3f oexp=%.3f cam=%.3f fov=%.2f err=%.2f pend=%d" % [
			Time.get_ticks_usec() / 1000, delta * 1000.0, p.distance_to(_trace_last), _states[you].speed * delta,
			o.distance_to(_trace_other), (ost.speed * delta) if ost != null else 0.0,
			_cam.global_position.distance_to(_trace_cam), _cam.fov,
			prediction.last_error if prediction != null else 0.0, prediction.pending_inputs() if prediction != null else 0])
		_trace_last = p
		_trace_other = o
		_trace_cam = _cam.global_position


## Remote-car display clock (server ticks): the moment the predicted own car is at (newest
## snapshot tick + unacknowledged inputs + blend phase − 1). That target steps with every input
## tick and snapshot (integer input counts, arrival jitter), so the clock runs at exactly 30 ticks/s
## and is only steered toward it gently; sampling remote cars at a steady clock is what keeps
## them from skipping (the old per-frame horizon jumped ±1 tick = ±1.3 m at speed).
var _rtick: float = -1.0
const REMOTE_SMOOTH_S: float = 0.25 # corrections when a (bursty) snapshot lands blend over ~¼ s


func _advance_remote_clock(delta: float) -> void:
	var target: float = float(interp.latest_tick()) + float(prediction.pending_inputs()) + maxf(prediction.phase, 0.0) - 1.0
	if _rtick < 0.0 or absf(target - _rtick) > 8.0:
		_rtick = target
	else:
		_rtick += delta * Interpolation.TICK_RATE
		_rtick += (target - _rtick) * (1.0 - exp(-delta / 0.4))


## Keeps remote cars moving at their speed every frame and blends toward the newest estimate,
## so a new snapshot never makes them jump (no visual stutter/flicker).
func _smooth_remote(i: int, target: Physics.CarState, delta: float) -> Physics.CarState:
	if target == null:
		return null
	var prev: Physics.CarState = _smoothed.get(i, null) as Physics.CarState
	if prev == null:
		_smoothed[i] = target
		return target
	var L: float = track.length
	var prev_prog: float = float(prev.lap) * L + prev.s + prev.speed * cos(prev.yaw_rel) * delta
	var tgt_prog: float = float(target.lap) * L + target.s
	if absf(tgt_prog - prev_prog) > 15.0: # far off (respawn, big correction): snap
		_smoothed[i] = target
		return target
	var k: float = 1.0 - exp(-delta / REMOTE_SMOOTH_S)
	var out: Physics.CarState = target.copy()
	var prog: float = lerpf(prev_prog, tgt_prog, k)
	out.lap = int(floorf(prog / L))
	out.s = prog - float(out.lap) * L
	out.d = lerpf(prev.d, target.d, k)
	out.yaw_rel = lerpf(prev.yaw_rel, target.yaw_rel, k)
	out.y = lerpf(prev.y, target.y, k)
	_smoothed[i] = out
	return out


## Engines (own + 4 nearest audible) and countdown beeps.
func _update_audio() -> void:
	var dists: Array = []
	for i: int in cars.size():
		if _states[i] != null:
			dists.append([_cam.global_position.distance_to(cars[i].global_position), i])
	dists.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var audible: Dictionary = {}
	for k: int in mini(5, dists.size()):
		audible[int(dists[k][1])] = true
	for i: int in _engines.size():
		_engines[i].audible = i == you or audible.has(i)
		if _states[i] != null:
			_engines[i].update(_states[i].speed)
	var t: float = race_time()
	if t > -4.0 and t < 0.0:
		var c: int = int(ceil(-t))
		if c < _last_count:
			_last_count = c
			AudioDirector.sfx("countdown")
			Haptics.tap_light()
	elif t >= 0.0 and _last_count > 0 and _last_count < 99:
		_last_count = 0
		AudioDirector.sfx("go")
		Haptics.tap_heavy()


var _hazards: Array[MeshInstance3D] = []


## Traps and projectiles from the latest snapshot (placeholder visuals until M8).
func _update_hazards() -> void:
	var things: Array = []
	if latest != null:
		for t: Protocol.SnapThing in latest.traps:
			things.append(t)
		for p: Protocol.SnapThing in latest.proj:
			things.append(p)
	while _hazards.size() < things.size():
		var mi: MeshInstance3D = MeshInstance3D.new()
		add_child(mi)
		_hazards.append(mi)
	for i: int in _hazards.size():
		var mi: MeshInstance3D = _hazards[i]
		mi.visible = i < things.size()
		if not mi.visible:
			continue
		var th: Protocol.SnapThing = things[i] as Protocol.SnapThing
		var is_proj: bool = i >= latest.traps.size()
		var s_mid: float = th.s + th.length / 2.0
		var key: String = "proj" if is_proj else ("ice" if th.kind == Protocol.TRAP_ICE else "goo")
		if mi.get_meta("kind", "") != key:
			mi.set_meta("kind", key)
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			if is_proj:
				var cyl: CylinderMesh = CylinderMesh.new()
				cyl.top_radius = 1.6
				cyl.bottom_radius = 0.3
				cyl.height = 4.0
				mi.mesh = cyl
				mat.albedo_color = Color(0.75, 0.9, 0.9, 0.7)
			else:
				var box: BoxMesh = BoxMesh.new()
				box.size = Vector3(6.0 if key == "ice" else 10.0, 0.06, th.length)
				mi.mesh = box
				mat.albedo_color = Color(0.7, 0.9, 1.0, 0.75) if key == "ice" else Color(0.55, 0.85, 0.15, 0.85)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.material_override = mat
		var p: Vector3 = track.world(s_mid if not is_proj else th.s, th.d, 2.0 if is_proj else 0.08)
		var fwd: Vector3 = (track.world(s_mid + 1.0, th.d, 0.0) - track.world(s_mid, th.d, 0.0)).normalized()
		mi.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), p)
		if is_proj:
			mi.rotate_object_local(Vector3.UP, float(Time.get_ticks_msec()) * 0.02)


## Server event → effect (cosmetic only).
func on_event(m: Dictionary) -> void:
	var kind: String = str(m.get("kind", ""))
	var car: int = int(m.get("car", -1))
	if car < 0 or car >= cars.size():
		return
	match kind:
		"wallHit":
			vfx.sparks(cars[car].global_position + Vector3.UP * 0.5)
			if car == follow:
				shake(clampf(float(m.get("value", 5.0)) / 20.0, 0.1, 0.6))
				AudioDirector.sfx("wall", -4.0)
				Haptics.wall(float(m.get("value", 5.0)))
		"hazard":
			if car == you:
				AudioDirector.sfx("ice" if str(m.get("ult", "")) == "ice" else "splat", -6.0)
				Haptics.tap_light()
				if car == follow:
					shake(0.15)
		"lap":
			if car == you:
				AudioDirector.sfx("lap")
				if int(m.get("value", 0)) == laps - 1 and track != null:
					AudioDirector.play_music(track.theme + "_final") # faster climax mix
		"finished":
			if car == you:
				AudioDirector.sfx("finish")
				start_finish_camera()
		"startBoost":
			if car == you:
				AudioDirector.sfx("start_boost")
				Haptics.double_tap()
		"abilityUsed":
			var ult_sfx: Dictionary = {"nitro": "boost", "ram": "boost", "ice": "ice", "emp": "emp", "grapple": "grapple", "goo": "splat", "phase": "phase", "tornado": "tornado"}
			var near: bool = cars[car].global_position.distance_to(_cam.global_position) < 80.0
			if car == you or near:
				AudioDirector.sfx(str(ult_sfx.get(str(m.get("ult", "")), "boost")), 0.0 if car == you else -8.0)
			match str(m.get("ult", "")):
				"emp":
					vfx.ring(cars[car].global_position, float(GameData.balance()["ults"]["emp"]["radiusM"]), Color(0.7, 0.4, 1.0, 0.8))
				"phase":
					vfx.ring(cars[car].global_position, 4.0, Color(0.9, 0.95, 1.0, 0.8))
				"nitro":
					vfx.ring(cars[car].global_position, 3.0, Color(1.0, 0.6, 0.1, 0.8))
		"hit":
			var src: int = int(m.get("other", -1))
			if str(m.get("ult", "")) == "grapple" and src >= 0 and src < cars.size():
				vfx.cable(cars[src], cars[car], 0.8)
			if car == follow:
				shake(0.6)
			if car == you:
				var hard: bool = str(m.get("ult", "")) in ["ram", "tornado"]
				AudioDirector.sfx("spinout" if hard else "splat", -2.0)
				if hard:
					Haptics.hard_cc()


func shake(amount: float) -> void:
	if not reduce_motion:
		_shake = maxf(_shake, amount)


## After the own car crosses the finish line: the chase camera eases into a slow orbit around
## it while the results come in (the car keeps cruising, as finished cars do on the server).
var _finish_cam: bool = false
var _orbit_a: float = 0.0
var _orbit_blend: float = 0.0
var _orbit_last: Vector3 = Vector3.ZERO # car position last frame (the camera rides along with it)
const ORBIT_RADIUS: float = 7.5
const ORBIT_HEIGHT: float = 2.4
const ORBIT_SPEED: float = 0.32 # rad/s


func start_finish_camera() -> void:
	if _finish_cam or you < 0 or you >= cars.size():
		return
	_finish_cam = true
	_orbit_blend = 0.0
	follow = you
	# start the orbit from where the chase camera is (no jump)
	var off: Vector3 = _cam.global_position - cars[you].global_position
	_orbit_a = atan2(off.z, off.x)
	_orbit_last = cars[you].global_position


func finish_camera_active() -> bool:
	return _finish_cam


func _update_finish_camera(delta: float) -> void:
	var car: CarView = cars[follow]
	# ride along with the (still cruising) car, then ease only the orbit offset: no lag at speed
	_cam.global_position += car.global_position - _orbit_last
	_orbit_last = car.global_position
	_orbit_a += ORBIT_SPEED * delta
	_orbit_blend = minf(_orbit_blend + delta * 0.6, 1.0)
	var target: Vector3 = car.global_position + Vector3(cos(_orbit_a) * ORBIT_RADIUS, ORBIT_HEIGHT, sin(_orbit_a) * ORBIT_RADIUS)
	var k: float = 1.0 - exp(-delta * (2.0 + 6.0 * _orbit_blend))
	_cam.global_position = _cam.global_position.lerp(target, k)
	# aim a little to the right of the car: it sits in the left half, beside the results panel
	_cam.look_at(car.global_position + Vector3.UP * 0.7 + _cam.global_basis.x * 2.6 * _orbit_blend, Vector3.UP)
	_cam.fov = lerpf(_cam.fov, 50.0, 1.0 - exp(-delta * 1.5))


func _update_camera(delta: float) -> void:
	if follow >= cars.size() or _states[follow] == null:
		return
	if _finish_cam:
		_update_finish_camera(delta)
		return
	var car: CarView = cars[follow]
	var raw: Vector3 = -car.global_transform.basis.z
	raw.y = 0.0
	raw = raw.normalized()
	# smoothed heading: steering wiggles and bump yaw no longer swing the whole view
	if _cam_fwd == Vector3.ZERO or _cam_fwd.dot(raw) < 0.0:
		_cam_fwd = raw
	_cam_fwd = _cam_fwd.lerp(raw, 1.0 - exp(-delta * 6.0)).normalized()
	var fwd: Vector3 = _cam_fwd
	var want: Vector3 = car.global_position - fwd * CAM_BACK + Vector3.UP * CAM_UP
	if _cam.global_position.distance_to(want) > 40.0:
		_cam.global_position = want
	else:
		_cam.global_position = _cam.global_position.lerp(want, 1.0 - exp(-delta * 8.0))
	_cam.look_at(car.global_position + fwd * CAM_LOOK_AHEAD + Vector3.UP * 0.6, Vector3.UP)
	if _shake > 0.0:
		_cam.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.25
		_shake = maxf(_shake - delta * 2.5, 0.0)
	var st: Physics.CarState = _states[follow]
	# gentle speed FOV from a slowly smoothed speed: the old 10° kick over 38–44 m/s pumped in and
	# out whenever speed dipped (bumps, scrub) and read as the camera zooming in
	_fov_speed = lerpf(_fov_speed, st.speed, 1.0 - exp(-delta * 0.8))
	var target_fov: float = 70.0 + clampf((_fov_speed - 30.0) / 15.0, 0.0, 1.0) * 6.0
	_cam.fov = lerpf(_cam.fov, target_fov, 1.0 - exp(-delta * 1.5))
