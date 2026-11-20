extends GdUnitTestSuite

## ResultsScreen: title reflects my finish, podium finishes get confetti, all rows listed.


func _results(my_pos: int) -> Dictionary:
	var rows: Array = []
	for p: int in range(1, 5):
		rows.append({"pos": p, "playerId": "me" if p == my_pos else "p%d" % p, "name": "N%d" % p,
			"vehicle": "bolt", "timeMs": 40000 + p * 1000, "finished": true, "bot": p != my_pos})
	return {"rows": rows}


func _screen() -> ResultsScreen:
	var rs: ResultsScreen = auto_free(ResultsScreen.new()) as ResultsScreen
	rs.my_id = "me"
	add_child(rs)
	return rs


func test_win_title_and_confetti() -> void:
	var rs: ResultsScreen = _screen()
	rs.show_results(_results(1))
	assert_str(rs._title.text).is_equal("YOU WON!")
	assert_int(rs._list.get_child_count()).is_equal(4)
	assert_int(rs.find_children("*", "CPUParticles2D", false, false).size()).is_equal(1)


func test_off_podium_no_confetti() -> void:
	var rs: ResultsScreen = _screen()
	rs.show_results(_results(4))
	assert_str(rs._title.text).is_equal("P4")
	assert_int(rs.find_children("*", "CPUParticles2D", false, false).size()).is_equal(0)
