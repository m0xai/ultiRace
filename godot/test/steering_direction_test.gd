extends GdUnitTestSuite

## Regression (2026-11-19, found on device): the RIGHT button must turn the car to the
## driver's right. Simulates the predicted physics for a car on a straight and checks which
## side of the screen (camera behind the car) it moves to.


func test_right_button_moves_car_to_screen_right() -> void:
	var tr: Track = Track.load_map("sunny")
	var ph: Physics.Constants = Physics.constants()
	var p: Physics.CarParams = Physics.params_for_vehicle("glacier")
	var c: Physics.CarState = Physics.CarState.new()
	c.s = 20.0 # start straight
	c.speed = 25.0
	var start: Vector3 = tr.world(c.s, c.d, 0.0)
	for i: int in 20:
		Physics.step_car(c, Protocol.steer_from_screen(1), 1, p, Physics.Mods.new(), tr, ph, 1.0 / 30.0)
	var smp: Track.Sample = tr.at(c.s)
	var fwd: Vector3 = Vector3(smp.tx, 0.0, smp.tz).normalized()
	# a camera looking along fwd has its right vector = fwd × up
	var screen_right: Vector3 = fwd.cross(Vector3.UP)
	var moved: Vector3 = tr.world(c.s, c.d, 0.0) - tr.world(c.s, 0.0, 0.0)
	assert_float(moved.dot(screen_right)).override_failure_message("right button moved the car %s (screen-right %s)" % [moved, screen_right]).is_greater(0.5)
	assert_float(start.length()).is_greater_equal(0.0)
