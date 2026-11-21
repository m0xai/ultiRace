class_name EngineSound
extends Node3D

## Per-car engines (GAME_PLAN §5, audio pass 2). Each car has its own engine, rendered by
## art/audio/gen_engines.py as seamless RPM loops with an on-throttle and an off-throttle
## layer (eng_<car>_<k>_<on|off>.wav, data in assets/audio/engines.json).
## A small drivetrain turns speed into RPM: gears with a short throttle cut on upshifts, clutch
## slip in first gear, a bouncing rev limiter past the top gear (boosts). Load (on/off throttle)
## is inferred from acceleration, so the same code drives the own car and the others.
## Only the two loops around the current RPM play per layer; the rest are paused.
## The own car plays 2D (+ road and wind loops); others are 3D (RaceView keeps ≤ 5 audible).

const SHIFT_CUT_S: float = 0.13
const UP_AT: float = 0.93 # upshift at this fraction of the redline
const DOWN_AT: float = 0.6 # downshift when the lower gear would be below this fraction
const RPM_TAU: float = 0.07
const LOAD_TAU: float = 0.09
const COAST_ACCEL: float = -2.5 # m/s² — slower than this reads as off-throttle

static var _meta: Dictionary = {}

var audible: bool = true
var _master: float = 1.0 # fades to 0 after the finish (fade_out)
var _fade_rate: float = 0.0
var _own: bool = false
var _ev: bool = false
var _top: float = 40.0
var _loops: PackedFloat32Array = PackedFloat32Array()
var _gear_top: PackedFloat32Array = PackedFloat32Array() # m/s at the redline, per gear
var _idle: float = 900.0
var _redline: float = 7000.0
var _on: Array[Node] = []
var _off: Array[Node] = []
var _road: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _playing: bool = true

var gear: int = 0
var rpm: float = 900.0
var load: float = 1.0
var _cut: float = 0.0
var _prev_speed: float = 0.0
var _accel: float = 0.0
var _t: float = 0.0


static func meta() -> Dictionary:
	if _meta.is_empty():
		var f: FileAccess = FileAccess.open("res://assets/audio/engines.json", FileAccess.READ)
		if f != null:
			_meta = JSON.parse_string(f.get_as_text()) as Dictionary
	return _meta


static func engine_for(vehicle_id: String) -> Dictionary:
	var engines: Dictionary = meta().get("engines", {}) as Dictionary
	return engines.get(vehicle_id, engines.get("glacier", {})) as Dictionary


func setup(vehicle_id: String, own: bool) -> void:
	_own = own
	_top = Physics.params_for_vehicle(vehicle_id).top_speed
	var e: Dictionary = engine_for(vehicle_id)
	if e.is_empty():
		return
	var id: String = vehicle_id if (meta()["engines"] as Dictionary).has(vehicle_id) else "glacier"
	_ev = str(e.get("kind", "ice")) == "ev"
	_idle = float(e["idle"])
	_redline = float(e["redline"])
	for r: Variant in e["loops"] as Array:
		_loops.append(float(r))
	for g: Variant in e["gears"] as Array:
		_gear_top.append(float(g) * _top)
	rpm = maxf(_idle, _loops[0])
	for i: int in _loops.size():
		_on.append(_player("eng_%s_%d_on" % [id, i]))
		# other cars only get the on-throttle layer (cheaper; their coasting is rarely heard)
		_off.append(_player("eng_%s_%d_off" % [id, i]) if own else null)
	if own:
		_road = _player("road_roll") as AudioStreamPlayer
		_wind = _player("wind") as AudioStreamPlayer
	_apply(0.0)


func _player(name: String) -> Node:
	var stream: AudioStreamWAV = AudioDirector.load_stream(name, true)
	var p: Node
	if _own:
		var p2: AudioStreamPlayer = AudioStreamPlayer.new()
		p2.stream = stream
		p2.bus = "Engine"
		p = p2
	else:
		var p3: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.bus = "Engine"
		p3.unit_size = 9.0
		p3.max_distance = 140.0
		p = p3
	p.set("volume_db", -80.0)
	add_child(p)
	p.call("play")
	return p


