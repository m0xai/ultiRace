class_name Profile
extends RefCounted

## Local player profile and settings in user://profile.cfg: guest name, session token (stable
## anonymous player id + reconnect), block list and control settings.

const PATH: String = "user://profile.cfg"

static var _cfg: ConfigFile = null


static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH) # missing file is fine
	return _cfg


static func get_value(key: String, def: Variant) -> Variant:
	return _load().get_value("profile", key, def)


static func set_value(key: String, value: Variant) -> void:
	_load().set_value("profile", key, value)
	_cfg.save(PATH)


static func player_name() -> String:
	return str(get_value("name", ""))


static func token() -> String:
	return str(get_value("token", ""))


static func blocked() -> Array:
	return get_value("blocked", []) as Array


static func auto_accelerate() -> bool:
	return bool(get_value("auto_accelerate", true))


static func swap_sides() -> bool:
	return bool(get_value("swap_sides", false))
