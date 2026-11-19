class_name Prediction
extends RefCounted

## Own-car prediction + reconciliation (GAME_PLAN §3.5). The client steps its own car with the
## Physics.gd mirror every input tick; on each snapshot it resets to the server's state for the
## acknowledged input and replays the inputs the server has not used yet. Visual corrections are
## smoothed over ~100 ms; errors above SNAP_DISTANCE snap. Collisions, ULTs and effects stay
## server-only: they arrive through snapshots (spin-out freezes input locally).

const SMOOTH_S: float = 0.1
const SNAP_DISTANCE: float = 5.0
const MAX_HISTORY: int = 90

var state: Physics.CarState = Physics.CarState.new()
var _prev: Physics.CarState = Physics.CarState.new() # state one input tick earlier (render blend)
var _step_ms: float = 0.0
var started: bool = false
var last_error: float = 0.0 # metres, for the debug overlay / tests

var _track: Track
var _params: Physics.CarParams
var _ph: Physics.Constants
var _dt: float
var _mods: Physics.Mods = Physics.Mods.new()
var _history: Array[PackedInt32Array] = [] # [seq, steer, thr]
var _off_s: float = 0.0
var _off_d: float = 0.0
var _off_yaw: float = 0.0


func _init(tr: Track, vehicle_id: String) -> void:
	_track = tr
	_params = Physics.params_for_vehicle(vehicle_id)
	_ph = Physics.constants()
	_dt = 1.0 / float(GameData.balance()["tickRate"])


## Applies one local input tick (call at the input rate, after sending it to the server).
func step_local(seq: int, steer: int, thr: int) -> void:
	if not started:
		return
	_history.append(PackedInt32Array([seq, steer, thr]))
	if _history.size() > MAX_HISTORY:
		_history.remove_at(0)
	_prev = state.copy()
	Physics.step_car(state, steer, thr, _params, _mods, _track, _ph, _dt)
	_step_ms = float(Time.get_ticks_msec())


## Server correction: car = our car in the snapshot, ack = last input seq the server applied.
func reconcile(car: Protocol.SnapCar, ack: int) -> void:
	var before: Physics.CarState = state.copy()
	var had: bool = started
	state.s = car.s
	state.d = car.d
	state.yaw_rel = car.yaw_rel
	state.y = car.y
	state.vy = car.vy
	state.speed = car.speed
	state.lap = car.lap
	_mods.no_input = (car.flags & Protocol.EFF_SPINOUT) != 0
	started = true
	while _history.size() > 0 and _history[0][0] <= ack:
		_history.remove_at(0)
	for h: PackedInt32Array in _history:
		_prev = state.copy()
		Physics.step_car(state, h[1], h[2], _params, _mods, _track, _ph, _dt)
	if _history.is_empty():
		_prev = state.copy()
	if not had:
		return
	# keep what the player sees continuous: carry the error as a decaying visual offset
	var raw_s: float = MathX.wrap_delta(state.s, before.s, _track.length)
	var raw_d: float = before.d - state.d
	last_error = sqrt(raw_s * raw_s + raw_d * raw_d) # this correction only (metrics)
	var es: float = raw_s + _off_s
	var ed: float = raw_d + _off_d
	if sqrt(es * es + ed * ed) > SNAP_DISTANCE:
		_off_s = 0.0
		_off_d = 0.0
		_off_yaw = 0.0
	else:
		_off_s = es
		_off_d = ed
		_off_yaw = before.yaw_rel - state.yaw_rel + _off_yaw


## What to render this frame: the predicted state blended between the last two input ticks
## (the sim runs at 30 Hz, the screen at 60–120 Hz: without the blend the car moves in steps and
## the chase camera judders), plus the fading correction offset.
func visual(delta: float) -> Physics.CarState:
	var k: float = exp(-delta / SMOOTH_S)
	_off_s *= k
	_off_d *= k
	_off_yaw *= k
	var alpha: float = clampf((float(Time.get_ticks_msec()) - _step_ms) / (_dt * 1000.0), 0.0, 1.0)
	var v: Physics.CarState = state.copy()
	var L: float = _track.length
	var cur_prog: float = float(state.lap) * L + state.s
	var prev_prog: float = float(_prev.lap) * L + _prev.s
	if absf(cur_prog - prev_prog) > 10.0: # reconcile jump: don't blend across it
		prev_prog = cur_prog
	v.d = lerpf(_prev.d, state.d, alpha) if absf(state.d - _prev.d) < 3.0 else state.d
	v.yaw_rel = lerpf(_prev.yaw_rel, state.yaw_rel, alpha)
	v.y = lerpf(_prev.y, state.y, alpha)
	var prog: float = lerpf(prev_prog, cur_prog, alpha) + _off_s
	v.lap = int(floorf(prog / _track.length))
	v.s = prog - float(v.lap) * _track.length
	v.d += _off_d
	v.yaw_rel += _off_yaw
	return v


func pending_inputs() -> int:
	return _history.size()
