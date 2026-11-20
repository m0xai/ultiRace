class_name RoomBrowserScreen
extends Control

## Browse public rooms (GAME_PLAN §2.3.1): LOBBY first, then most humans, then newest (server
## sorts); racing rooms greyed ("joins next race"); filters map/laps; refresh every 3 s with ETag.

signal join(code: String)
signal play(opts: Dictionary)
signal back

const POLL_S: float = 3.0
const MAP_NAMES: Dictionary = {"sunny": "Sunny Circuit", "neon": "Neon Overpass", "frosty": "Frosty Peaks"}

var _list: VBoxContainer
var _header: Label
var _map_f: OptionButton
var _laps_f: OptionButton
var _http: HTTPRequest
var _etag: String = ""
var _t: float = POLL_S
var _sent_ms: int = 0
var _ping_ms: int = 0
var _rooms: Array = []


func _ready() -> void:
	var root: MarginContainer = Ui.safe_root(self)
	Ui.background(self)
	var col: VBoxContainer = Ui.vbox(12)
	root.add_child(col)
	var head: HBoxContainer = Ui.hbox(14)
	var b: Button = Ui.button("Back")
	b.pressed.connect(func() -> void: back.emit())
	head.add_child(b)
	_header = Ui.label("Public rooms", 32, Ui.ACCENT)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_header)
	_map_f = _option(["All maps", "sunny", "neon", "frosty"])
	_laps_f = _option(["Any laps", "2", "3"])
	head.add_child(_map_f)
	head.add_child(_laps_f)
	col.add_child(head)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = Ui.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	col.add_child(scroll)
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_list)


func _option(items: Array) -> OptionButton:
	var ob: OptionButton = OptionButton.new()
	ob.custom_minimum_size = Vector2(170, Ui.MIN_TOUCH)
	ob.add_theme_font_size_override("font_size", 22)
	for it: Variant in items:
		ob.add_item(str(it))
	ob.item_selected.connect(func(_i: int) -> void:
		_etag = ""
		_t = POLL_S)
	return ob


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_t = POLL_S # refresh immediately when shown; poll only while open
		return
	_t += delta
	if _t >= POLL_S and _http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_t = 0.0
		_fetch()


func _fetch() -> void:
	var base: String = Config.server_url().replace("wss://", "https://").replace("ws://", "http://")
	var q: PackedStringArray = []
	if _map_f.selected > 0:
		q.append("map=" + _map_f.get_item_text(_map_f.selected))
	if _laps_f.selected > 0:
		q.append("laps=" + _laps_f.get_item_text(_laps_f.selected))
	var headers: PackedStringArray = []
	if _etag != "":
		headers.append("If-None-Match: " + _etag)
	_sent_ms = Time.get_ticks_msec()
	_http.request(base + "/api/rooms" + ("?" + "&".join(q) if q.size() > 0 else ""), headers)


func _on_list(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_ping_ms = Time.get_ticks_msec() - _sent_ms
	if result != HTTPRequest.RESULT_SUCCESS:
		_header.text = "Public rooms — server offline"
		return
	for h: String in headers:
		if h.to_lower().begins_with("etag:"):
			_etag = h.substr(5).strip_edges()
	if code == 304:
		_header.text = "Public rooms — ping %d ms" % _ping_ms
		return
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not d is Dictionary:
		return
	_rooms = (d as Dictionary).get("rooms", []) as Array
	_header.text = "Public rooms — %d online — ping %d ms" % [int((d as Dictionary).get("online", 0)), _ping_ms]
	_render()


func _render() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	if _rooms.is_empty():
		_list.add_child(Ui.label("No public rooms right now.", 26, Ui.MUTED))
		var row: HBoxContainer = Ui.hbox(14)
		var create: Button = Ui.button("Create a public room", true)
		create.pressed.connect(func() -> void: play.emit({"create": Protocol.PUBLIC}))
		var quick: Button = Ui.button("Quick Play")
		quick.pressed.connect(func() -> void: play.emit({"quick": true}))
		row.add_child(create)
		row.add_child(quick)
		_list.add_child(row)
		return
	var now_ms: float = Time.get_unix_time_from_system() * 1000.0
	for r: Variant in _rooms:
		var rd: Dictionary = r as Dictionary
		var racing: bool = rd["state"] != "LOBBY"
		var p: PanelContainer = Ui.panel()
		var row: HBoxContainer = Ui.hbox(16)
		p.add_child(row)
		var info: VBoxContainer = Ui.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(Ui.label(str(rd["name"]), 24, Ui.MUTED if racing else Ui.TEXT))
		var left: String = ""
		if int(rd.get("deadline", 0)) > 0:
			left = " · starts in %ds" % maxi(int((float(rd["deadline"]) - now_ms) / 1000.0), 0)
		var state: String = "race in progress, joins next race" if racing else "in lobby" + left
		info.add_child(Ui.label("host %s · %s · %d laps · %d/%d humans (+%d bots) · %s" % [
			rd.get("host", ""), MAP_NAMES.get(rd["map"], rd["map"]), int(rd["laps"]), int(rd["humans"]),
			int(rd["maxCars"]), int(rd["bots"]), state], 18, Ui.MUTED))
		row.add_child(info)
		var j: Button = Ui.button("Join", not racing)
		var code: String = str(rd["code"])
		j.pressed.connect(func() -> void: join.emit(code))
		row.add_child(j)
		_list.add_child(p)
