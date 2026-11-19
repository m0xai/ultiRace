extends GdUnitTestSuite

## M0 smoke tests: the project boots and its settings match the plan.

func test_boot_scene_shows_title_and_version() -> void:
	var runner: GdUnitSceneRunner = scene_runner("res://src/app/Boot.tscn")
	var title: Label = runner.find_child("Title") as Label
	var version: Label = runner.find_child("Version") as Label
	assert_str(title.text).is_equal("UltiRace")
	assert_str(version.text).contains("Godot 4.7")

func test_mobile_renderer_and_landscape() -> void:
	assert_str(str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))).is_equal("mobile")
	assert_int(int(ProjectSettings.get_setting("display/window/handheld/orientation"))).is_equal(4)

func test_untyped_declarations_are_errors() -> void:
	assert_int(int(ProjectSettings.get_setting("debug/gdscript/warnings/untyped_declaration"))).is_equal(2)
