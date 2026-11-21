class_name HomeScreen
extends Control

## Home (GAME_PLAN §2.3), UI overhaul: logo + online count + name + settings on top, the car
## showroom in the middle, and one mode switcher (Quick Play / Practice / Rooms) above a single
## big action. Rooms mode shows Browse, Create (public; the host can switch to private in the
## lobby) and join by code.

signal play(opts: Dictionary)
signal settings
signal browse

const MODES: Array[String] = ["Quick Play", "Practice", "Rooms"]
const HINTS: Array[String] = ["Race players from around the world", "Race 7 bots, any time", "Race with friends"]

var _name: LineEdit
var _code: LineEdit
var _online: Label
var _status: Label
var _hint: Label
var _mode: Switcher
var _go: Button
var _rooms: HBoxContainer
var _http: HTTPRequest
var _poll: float = 0.0
var _showroom: Showroom
var _car_i: int = 0
var _car_t: float = 0.0


## Home showroom: shows the next car every few seconds.
func _cycle_car() -> void:
	var vs: Array = GameData.vehicles()
	_showroom.show_car((vs[_car_i % vs.size()] as Dictionary)["id"] as String)
	_car_i += 1


func _ready() -> void:
	var root: MarginContainer = Ui.safe_root(self)
	Ui.background(self)
	var col: VBoxContainer = Ui.vbox(8)
	root.add_child(col)

	# top bar
	var top: HBoxContainer = Ui.hbox(18)
	var logo: Label = Ui.label("ULTIRACE", 72, Ui.ACCENT)
	top.add_child(logo)
	var info: VBoxContainer = Ui.vbox(0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	_online = Ui.label("", 22, Ui.MUTED)
	info.add_child(_online)
	_status = Ui.label("", 20, Color(1, 0.5, 0.4))
	info.add_child(_status)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	_name = Ui.line_edit("Your name", 16)
	_name.custom_minimum_size = Vector2(260, Ui.MIN_TOUCH)
	_name.text = Profile.player_name()
	_name.text_changed.connect(func(t: String) -> void: Profile.set_value("name", t))
	top.add_child(_name)
	var set_btn: Button = Ui.button("Settings")
	set_btn.custom_minimum_size = Vector2(170, Ui.MIN_TOUCH)
	set_btn.pressed.connect(func() -> void: settings.emit())
	top.add_child(set_btn)
	col.add_child(top)

	# showroom
	_showroom = Showroom.new()
	_showroom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_showroom.custom_minimum_size = Vector2(0, 200)
	col.add_child(_showroom)
	_cycle_car()

	# mode switcher + action (fixed height: switching modes doesn't move anything)
	var bottom: VBoxContainer = Ui.vbox(10)
	bottom.custom_minimum_size = Vector2(0, 236)
	var center: CenterContainer = CenterContainer.new()
	var inner: VBoxContainer = Ui.vbox(10)
	inner.custom_minimum_size = Vector2(760, 0)
	center.add_child(inner)
	bottom.add_child(center)
	_mode = Switcher.new(MODES, clampi(int(Profile.get_value("home_mode", 0)), 0, 2), 30)
	_mode.changed.connect(_on_mode)
	inner.add_child(_mode)
	_hint = Ui.label("", 22, Ui.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(_hint)
	_go = Ui.button("PLAY", true, 46)
	_go.custom_minimum_size = Vector2(0, 112)
	_go.pressed.connect(_on_go)
	inner.add_child(_go)
	_rooms = Ui.hbox(12)
	_rooms.custom_minimum_size = Vector2(0, 112)
	var browse_btn: Button = Ui.button("Browse", true, 30)
	browse_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browse_btn.size_flags_vertical = Control.SIZE_FILL
	browse_btn.pressed.connect(func() -> void: browse.emit())
	_rooms.add_child(browse_btn)
	var create: Button = Ui.button("Create", false, 30)
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.size_flags_vertical = Control.SIZE_FILL
	create.pressed.connect(func() -> void: play.emit({"create": Protocol.PUBLIC}))
	_rooms.add_child(create)
	_code = Ui.line_edit("CODE", 4)
	_code.custom_minimum_size = Vector2(150, 0)
	_code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.text_changed.connect(func(t: String) -> void:
		var up: String = t.to_upper()
		if up != t:
			_code.text = up
			_code.caret_column = up.length())
	_rooms.add_child(_code)
	var join: Button = Ui.button("Join", false, 30)
	join.custom_minimum_size = Vector2(130, 0)
	join.size_flags_vertical = Control.SIZE_FILL
	join.pressed.connect(func() -> void:
		if _code.text.length() == 4:
			play.emit({"room": _code.text}))
	_rooms.add_child(join)
	inner.add_child(_rooms)
	col.add_child(bottom)
	_on_mode(_mode.selected)
	Ui.pop_in(inner, 0.1)

	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_stats)
	_fetch_stats()


func _on_mode(i: int) -> void:
	Profile.set_value("home_mode", i)
	_hint.text = HINTS[i]
	_go.visible = i != 2
	_rooms.visible = i == 2
	_go.text = "RACE NOW" if i == 0 else "PRACTICE"


func _on_go() -> void:
	play.emit({"quick": true} if _mode.selected == 0 else {"practice": true})


func show_error(text: String) -> void:
	_status.text = text


func _process(delta: float) -> void:
	_car_t += delta
	if _car_t > 3.5 and is_visible_in_tree():
		_car_t = 0.0
		_cycle_car()
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
