extends GdUnitTestSuite

## Ramps (rendering): cars are drawn on the wedge surface, rising to the ramp's height at the lip.


func test_ramp_height_rises_along_the_wedge() -> void:
	var tr: Track = Track.load_map("frosty")
	var r: Dictionary = tr.ramps[0]
	var s0: float = float(r["s"])
	var L: float = float(r["length"])
	var h: float = float(r["height"])
	assert_float(tr.ramp_height(s0 - 1.0)).is_equal(0.0)
	assert_float(tr.ramp_height(s0 + L * 0.5)).is_equal_approx(h * 0.5, 1e-6)
	assert_float(tr.ramp_height(s0 + L)).is_equal_approx(h, 1e-6)
	assert_float(tr.ramp_height(s0 + L + 1.0)).is_equal(0.0)
	assert_float(tr.ramp_slope(s0 + 1.0)).is_equal_approx(h / L, 1e-6)
