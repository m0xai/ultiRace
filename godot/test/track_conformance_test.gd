extends GdUnitTestSuite

## Track.gd must match the Go reference (gamedata/fixtures/track_*.json) within 1e-4.

const TOL: float = 1e-4


func _fixture(map_id: String) -> Dictionary:
	return GameData.load_json("fixtures/track_%s.json" % map_id) as Dictionary


func test_track_lengths_match_go() -> void:
	for map_id: String in GameData.map_ids():
		var fx: Dictionary = _fixture(map_id)
		var tr: Track = Track.load_map(map_id)
		assert_float(absf(tr.length - float(fx["length"]))).override_failure_message(
			"%s: length %f vs Go %f" % [map_id, tr.length, float(fx["length"])]).is_less(TOL)


func test_track_samples_match_go() -> void:
	for map_id: String in GameData.map_ids():
		var fx: Dictionary = _fixture(map_id)
		var tr: Track = Track.load_map(map_id)
		var worst: float = 0.0
		var worst_at: String = ""
		for row: Variant in fx["samples"] as Array:
			var r: Array = row as Array
			var smp: Track.Sample = tr.at(float(r[0]))
			# column 0 is the query s (may be out of range); Sample.s is wrapped, so compare
			# it with the wrapped query.
			var got: PackedFloat64Array = PackedFloat64Array([smp.s - MathX.wrap_pos(float(r[0]), tr.length) + float(r[0]), smp.px, smp.py, smp.pz, smp.tx, smp.ty, smp.tz,
				smp.nx, smp.ny, smp.nz, smp.curvature, smp.half_width, smp.bank])
			for i: int in got.size():
				var diff: float = absf(got[i] - float(r[i]))
				if diff > worst:
					worst = diff
					worst_at = "s=%f col=%s" % [float(r[0]), (fx["columns"] as Array)[i]]
		assert_float(worst).override_failure_message("%s: worst diff %s at %s" % [map_id, worst, worst_at]).is_less(TOL)


func test_mulberry32_matches_reference() -> void:
	var r: Rng = Rng.new(1)
	assert_int(r.next_u32()).is_equal(2693262067)
	assert_int(r.next_u32()).is_equal(11749833)
	assert_int(r.next_u32()).is_equal(2265367787)


func test_wrap_helpers() -> void:
	assert_float(MathX.wrap_pos(-1.0, 10.0)).is_equal_approx(9.0, 1e-12)
	assert_float(MathX.wrap_pos(25.0, 10.0)).is_equal_approx(5.0, 1e-12)
	assert_float(MathX.wrap_delta(990.0, 10.0, 1000.0)).is_equal_approx(20.0, 1e-9)
	assert_float(MathX.wrap_delta(10.0, 990.0, 1000.0)).is_equal_approx(-20.0, 1e-9)
