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
	assert_float(pred.visual(0.3).s).is_equal_approx(201.0, 0.1)
	st.s = 260.0 # 59 m: snap
	pred.reconcile(_snap_car(st), 0)
	assert_float(pred.visual(0.0).s).is_equal_approx(260.0, 1e-6)
