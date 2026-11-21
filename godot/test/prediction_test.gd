extends GdUnitTestSuite

## Prediction: with a lagging authoritative "server" running the same physics, the predicted car
## stays where the server will be once it has applied our inputs (replay is exact).

const LAG_TICKS: int = 5 # ~150 ms one way at 30 Hz


func _snap_car(st: Physics.CarState) -> Protocol.SnapCar:
	var c: Protocol.SnapCar = Protocol.SnapCar.new()
	c.id = 0
	c.s = st.s
	c.d = st.d
	c.yaw_rel = st.yaw_rel
	c.y = st.y
	c.vy = st.vy
	c.speed = st.speed
	c.lap = st.lap
	return c


func test_replay_matches_server_under_lag() -> void:
	var tr: Track = Track.load_map("neon")
	var ph: Physics.Constants = Physics.constants()
	var p: Physics.CarParams = Physics.params_for_vehicle("hook")
	var server: Physics.CarState = Physics.CarState.new()
	server.s = 100.0
	var pred: Prediction = Prediction.new(tr, "hook")
	pred.reconcile(_snap_car(server), 0)
	var sent: Array[PackedInt32Array] = []
	var worst: float = 0.0
	for seq: int in range(1, 300):
		var steer: int = [-1, 0, 1, 0][(seq / 20) % 4]
		sent.append(PackedInt32Array([seq, steer, 1]))
		pred.step_local(seq, steer, 1)
		# server applies the input that arrived LAG_TICKS ago, then "sends" a snapshot that
		# arrives another LAG_TICKS later — model it by reconciling with the state at ack
		if seq > LAG_TICKS:
			var inp: PackedInt32Array = sent[seq - LAG_TICKS - 1]
			Physics.step_car(server, inp[1], inp[2], p, Physics.Mods.new(), tr, ph, 1.0 / 30.0)
			pred.reconcile(_snap_car(server), inp[0])
			worst = maxf(worst, pred.last_error)
	# quantisation-free snapshots: replay must be exact (no correction needed)
	assert_float(worst).is_less(1e-6)
	assert_int(pred.pending_inputs()).is_equal(LAG_TICKS)


func test_large_error_snaps_small_error_smooths() -> void:
	var tr: Track = Track.load_map("sunny")
	var pred: Prediction = Prediction.new(tr, "bolt")
	var st: Physics.CarState = Physics.CarState.new()
	st.s = 200.0
	pred.reconcile(_snap_car(st), 0)
	st.s = 201.0 # 1 m correction: smoothed
	pred.reconcile(_snap_car(st), 0)
	assert_float(pred.visual(0.0).s).is_equal_approx(200.0, 1e-6)
	assert_float(pred.visual(0.8).s).is_equal_approx(201.0, 0.1)
	st.s = 260.0 # 59 m: snap
	pred.reconcile(_snap_car(st), 0)
	assert_float(pred.visual(0.0).s).is_equal_approx(260.0, 1e-6)


## AFK autopilot: the server keeps driving but stops acking our inputs. The prediction must follow
## the server smoothly (small corrections every snapshot) instead of building up a 1 s backlog
## and dropping it again (the camera pulsed with that cycle).
func test_afk_autopilot_follows_the_server_without_pulsing() -> void:
	var tr: Track = Track.load_map("sunny")
	var p: Physics.CarParams = Physics.params_for_vehicle("bolt")
	var ph: Physics.Constants = Physics.constants()
	var dt: float = 1.0 / 30.0
	var pred: Prediction = Prediction.new(tr, "bolt")
	var server: Physics.CarState = Physics.CarState.new()
	server.s = 50.0
	server.speed = 30.0
	pred.reconcile(_snap_car(server), 1)
	var worst: float = 0.0
	for tick: int in 300: # 10 s, snapshots every 3 ticks, ack frozen at 1
		Physics.step_car(server, 0, 1, p, Physics.Mods.new(), tr, ph, dt)
		pred.step_local(tick + 2, 1, 1) # the player's (ignored) input steers
		if tick % 3 == 2:
			pred.reconcile(_snap_car(server), 1)
			if tick > 60:
				worst = maxf(worst, pred.last_error)
	assert_bool(pred.server_driven).is_true()
	assert_float(worst).is_less(1.5) # was ~30 m once the backlog was dropped
	# the server applies our inputs again → normal prediction resumes
	pred.reconcile(_snap_car(server), 400)
	assert_bool(pred.server_driven).is_false()
