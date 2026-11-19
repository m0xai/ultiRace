class_name Config
extends RefCounted

## Client configuration. Server URL priority: `-- --server <url>` command-line arg,
## then res://dev_server.txt (written by `make ios-run SERVER_URL=…`, never committed),
## then the production server.

const PROD_SERVER: String = "wss://ultirace.flappus.com"
const DEV_FILE: String = "res://dev_server.txt"


static func server_url() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
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
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def
