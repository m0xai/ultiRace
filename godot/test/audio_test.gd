extends GdUnitTestSuite

## Every sound the game references exists; engine and music streams loop.

const SFX: PackedStringArray = ["countdown", "go", "boost", "wall", "spinout", "ice", "emp", "grapple", "splat",
	"tornado", "phase", "lap", "finish", "ult_ready", "ui_click", "start_boost"]


func test_all_sfx_load() -> void:
	for n: String in SFX:
		assert_object(AudioDirector.load_stream("sfx_" + n)).override_failure_message("missing sfx_%s" % n).is_not_null()


func test_engine_and_music_loop() -> void:
	for cls: String in ["light", "medium", "heavy"]:
		for layer: String in EngineSound.LAYERS:
			var s: AudioStreamWAV = AudioDirector.load_stream("engine_%s_%s" % [cls, layer], true)
			assert_object(s).is_not_null()
			assert_int(s.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
			assert_int(s.loop_end).is_greater(1000)
	for m: String in ["menu", "sunny", "neon", "frosty"]:
		assert_object(AudioDirector.load_stream("music_" + m, true)).is_not_null()


func test_every_vehicle_has_an_engine_class() -> void:
	for v: Variant in GameData.vehicles():
		var cls: String = EngineSound.car_class((v as Dictionary)["id"] as String)
		assert_bool(cls in ["light", "medium", "heavy"]).is_true()
