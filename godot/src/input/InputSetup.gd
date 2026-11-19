class_name InputSetup
extends RefCounted

## Registers the game's input actions once (keyboard + gamepad), so project.godot stays small.


static func ensure() -> void:
	if InputMap.has_action("steer_left"):
		return
	_add("steer_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_add("steer_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_add("accelerate", [KEY_UP, KEY_W], [JOY_BUTTON_A], JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add("ult", [KEY_SPACE], [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER], -1, 0.0)


static func _add(action: String, keys: Array, buttons: Array, axis: int, axis_dir: float) -> void:
	InputMap.add_action(action, 0.35)
	for k: Variant in keys:
		var e: InputEventKey = InputEventKey.new()
		e.physical_keycode = k as Key
		InputMap.action_add_event(action, e)
	for b: Variant in buttons:
		var jb: InputEventJoypadButton = InputEventJoypadButton.new()
		jb.button_index = b as JoyButton
		InputMap.action_add_event(action, jb)
	if axis >= 0:
		var jm: InputEventJoypadMotion = InputEventJoypadMotion.new()
		jm.axis = axis as JoyAxis
		jm.axis_value = axis_dir
		InputMap.action_add_event(action, jm)
