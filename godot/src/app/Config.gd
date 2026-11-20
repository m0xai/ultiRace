class_name Config
extends RefCounted

## Client configuration. Server URL priority: `-- --server <url>` command-line arg,
## then res://dev_server.txt (written by `make ios-run SERVER_URL=…`, never committed),
## then the production server.

const PROD_SERVER: String = "wss://ultirace.flappus.com"
const DEV_FILE: String = "res://dev_server.txt"
const DEV_ARGS_FILE: String = "res://dev_args.txt"


## Command-line user args plus dev args baked into device builds (iOS does not forward launch
## arguments to Godot): `make ios-run DEV_ARGS="--watch --shot user://x.png"`.
static func user_args() -> PackedStringArray:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if FileAccess.file_exists(DEV_ARGS_FILE):
		for a: String in FileAccess.get_file_as_string(DEV_ARGS_FILE).strip_edges().split(" ", false):
			args.append(a)
	return args


static func server_url() -> String:
	var args: PackedStringArray = user_args()
	var i: int = args.find("--server")
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	if FileAccess.file_exists(DEV_FILE):
		var url: String = FileAccess.get_file_as_string(DEV_FILE).strip_edges()
		if url != "":
			return url
	if OS.is_debug_build() and OS.has_feature("editor"):
		return "ws://127.0.0.1:8090"
	return PROD_SERVER


static func arg(key: String, def: String) -> String:
	var args: PackedStringArray = user_args()
	var i: int = args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def


# ---------- device emulation (dev): `--iphone11` or the individual overrides ----------
# iPhone 11 (iPhone12,1): 1792×828 px landscape (896×414 pt @2x), 60 Hz, landscape safe area
# 48 pt per side for the notch / home-indicator column and 21 pt at the bottom (×2 = px).
const IPHONE11_MODEL: String = "iPhone12,1"
const IPHONE11_SAFE_PX: Vector4i = Vector4i(96, 0, 96, 42) # left, top, right, bottom


## Device model (OS.get_model_name(), or `--model` / `--iphone11` on desktop).
static func model_name() -> String:
	if user_args().has("--iphone11"):
		return IPHONE11_MODEL
	return arg("--model", OS.get_model_name())


## Display refresh rate (an emulated iPhone 11 is 60 Hz).
static func refresh_rate() -> float:
	if user_args().has("--iphone11") or arg("--model", "") != "":
		return 60.0
	return DisplayServer.screen_get_refresh_rate()


## Safe-area insets in window pixels (left, top, right, bottom), or (-1, …) when not emulated.
static func safe_area_override() -> Vector4i:
	if user_args().has("--iphone11"):
		return IPHONE11_SAFE_PX
	var s: String = arg("--safe-area", "")
	if s == "":
		return Vector4i(-1, -1, -1, -1)
	var p: PackedStringArray = s.split(",")
	return Vector4i(p[0].to_int(), p[1].to_int(), p[2].to_int(), p[3].to_int())
