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
