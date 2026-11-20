extends GdUnitTestSuite

## Interpolation: blends between snapshots, handles the s wrap, adapts the delay.

const L: float = 1000.0


func _snap(tick: int, s: float, lap: int, d: float) -> Protocol.Snapshot:
	var sn: Protocol.Snapshot = Protocol.Snapshot.new()
	sn.tick = tick
	var c: Protocol.SnapCar = Protocol.SnapCar.new()
	c.id = 0
	c.s = s
	c.lap = lap
	c.d = d
	c.speed = 30.0
	sn.cars.append(c)
	return sn


func test_blends_between_snapshots() -> void:
	var ip: Interpolation = Interpolation.new(L)
	ip.push(_snap(100, 100.0, 0, 0.0), 0.0)
	ip.push(_snap(103, 103.0, 0, 3.0), 50.0)
	ip.render_tick = 101.5
	var st: Physics.CarState = ip.sample(0)
	assert_float(st.s).is_equal_approx(101.5, 1e-9)
	assert_float(st.d).is_equal_approx(1.5, 1e-9)


func test_wrap_over_start_line() -> void:
	var ip: Interpolation = Interpolation.new(L)
	ip.push(_snap(100, 998.0, 0, 0.0), 0.0)
	ip.push(_snap(102, 2.0, 1, 0.0), 50.0)
	ip.render_tick = 101.0 # halfway: progress 1000 → s 0, lap 1
	var st: Physics.CarState = ip.sample(0)
	assert_float(st.s).is_equal_approx(0.0, 1e-9)
	assert_int(st.lap).is_equal(1)
	ip.render_tick = 100.5
	st = ip.sample(0)
	assert_float(st.s).is_equal_approx(999.0, 1e-9)
	assert_int(st.lap).is_equal(0)


func test_render_clock_trails_latest_by_delay() -> void:
	var ip: Interpolation = Interpolation.new(L)
	var t: float = 0.0
	var tick: int = 0
	for i: int in 40:
		ip.push(_snap(tick, float(tick), 0, 0.0), t)
		ip.advance(0.05)
		tick += 1 if i % 2 == 0 else 2 # 2 of 3 ticks → ~20 Hz
		t += 50.0
	var behind_ms: float = (float(ip.latest_tick()) - ip.render_tick) / 30.0 * 1000.0
	assert_float(behind_ms).is_between(60.0, 180.0)
	assert_float(ip.delay_ms).is_equal_approx(100.0, 5.0)


func test_jitter_raises_delay_up_to_cap() -> void:
	var ip: Interpolation = Interpolation.new(L)
	var t: float = 0.0
	for i: int in 60:
		ip.push(_snap(i * 2, float(i), 0, 0.0), t)
		t += 10.0 if i % 2 == 0 else 120.0
	assert_float(ip.delay_ms).is_greater(130.0)
	assert_float(ip.delay_ms).is_less_equal(160.0)


func test_ignores_out_of_order() -> void:
	var ip: Interpolation = Interpolation.new(L)
	ip.push(_snap(10, 10.0, 0, 0.0), 0.0)
	ip.push(_snap(9, 9.0, 0, 0.0), 1.0)
	assert_int(ip.latest_tick()).is_equal(10)


func test_extrapolate_moves_forward_and_wraps() -> void:
	var ip: Interpolation = Interpolation.new(L)
	ip.push(_snap(100, 995.0, 0, 1.0), 0.0) # speed 30 in _snap
	var st: Physics.CarState = ip.extrapolate(0, 0.2) # +6 m → wraps to lap 1, s 1
	assert_int(st.lap).is_equal(1)
	assert_float(st.s).is_equal_approx(1.0, 1e-9)
	assert_float(ip.extrapolate(0, 5.0).s).is_equal_approx(10.0, 1e-9) # clamped to 0.5 s → +15 m


func test_at_tick_interpolates_then_dead_reckons() -> void:
	var ip: Interpolation = Interpolation.new(L)
	ip.push(_snap(100, 100.0, 0, 0.0), 0.0)
	ip.push(_snap(103, 103.0, 0, 0.0), 50.0)
	assert_float(ip.at_tick(0, 101.5, 15.0).s).is_equal_approx(101.5, 1e-9) # between snapshots
	# past the newest: last speed (30 m/s = 1 m per tick), capped at max_ahead ticks
	assert_float(ip.at_tick(0, 106.0, 15.0).s).is_equal_approx(106.0, 1e-9)
	assert_float(ip.at_tick(0, 200.0, 15.0).s).is_equal_approx(118.0, 1e-9)
