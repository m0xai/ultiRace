extends Node

## Headless Godot client for e2e (GAME_PLAN §9): Quick Play / Practice, ready, lock a free
## vehicle, send throttle (the server's AFK handover drives after 20 s without input change),
## print the result and quit. Exit code 0 when a results message arrived.
## godot --headless --path godot res://src/testing/BotClient.tscn -- --server ws://… --name A --mode quick

var _conn: Connection
var _locked: bool = false
var _racing: bool = false
var _seq: int = 0
var _snaps: int = 0
var _t: float = 0.0
var _timeout_s: float = 240.0
var _drive: bool = false
var _you: int = -1
var _track: Track = null
var _pred: Prediction = null
var _go_tick: int = 0
var _in_t: float = 0.0
var _err_sum: float = 0.0
var _err_max: float = 0.0
var _err_n: int = 0


func _ready() -> void:
	_timeout_s = float(Config.arg("--timeout", "240"))
	_drive = Config.user_args().has("--drive")
	_conn = Connection.new()
	add_child(_conn)
	_conn.message.connect(_on_message)
	_conn.snapshot.connect(_on_snapshot)
	_conn.closed.connect(func(code: int, reason: String) -> void:
		print("BOTCLIENT CLOSED %d %s" % [code, reason])
		get_tree().quit(2))
	var mode: String = Config.arg("--mode", "quick")
	var hello: Dictionary = Protocol.hello(Config.arg("--name", "Godot Bot"), {"quick": mode == "quick", "practice": mode == "practice", "room": Config.arg("--room", "")})
	_conn.connect_to(Config.server_url(), hello)


func _on_message(m: Dictionary) -> void:
	match m["t"] as String:
		Protocol.T_ROOM:
			if m["state"] == "LOBBY":
				for p: Variant in m["players"] as Array:
					var pd: Dictionary = p as Dictionary
					if pd["id"] == _conn.player_id:
						if not pd["ready"]:
							_conn.send(Protocol.ready(true))
						elif pd["host"] and m["visibility"] == Protocol.PRIVATE:
							_conn.send(Protocol.start())
		Protocol.T_SELECT:
			if not _locked:
				var taken: Dictionary = {}
				for c: Variant in m["claims"] as Array:
					taken[(c as Dictionary)["vehicle"]] = true
				var vs: Array = GameData.vehicles()
				var off: int = hash(Config.arg("--name", "")) % vs.size()
				for i: int in vs.size():
					var vid: String = (vs[(i + off) % vs.size()] as Dictionary)["id"] as String
					if not taken.has(vid):
						_conn.send(Protocol.lock(vid))
						_locked = true
						break
		Protocol.T_RACE_START:
			_you = int(m["you"])
			_go_tick = int(m["tick"])
			_track = Track.load_map(m["map"] as String)
			if _drive and _you >= 0:
				_pred = Prediction.new(_track, ((m["grid"] as Array)[_you] as Dictionary)["vehicle"] as String)
		Protocol.T_EV:
			if m.get("kind", "") == "state" and m.get("state", "") == "RACING":
				_racing = true
		Protocol.T_RESULTS:
			var pos: int = -1
			var finished: bool = false
			for r: Variant in m["rows"] as Array:
				var rd: Dictionary = r as Dictionary
				if rd["playerId"] == _conn.player_id:
					pos = int(rd["pos"])
					finished = rd["finished"] as bool
			var avg_err: float = _err_sum / maxf(1.0, float(_err_n))
			print("BOTCLIENT RESULT room=%s player=%s pos=%d finished=%s snaps=%d rows=%d pred_err_avg=%.3f pred_err_max=%.2f" % [
				_conn.room_code, _conn.player_id, pos, finished, _snaps, (m["rows"] as Array).size(), avg_err, _err_max])
			_conn.close()
			get_tree().quit(0)
		Protocol.T_ERR:
			print("BOTCLIENT ERR ", m)


func _on_snapshot(s: Protocol.Snapshot) -> void:
	_snaps += 1
	if _pred == null or s.tick <= _go_tick:
		return
	for c: Protocol.SnapCar in s.cars:
		if c.id == _you:
			_pred.set_mods(s.speed_mul, s.accel_mul, s.steer_mul)
			_pred.reconcile(c, s.ack)
			if _pred.pending_inputs() > 0:
				_err_sum += _pred.last_error
				_err_n += 1
				_err_max = maxf(_err_max, _pred.last_error)


func _process(delta: float) -> void:
	_t += delta
	if _t > _timeout_s:
		print("BOTCLIENT TIMEOUT")
		get_tree().quit(3)
	if not _racing:
		return
	_in_t = minf(_in_t + delta, 0.1)
	while _in_t >= 1.0 / 30.0:
		_in_t -= 1.0 / 30.0
		_seq += 1
		var steer: int = 0
		if _drive and _pred != null and _pred.started:
			# test driver on the PREDICTED state (what a player sees): keep the centre line
			var st: Physics.CarState = _pred.state
			var want: float = clampf(-st.d * 0.06, -0.3, 0.3)
			steer = 1 if want - st.yaw_rel > 0.012 else (-1 if want - st.yaw_rel < -0.012 else 0)
		_conn.send(Protocol.input(_seq, steer, 1, false))
		if _pred != null:
			_pred.step_local(_seq, steer, 1)
