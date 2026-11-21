extends GdUnitTestSuite

## UI overhaul widgets: the Switcher (replaces dropdowns) and the pause menu's two-tap leave.


func test_switcher_selects_and_emits() -> void:
	var sw: Switcher = auto_free(Switcher.new(["S", "M", "L"], 1)) as Switcher
	add_child(sw)
	var got: Array[int] = []
	sw.changed.connect(func(i: int) -> void: got.append(i))
	assert_str(sw.text()).is_equal("M")
	var buttons: Array[Node] = sw.get_child(0).get_children()
	(buttons[2] as Button).pressed.emit()
	assert_int(sw.selected).is_equal(2)
	(buttons[2] as Button).pressed.emit() # same segment again: no event
	assert_array(got).is_equal([2])
	sw.set_selected(0) # from the server: no event
	sw.select_text("L")
	assert_array(got).is_equal([2])
	assert_str(sw.text()).is_equal("L")


func test_pause_menu_leave_needs_two_taps() -> void:
	var pm: PauseMenu = auto_free(PauseMenu.new()) as PauseMenu
	add_child(pm)
	var left: Array[bool] = []
	pm.leave_race.connect(func() -> void: left.append(true))
	pm._on_leave()
	assert_int(left.size()).is_equal(0)
	pm._on_leave()
	assert_int(left.size()).is_equal(1)


## Gravity in the phone's portrait axes for a landscape grip, rolled like a steering wheel
## (right = positive) and pitched back toward flat. side −1: top of the phone points left
## (gx < 0), +1: top points right.
func _g(roll_deg: float, pitch_deg: float, side: float) -> Vector3:
	var r: float = deg_to_rad(roll_deg)
	var p: float = deg_to_rad(pitch_deg)
	return Vector3(side * cos(r) * cos(p), side * sin(r), -cos(r) * sin(p)) * 9.81


func test_tilt_steers_both_ways_in_both_landscape_grips() -> void:
	for side: float in [-1.0, 1.0]:
		var latched: float = TouchControls.tilt_side(_g(0.0, 30.0, side), -side)
		assert_float(latched).is_equal(side)
		for pitch: float in [0.0, 45.0, 75.0]:
			assert_int(TouchControls.tilt_from_gravity(_g(12.0, pitch, side), 1.0, 0, latched)).is_equal(1)
			assert_int(TouchControls.tilt_from_gravity(_g(-12.0, pitch, side), 1.0, 0, latched)).is_equal(-1)
			assert_int(TouchControls.tilt_from_gravity(_g(1.5, pitch, side), 1.0, 0, latched)).is_equal(0)
	# nearly flat: the grip side stays latched
	assert_float(TouchControls.tilt_side(_g(0.0, 85.0, 1.0), -1.0)).is_equal(-1.0)
	# hysteresis: 3° keeps an active turn, but does not start one
	assert_int(TouchControls.tilt_from_gravity(_g(3.0, 30.0, -1.0), 1.0, 1, -1.0)).is_equal(1)
	assert_int(TouchControls.tilt_from_gravity(_g(3.0, 30.0, -1.0), 1.0, 0, -1.0)).is_equal(0)


func test_tilt_mode_has_no_steer_buttons() -> void:
	Profile.set_value("tilt", true)
	var tc: TouchControls = auto_free(TouchControls.new()) as TouchControls
	add_child(tc)
	assert_bool(tc._rects.has("left") or tc._rects.has("right")).is_false()
	assert_bool(tc._rects.has("ult")).is_true()
	Profile.set_value("tilt", false)
