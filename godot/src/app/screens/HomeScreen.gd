class_name HomeScreen
extends Control

## Home (GAME_PLAN §2.3): name, Quick Play with the online counter, Practice, Create Room,
## join by code. Browse Rooms arrives in M11.

signal play(opts: Dictionary)
signal settings
signal browse

var _name: LineEdit
var _code: LineEdit
var _online: Label
var _status: Label
var _http: HTTPRequest
var _poll: float = 0.0


func _ready() -> void:
	var root: MarginContainer = Ui.safe_root(self)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)
	var row: HBoxContainer = Ui.hbox(40)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)

	var left: VBoxContainer = Ui.vbox(10)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(Ui.label("UltiRace", 96, Ui.ACCENT))
	_online = Ui.label("", 22, Ui.MUTED)
	left.add_child(_online)
	left.add_child(Ui.label("Your name", 22, Ui.MUTED))
	_name = Ui.line_edit("Guest", 16)
	_name.text = Profile.player_name()
	_name.text_changed.connect(func(t: String) -> void: Profile.set_value("name", t))
	left.add_child(_name)
	_status = Ui.label("", 20, Color(1, 0.5, 0.4))
	left.add_child(_status)
	var set_btn: Button = Ui.button("Settings")
	set_btn.pressed.connect(func() -> void: settings.emit())
	left.add_child(set_btn)
	row.add_child(left)

	var right: VBoxContainer = Ui.vbox(16)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size = Vector2(440, 0)
	var quick: Button = Ui.button("QUICK PLAY", true, 40)
	quick.custom_minimum_size = Vector2(440, 120)
	quick.pressed.connect(func() -> void: play.emit({"quick": true}))
	right.add_child(quick)
	var browse_btn: Button = Ui.button("Browse rooms")
	browse_btn.pressed.connect(func() -> void: browse.emit())
	right.add_child(browse_btn)
	var practice: Button = Ui.button("Practice vs bots")
	practice.pressed.connect(func() -> void: play.emit({"practice": true}))
	right.add_child(practice)
	var create_row: HBoxContainer = Ui.hbox(12)
	var pub: Button = Ui.button("New public room")
	pub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pub.pressed.connect(func() -> void: play.emit({"create": Protocol.PUBLIC}))
	var priv: Button = Ui.button("New private room")
	priv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	priv.pressed.connect(func() -> void: play.emit({"create": Protocol.PRIVATE}))
	create_row.add_child(pub)
	create_row.add_child(priv)
	right.add_child(create_row)
	var join_row: HBoxContainer = Ui.hbox(12)
	_code = Ui.line_edit("CODE", 4)
	_code.custom_minimum_size = Vector2(200, Ui.MIN_TOUCH)
	_code.text_changed.connect(func(t: String) -> void:
		var up: String = t.to_upper()
		if up != t:
			_code.text = up
			_code.caret_column = up.length())
	var join: Button = Ui.button("Join")
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(func() -> void:
		if _code.text.length() == 4:
			play.emit({"room": _code.text}))
	join_row.add_child(_code)
	join_row.add_child(join)
	right.add_child(join_row)
	row.add_child(right)

	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_stats)
	_fetch_stats()


func show_error(text: String) -> void:
	_status.text = text


func _process(delta: float) -> void:
	_poll += delta
	if _poll > 5.0 and is_visible_in_tree():
		_poll = 0.0
		_fetch_stats()


func _fetch_stats() -> void:
	var base: String = Config.server_url().replace("wss://", "https://").replace("ws://", "http://")
	_http.cancel_request()
	_http.request(base + "/api/stats")


func _on_stats(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_online.text = "server offline"
		return
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	if d is Dictionary:
		_online.text = "%d players online" % int((d as Dictionary).get("online", 0))