## Drivetrain step: speed (m/s) and dt → gear, rpm, load. Pure logic (tested).
func step(speed: float, dt: float) -> void:
	_t += dt
	if dt > 0.0:
		var a: float = (speed - _prev_speed) / dt
		_accel = lerpf(_accel, a, 1.0 - exp(-dt / 0.12))
	_prev_speed = speed
	_cut = maxf(_cut - dt, 0.0)
	var target: float
	if _ev:
		target = speed / maxf(_gear_top[0], 1.0) * _redline
		target = maxf(target, _loops[0] * 0.8)
	else:
		var n: int = _gear_top.size()
		var in_gear: float = speed / maxf(_gear_top[gear], 1.0) * _redline
		if gear < n - 1 and in_gear > _redline * UP_AT and _accel > COAST_ACCEL:
			gear += 1
			_cut = SHIFT_CUT_S
		elif gear > 0 and speed / maxf(_gear_top[gear - 1], 1.0) < DOWN_AT:
			gear -= 1
		in_gear = speed / maxf(_gear_top[gear], 1.0) * _redline
		target = in_gear
		if gear == 0 and speed > 0.3:
			# clutch slip: revs up from idle before the wheels catch up
			var slip: float = lerpf(_idle, _redline * 0.55, clampf(load, 0.0, 1.0))
			target = maxf(target, lerpf(slip, target, clampf(speed / (_gear_top[0] * 0.55), 0.0, 1.0)))
		if target > _redline:
			# rev limiter bounce (boosting past the top gear)
			target = _redline * (0.965 + 0.035 * absf(sin(_t * 26.0)))
		target = maxf(target, _idle)
		if _cut > 0.0:
			target = minf(target, rpm) # throttle cut: revs fall toward the new gear
	rpm = lerpf(rpm, target, 1.0 - exp(-dt / (RPM_TAU * (0.6 if _cut > 0.0 else 1.0))))
	var want: float = 1.0 if (_accel > COAST_ACCEL or speed < 2.0) else 0.0
	if _cut > 0.0:
		want = 0.15
	load = lerpf(load, want, 1.0 - exp(-dt / LOAD_TAU))


func top_speed() -> float:
	return _top


## Fade the whole engine (and road/wind) to silence over `seconds` (finish, results).
func fade_out(seconds: float) -> void:
	_fade_rate = maxf(_fade_rate, 1.0 / maxf(seconds, 0.05))


func update(speed: float) -> void:
	var dt: float = get_process_delta_time()
	if _loops.is_empty():
		return
	_master = maxf(_master - _fade_rate * dt, 0.0)
	step(speed, dt)
	_apply(speed)


func _set_playing(on: bool) -> void:
	if on == _playing:
		return
	_playing = on
	for p: Node in _on + _off + [_road, _wind]:
		if p != null:
			p.set("stream_paused", not on)


func _apply(speed: float) -> void:
	_set_playing(audible and _master > 0.0)
	if not audible or _master <= 0.0:
		return
	# position between the two nearest loops (log scale), equal-power cross-fade
	var n: int = _loops.size()
	var i: int = 0
	while i < n - 2 and rpm > _loops[i + 1]:
		i += 1
	var f: float = clampf(log(rpm / _loops[i]) / log(_loops[i + 1] / _loops[i]), 0.0, 1.0)
	var x: float = clampf((rpm - _idle) / maxf(_redline - _idle, 1.0), 0.0, 1.0)
	var level: float = (0.55 + 0.45 * x) * (0.7 if _cut > 0.0 else 1.0) * _master
	var on_g: float = sqrt(clampf(load, 0.0, 1.0))
	var off_g: float = sqrt(clampf(1.0 - load, 0.0, 1.0)) * 0.7
	var base_db: float = -5.0 if _own else -1.0
	for k: int in n:
		var w: float = 0.0
		if k == i:
			w = cos(f * PI * 0.5)
		elif k == i + 1:
			w = sin(f * PI * 0.5)
		var pitch: float = clampf(rpm / _loops[k], 0.5, 2.0)
		_mix(_on[k], w * level * (on_g if _own else 1.0), pitch, base_db)
		if _off[k] != null:
			_mix(_off[k], w * level * off_g, pitch, base_db)
	if _road != null:
		var v: float = clampf(speed / maxf(_top, 1.0), 0.0, 1.3)
		_mix(_road, minf(v * 1.6, 1.0) * 0.55 * _master, 0.6 + 0.6 * v, -6.0)
		_mix(_wind, v * v * 0.6 * _master, 0.8 + 0.4 * v, -8.0)


func _mix(p: Node, gain: float, pitch: float, base_db: float) -> void:
	var active: bool = gain > 0.002
	p.set("stream_paused", not active)
	if active:
		p.set("volume_db", base_db + linear_to_db(gain))
		p.set("pitch_scale", pitch)
