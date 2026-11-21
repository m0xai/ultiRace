extends GdUnitTestSuite

## Physics.gd must replay every gamedata/fixtures/physics_*.json within 1e-4 of Go.

const TOL: float = 1e-4
const SCENARIOS: PackedStringArray = ["straight_full_throttle", "slalom", "wall_hits", "coast_and_lap_wrap", "jumps", "random_inputs_slowed", "road_block", "ice_patch"]


func _replay(name: String) -> Dictionary:
	var fx: Dictionary = GameData.load_json("fixtures/physics_%s.json" % name) as Dictionary
	var tr: Track = Track.load_map(fx["map"] as String)
	var ph: Physics.Constants = Physics.constants()
	var p: Physics.CarParams = Physics.params_for_vehicle(fx["vehicle"] as String)
	var want_p: Dictionary = fx["params"] as Dictionary
	var param_diff: float = maxf(absf(p.top_speed - float(want_p["TopSpeed"])), absf(p.accel - float(want_p["Accel"])))
	param_diff = maxf(param_diff, absf(p.steer_rate - float(want_p["SteerRate"])))
	param_diff = maxf(param_diff, absf(p.wall_reflect - float(want_p["WallReflect"])))
	var mods: Physics.Mods = Physics.Mods.new()
	var m: Dictionary = fx["mods"] as Dictionary
	mods.speed_mul = float(m["SpeedMul"])
	mods.accel_mul = float(m["AccelMul"])
	mods.steer_mul = float(m["SteerMul"])
	mods.no_input = bool(m["NoInput"])
	var st: Array = fx["start"] as Array
	var c: Physics.CarState = Physics.CarState.new()
	c.s = float(st[0])
	c.d = float(st[1])
	c.yaw_rel = float(st[2])
	c.y = float(st[3])
	c.vy = float(st[4])
	c.speed = float(st[5])
	c.lap = int(st[6])
	var dt: float = float(fx["dt"])
	var inputs: Array = fx["inputs"] as Array
	var states: Array = fx["states"] as Array
	var worst: float = 0.0
	var worst_at: String = ""
	var events_ok: bool = true
	for i: int in inputs.size():
		var inp: Array = inputs[i] as Array
		var ev: Physics.StepEvents = Physics.step_car(c, int(inp[0]), int(inp[1]), p, mods, tr, ph, dt)
		var w: Array = states[i] as Array
		var got: PackedFloat64Array = PackedFloat64Array([c.s, c.d, c.yaw_rel, c.y, c.vy, c.speed, float(c.lap)])
		for j: int in got.size():
			var diff: float = absf(got[j] - float(w[j]))
			if diff > worst:
				worst = diff
				worst_at = "tick %d col %s" % [i, (fx["columns"] as Array)[j]]
		if float(ev.wall_hit) != float(w[7]) or float(ev.launched) != float(w[8]) or float(ev.landed) != float(w[9]) or float(ev.crossed_start) != float(w[10]):
			if events_ok:
				worst_at += " | first event mismatch at tick %d" % i
			events_ok = false
	return {"worst": worst, "where": worst_at, "events_ok": events_ok, "param_diff": param_diff}


func test_physics_fixtures_match_go() -> void:
	for name: String in SCENARIOS:
		var r: Dictionary = _replay(name)
		assert_float(float(r["param_diff"])).override_failure_message("%s: params differ by %s" % [name, float(r["param_diff"])]).is_less(1e-12)
		assert_float(float(r["worst"])).override_failure_message("%s: worst diff %s at %s" % [name, float(r["worst"]), r["where"]]).is_less(TOL)
		assert_bool(bool(r["events_ok"])).override_failure_message("%s: events differ (%s)" % [name, r["where"]]).is_true()
