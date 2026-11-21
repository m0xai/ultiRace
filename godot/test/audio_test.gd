extends GdUnitTestSuite

## Every sound the game references exists and loops where it should; audio pass 2: per-car
## engine data, the drivetrain (gears, idle, limiter) and the music picks.

const SFX: PackedStringArray = ["countdown", "go", "boost", "wall", "spinout", "ice", "emp", "grapple", "splat",
	"tornado", "phase", "lap", "finish", "ult_ready", "ui_click", "start_boost"]


func test_all_sfx_load() -> void:
	for n: String in SFX:
		assert_object(AudioDirector.load_stream("sfx_" + n)).override_failure_message("missing sfx_%s" % n).is_not_null()


func _engine(vehicle: String) -> EngineSound:
	var es: EngineSound = auto_free(EngineSound.new()) as EngineSound
	add_child(es)
	es.setup(vehicle, true)
	return es


func test_every_car_has_its_own_engine_and_loops() -> void:
	var seen: Dictionary = {}
	for v: Variant in GameData.vehicles():
		var id: String = str((v as Dictionary)["id"])
		var e: Dictionary = EngineSound.engine_for(id)
		assert_bool((EngineSound.meta()["engines"] as Dictionary).has(id)).is_true()
		for k: int in (e["loops"] as Array).size():
			for layer: String in ["on", "off"]:
				var st: AudioStreamWAV = AudioDirector.load_stream("eng_%s_%d_%s" % [id, k, layer], true)
				assert_object(st).override_failure_message("missing eng_%s_%d_%s" % [id, k, layer]).is_not_null()
				assert_int(st.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
				assert_int(st.loop_end).is_greater(1000)
		seen[id] = true
	assert_int(seen.size()).is_equal(8)


func test_idles_on_the_grid_and_shifts_up_while_accelerating() -> void:
	var es: EngineSound = _engine("rhino")
	for i: int in 60:
		es.step(0.0, 1.0 / 60.0)
	assert_float(es.rpm).is_less(1000.0)
	assert_int(es.gear).is_equal(0)
	var top: float = Physics.params_for_vehicle("rhino").top_speed
	var gears_seen: Array[int] = []
	var v: float = 0.0
	var redline: float = float(EngineSound.engine_for("rhino")["redline"])
	for i: int in 900: # 15 s steady acceleration to top speed
		v = minf(v + top / 600.0, top)
		es.step(v, 1.0 / 60.0)
		if not gears_seen.has(es.gear):
			gears_seen.append(es.gear)
		assert_float(es.rpm).is_less_equal(redline * 1.001)
	assert_int(gears_seen.size()).is_greater_equal(4)
	assert_float(es.load).is_greater(0.8)
	# hard braking reads as off-throttle and the box shifts down
	var g: int = es.gear
	for i: int in 120:
		v = maxf(v - 0.4, 3.0)
		es.step(v, 1.0 / 60.0)
	assert_int(es.gear).is_less(g)


func test_ev_has_no_gears() -> void:
	var es: EngineSound = _engine("volt")
	var top: float = Physics.params_for_vehicle("volt").top_speed
	for i: int in 300:
		es.step(top * float(i) / 300.0, 1.0 / 60.0)
	assert_int(es.gear).is_equal(0)


func test_result_music() -> void:
	assert_str(ResultsScreen.result_music(1, 8)).is_equal("result_best")
	assert_str(ResultsScreen.result_music(4, 8)).is_equal("result_good")
	assert_str(ResultsScreen.result_music(7, 8)).is_equal("result_bad")
	assert_str(ResultsScreen.result_music(0, 8)).is_equal("result_bad")
	for m: String in ["menu", "sunny", "neon", "neon_final", "frosty", "result_best", "result_good", "result_bad"]:
		var mus: AudioStreamOggVorbis = AudioDirector.load_music(m) as AudioStreamOggVorbis
		assert_object(mus).override_failure_message("missing music " + m).is_not_null()
		assert_bool(mus.loop).is_true()
