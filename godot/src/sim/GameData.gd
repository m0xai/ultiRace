class_name GameData
extends RefCounted

## Loads the shared JSON game data synced from ../gamedata (`make sync`). Never edit the
## copies in godot/gamedata by hand.

const ROOT: String = "res://gamedata/"

static var _cache: Dictionary = {}


static func load_json(rel_path: String) -> Variant:
	if _cache.has(rel_path):
		return _cache[rel_path]
	var path: String = ROOT + rel_path
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("GameData: cannot read %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("GameData: invalid JSON in %s" % path)
		return null
	_cache[rel_path] = parsed
	return parsed


static func balance() -> Dictionary:
	return load_json("balance.json") as Dictionary


static func vehicles() -> Array:
	var d: Dictionary = load_json("vehicles.json") as Dictionary
	return d["vehicles"] as Array


static func vehicle(id: String) -> Dictionary:
	for v: Variant in vehicles():
		var vd: Dictionary = v as Dictionary
		if vd["id"] == id:
			return vd
	return {}


static func map_data(id: String) -> Dictionary:
	return load_json("maps/%s.json" % id) as Dictionary


static func map_ids() -> PackedStringArray:
	return PackedStringArray(["frosty", "neon", "sunny"])
