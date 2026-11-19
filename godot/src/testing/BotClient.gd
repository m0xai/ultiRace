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


func _ready() -> void:
	_timeout_s = float(Config.arg("--timeout", "240"))
	_conn = Connection.new()
	add_child(_conn)
	_conn.message.connect(_on_message)
	_conn.snapshot.connect(func(_s: Protocol.Snapshot) -> void: _snaps += 1)
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
			print("BOTCLIENT RESULT room=%s player=%s pos=%d finished=%s snaps=%d rows=%d" % [_conn.room_code, _conn.player_id, pos, finished, _snaps, (m["rows"] as Array).size()])
			_conn.close()
			get_tree().quit(0)
		Protocol.T_ERR:
			print("BOTCLIENT ERR ", m)


func _process(delta: float) -> void:
	_t += delta
	if _t > _timeout_s:
		print("BOTCLIENT TIMEOUT")
		get_tree().quit(3)
	if _racing:
		_seq += 1
		_conn.send(Protocol.input(_seq, 0, 1, false))
