extends GdUnitTestSuite

## Protocol.gd must produce/understand exactly what internal/protocol (Go) does:
## gamedata/fixtures/protocol/messages.json.

var _fx: Dictionary


func before() -> void:
	_fx = GameData.load_json("fixtures/protocol/messages.json") as Dictionary


func _rebuild(m: Dictionary) -> Dictionary:
	match m["t"] as String:
		Protocol.T_HELLO:
			var opts: Dictionary = {}
			for k: String in ["token", "room", "quick", "practice", "blocked"]:
				if m.has(k):
					opts[k] = m[k]
			if m.has("create"):
				opts["create"] = (m["create"] as Dictionary)["visibility"]
			if m.has("auth"):
				opts["auth"] = (m["auth"] as Dictionary)["provider"]
			return Protocol.hello(m["name"] as String, opts)
		Protocol.T_READY:
			return Protocol.ready(m["ready"] as bool)
		Protocol.T_SETTINGS:
			return Protocol.settings(m["map"] as String, int(m["laps"]), m["bots"] as bool, m["visibility"] as String)
		Protocol.T_START:
			return Protocol.start()
		Protocol.T_KICK:
			return Protocol.kick(m["playerId"] as String)
		Protocol.T_PREVIEW:
			return Protocol.preview(m["vehicle"] as String)
		Protocol.T_LOCK:
			return Protocol.lock(m["vehicle"] as String)
		Protocol.T_IN:
			return Protocol.input(int(m["seq"]), int(m["steer"]), int(m["thr"]), m["ab"] as bool)
		Protocol.T_REMATCH:
			return Protocol.rematch()
		Protocol.T_REPORT:
			return Protocol.report(m["playerId"] as String, m["reason"] as String)
		Protocol.T_PING:
			return Protocol.ping(int(m["ts"]))
		Protocol.T_LEAVE:
			return Protocol.leave()
	return {}


func test_client_builders_match_go_json() -> void:
	for raw: Variant in _fx["client"] as Array:
		var want: Dictionary = raw as Dictionary
		var got: Dictionary = _rebuild(want)
		# compare through JSON so int/float representation doesn't matter
		var a: Variant = JSON.parse_string(JSON.stringify(got))
		var b: Variant = JSON.parse_string(JSON.stringify(want))
		assert_dict(a as Dictionary).override_failure_message("builder for %s: %s != %s" % [want["t"], JSON.stringify(got), JSON.stringify(want)]).is_equal(b as Dictionary)


func test_server_messages_parse() -> void:
	var seen: Dictionary = {}
	for raw: Variant in _fx["server"] as Array:
		var m: Dictionary = Protocol.parse(JSON.stringify(raw))
		assert_bool(m.has("t")).is_true()
		seen[m["t"]] = true
	for t: String in [Protocol.T_WELCOME, Protocol.T_ROOM, Protocol.T_SELECT, Protocol.T_RACE_START, Protocol.T_EV, Protocol.T_RESULTS, Protocol.T_KICKED, Protocol.T_PONG, Protocol.T_ERR]:
		assert_bool(seen.has(t)).override_failure_message("no fixture for %s" % t).is_true()


func test_snapshot_decodes_like_go() -> void:
	var snap: Dictionary = _fx["snapshot"] as Dictionary
	var b: PackedByteArray = Marshalls.base64_to_raw(snap["base64"] as String)
	var s: Protocol.Snapshot = Protocol.decode_snapshot(b)
	assert_object(s).is_not_null()
	assert_int(s.ack).is_equal(int(snap["ack"]))
	assert_int(s.tick).is_equal(int(snap["tick"]))
	var cars: Array = snap["cars"] as Array
	assert_int(s.cars.size()).is_equal(cars.size())
	for i: int in cars.size():
		var w: Dictionary = cars[i] as Dictionary
		var g: Protocol.SnapCar = s.cars[i]
		assert_int(g.id).is_equal(int(w["ID"]))
		assert_int(g.lap).is_equal(int(w["Lap"]))
		assert_int(g.flags).is_equal(int(w["Flags"]))
		assert_int(Protocol.pos_of(g.flags)).is_equal((int(w["Flags"]) >> 12) & 0xF)
		for pair: Array in [[g.s, w["S"]], [g.d, w["D"]], [g.yaw_rel, w["YawRel"]], [g.y, w["Y"]], [g.speed, w["Speed"]], [g.vy, w["Vy"]]]:
			assert_float(absf(float(pair[0]) - float(pair[1]))).is_less(1e-9)
	var proj: Array = snap["proj"] as Array
	assert_int(s.proj.size()).is_equal(proj.size())
	for i: int in proj.size():
		var w: Dictionary = proj[i] as Dictionary
		assert_int(s.proj[i].kind).is_equal(int(w["Kind"]))
		assert_float(absf(s.proj[i].s - float(w["S"]))).is_less(1e-9)
		assert_float(absf(s.proj[i].d - float(w["D"]))).is_less(1e-9)
	var traps: Array = snap["traps"] as Array
	assert_int(s.traps.size()).is_equal(traps.size())
	for i: int in traps.size():
		var w: Dictionary = traps[i] as Dictionary
		assert_int(s.traps[i].kind).is_equal(int(w["Kind"]))
		assert_float(absf(s.traps[i].s - float(w["S"]))).is_less(1e-9)
		assert_float(absf(s.traps[i].length - float(w["Len"]))).is_less(1e-9)
	assert_float(Protocol.charge_of(s.cars[1].flags)).is_equal_approx(9.0 / 15.0, 1e-9)


func test_truncated_snapshot_is_rejected() -> void:
	var b: PackedByteArray = Marshalls.base64_to_raw((_fx["snapshot"] as Dictionary)["base64"] as String)
	assert_object(Protocol.decode_snapshot(b.slice(0, 15))).is_null()
	assert_object(Protocol.decode_snapshot(PackedByteArray())).is_null()
