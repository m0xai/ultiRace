class_name Haptics
extends RefCounted

## Haptic feedback (GAME_PLAN §2.2) via Input.vibrate_handheld; respects the haptics setting.
## Core Haptics patterns are backlog.


static func _on() -> bool:
	return bool(Profile.get_value("haptics", true))


static func tap_light() -> void:
	if _on():
		Input.vibrate_handheld(15, 0.3)


static func tap_heavy() -> void:
	if _on():
		Input.vibrate_handheld(40, 1.0)


static func wall(impact: float) -> void:
	if _on():
		Input.vibrate_handheld(int(clampf(impact * 4.0, 15.0, 60.0)), clampf(impact / 15.0, 0.3, 1.0))


static func hard_cc() -> void:
	if _on():
		Input.vibrate_handheld(120, 1.0)


static func double_tap() -> void:
	if _on():
		Input.vibrate_handheld(20, 0.8)
		await Engine.get_main_loop().create_timer(0.09).timeout
		Input.vibrate_handheld(20, 0.8)
