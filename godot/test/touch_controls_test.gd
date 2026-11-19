extends GdUnitTestSuite

## TouchControls maps independent touches to steer/ULT (multi-touch, slide between buttons).


func _touch(idx: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	return e


func test_steer_and_ult_multitouch() -> void:
	InputSetup.ensure()
	var tc: TouchControls = auto_free(TouchControls.new()) as TouchControls
	add_child(tc)
	await await_idle_frame()
	var left: Vector2 = (tc._rects["left"] as Rect2).get_center()
	var right: Vector2 = (tc._rects["right"] as Rect2).get_center()
	var ult: Vector2 = (tc._rects["ult"] as Rect2).get_center()
	var fired: Array[bool] = [false]
	tc.ability_pressed.connect(func() -> void: fired[0] = true)

	tc._input(_touch(0, left, true))
	assert_int(tc.steer).is_equal(-1)
	tc._input(_touch(1, ult, true)) # second finger: ULT while steering
	assert_bool(fired[0]).is_true()
	assert_int(tc.steer).is_equal(-1)
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = 0
	drag.position = right
	tc._input(drag) # slide to the right button
	assert_int(tc.steer).is_equal(1)
	tc._input(_touch(0, right, false))
	assert_int(tc.steer).is_equal(0)
	assert_int(tc.throttle).is_equal(1) # auto-accelerate default
