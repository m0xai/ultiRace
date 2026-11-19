class_name Interpolation
extends RefCounted

## Renders remote cars ~100 ms in the past (GAME_PLAN §3.5): buffers snapshots, keeps a
## smoothed render clock behind the newest server tick, and blends between the two snapshots
## around it. Interpolating progress (lap·L + s) handles the start-line wrap for free.
## The delay adapts up to 160 ms when snapshot arrival is jittery.

const TICK_RATE: float = 30.0
const MIN_DELAY_MS: float = 100.0
const MAX_DELAY_MS: float = 160.0
const EXPECTED_GAP_MS: float = 50.0 # 20 Hz snapshots
const MAX_EXTRAPOLATE_TICKS: float = 3.0
const BUFFER_TICKS: int = 60

var track_length: float = 1.0
var delay_ms: float = MIN_DELAY_MS
var render_tick: float = -1.0

var _snaps: Array[Protocol.Snapshot] = []
var _last_arrival_ms: float = -1.0
var _jitter_ms: float = 0.0


func _init(length: float) -> void:
	track_length = length


func reset() -> void:
	_snaps.clear()
	render_tick = -1.0
	_last_arrival_ms = -1.0


func push(snap: Protocol.Snapshot, arrival_ms: float) -> void:
	if _snaps.size() > 0 and snap.tick <= _snaps[_snaps.size() - 1].tick:
		return # duplicate or out of order
	_snaps.append(snap)
	while _snaps.size() > 2 and _snaps[0].tick < snap.tick - BUFFER_TICKS:
		_snaps.remove_at(0)
	if _last_arrival_ms >= 0.0:
		var dev: float = absf((arrival_ms - _last_arrival_ms) - EXPECTED_GAP_MS)
		_jitter_ms = _jitter_ms * 0.9 + dev * 0.1
		delay_ms = clampf(MIN_DELAY_MS + 2.0 * _jitter_ms, MIN_DELAY_MS, MAX_DELAY_MS)
	_last_arrival_ms = arrival_ms


func latest_tick() -> int:
	return _snaps[_snaps.size() - 1].tick if _snaps.size() > 0 else -1


## Advances the render clock; call once per frame.
func advance(delta: float) -> void:
	if _snaps.is_empty():
		return
	var target: float = float(latest_tick()) - delay_ms / 1000.0 * TICK_RATE
	if render_tick < 0.0 or absf(render_tick - target) > 15.0:
		render_tick = target
	else:
		render_tick += delta * TICK_RATE
		render_tick += (target - render_tick) * minf(1.0, delta * 2.0) # gentle drift correction


## Interpolated state of one car at the render clock (null before the first snapshot).
func sample(car_id: int) -> Physics.CarState:
	if _snaps.is_empty():
		return null
	var a: Protocol.Snapshot = _snaps[0]
	var b: Protocol.Snapshot = _snaps[0]
	for i: int in _snaps.size():
		if float(_snaps[i].tick) <= render_tick:
			a = _snaps[i]
			b = _snaps[i + 1] if i + 1 < _snaps.size() else _snaps[i]
	var ca: Protocol.SnapCar = _find(a, car_id)
	var cb: Protocol.SnapCar = _find(b, car_id)
	if ca == null:
		return null
	if cb == null:
		cb = ca
	var out: Physics.CarState = Physics.CarState.new()
	var pa: float = float(ca.lap) * track_length + ca.s
	var pb: float = float(cb.lap) * track_length + cb.s
	var f: float = 0.0
	if b.tick > a.tick:
		f = clampf((render_tick - float(a.tick)) / float(b.tick - a.tick), 0.0, 1.0)
	var prog: float = lerpf(pa, pb, f)
	if b.tick == a.tick and render_tick > float(a.tick):
		# starved: extrapolate a little with the last known speed
		var ahead: float = minf(render_tick - float(a.tick), MAX_EXTRAPOLATE_TICKS) / TICK_RATE
		prog += ca.speed * cos(ca.yaw_rel) * ahead
	var lap: int = int(floorf(prog / track_length))
	out.lap = lap
	out.s = prog - float(lap) * track_length
	out.d = lerpf(ca.d, cb.d, f)
	out.yaw_rel = lerpf(ca.yaw_rel, cb.yaw_rel, f)
	out.y = lerpf(ca.y, cb.y, f)
	out.vy = lerpf(ca.vy, cb.vy, f)
	out.speed = lerpf(ca.speed, cb.speed, f)
	return out


func _find(s: Protocol.Snapshot, car_id: int) -> Protocol.SnapCar:
	if car_id < s.cars.size() and s.cars[car_id].id == car_id:
		return s.cars[car_id]
	for c: Protocol.SnapCar in s.cars:
		if c.id == car_id:
			return c
	return null
