class_name LobbyScreen
extends Control

## Lobby (GAME_PLAN §2.3, §2.3.1): players with host/ready/ping, ready toggle, host settings
## (map, laps, visibility, bots), Start, the public lobby timer, Leave.

signal send(msg: Dictionary)
signal leave

var my_id: String = ""

var _title: Label
var _timer: Label
var _list: VBoxContainer
var _ready_btn: Button
var _start_btn: Button
var _settings: VBoxContainer
var _map_btn: Switcher
var _laps_btn: Switcher
var _vis_btn: Switcher
const MAP_IDS: Array[String] = ["sunny", "neon", "frosty"]
const MAP_LABELS: Array[String] = ["Sunny", "Desert", "Frosty"]
var _room: Dictionary = {}
var _me_ready: bool = false


func _ready() -> void:
	var root: MarginContainer = Ui.safe_root(self)
	Ui.background(self)
	var col: VBoxContainer = Ui.vbox(14)
	root.add_child(col)
	var head: HBoxContainer = Ui.hbox(20)
	_title = Ui.label("Lobby", 40, Ui.ACCENT)
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer = Ui.label("", 30)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var back: Button = Ui.button("Leave")
	back.pressed.connect(func() -> void: leave.emit())
	var share: Button = Ui.button("Share link")
	share.pressed.connect(func() -> void:
		# native share sheet needs an iOS plugin (DECISIONS); copy the Universal Link for now
		DisplayServer.clipboard_set("https://ultirace.flappus.com/r/%s" % str(_room.get("code", "")))
		share.text = "Link copied!")
	head.add_child(_title)
	head.add_child(share)
	head.add_child(back)
	col.add_child(head)

	var body: HBoxContainer = Ui.hbox(24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	var list_panel: PanelContainer = Ui.panel()
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list = Ui.vbox(10)
	list_panel.add_child(_list)
	body.add_child(list_panel)

	var side: VBoxContainer = Ui.vbox(14)
	side.custom_minimum_size = Vector2(440, 0)
	_settings = Ui.vbox(8)
	_map_btn = Switcher.new(MAP_LABELS, 0, 24)
	_laps_btn = Switcher.new(["2 laps", "3 laps"], 1, 24)
	_vis_btn = Switcher.new(["Public", "Private"], 0, 24)
	_settings.add_child(Ui.label("Room settings (host)", 20, Ui.MUTED))
	for sw: Switcher in [_map_btn, _laps_btn, _vis_btn]:
		sw.changed.connect(func(_i: int) -> void: _send_settings())
		_settings.add_child(sw)
	side.add_child(_settings)
	side.add_child(_timer)
	_ready_btn = Ui.button("READY", true, 34)
	_ready_btn.custom_minimum_size = Vector2(440, 110)
	_ready_btn.pressed.connect(func() -> void: send.emit(Protocol.ready(not _me_ready)))
	side.add_child(_ready_btn)
	_start_btn = Ui.button("Start race")
	_start_btn.pressed.connect(func() -> void: send.emit(Protocol.start()))
	side.add_child(_start_btn)
	body.add_child(side)


func _host_is_me(m: Dictionary) -> bool:
	for p: Variant in m["players"] as Array:
		var pd: Dictionary = p as Dictionary
		if pd["id"] == my_id:
			return pd.get("host", false) as bool
	return false


## Report / Block on every other player; Kick for the host (GAME_PLAN §2.3.1, App Store 1.2).
func _add_moderation(row: HBoxContainer, pid: String, host: bool) -> void:
	for spec: Array in [["Report", "report"], ["Block", "block"], ["Kick", "kick"]]:
		if spec[1] == "kick" and not host:
			continue
		var b: Button = Ui.button(spec[0] as String, false, 18)
		b.custom_minimum_size = Vector2(96, 60)
		var action: String = spec[1] as String
		b.pressed.connect(_moderate.bind(action, pid, b))
		row.add_child(b)


func _moderate(action: String, pid: String, b: Button) -> void:
	if action == "report":
		send.emit(Protocol.report(pid, "name"))
		b.text = "Reported"
		b.disabled = true
	elif action == "block":
		Profile.block(pid)
		b.text = "Blocked"
		b.disabled = true
	elif action == "kick":
		send.emit(Protocol.kick(pid))


func _send_settings() -> void:
	send.emit(Protocol.settings(MAP_IDS[_map_btn.selected], 2 + _laps_btn.selected,
		bool(_room.get("bots", true)), Protocol.PUBLIC if _vis_btn.selected == 0 else Protocol.PRIVATE))


func update_room(m: Dictionary) -> void:
	_room = m
	_title.text = "%s" % m.get("name", "Lobby")
	for c: Node in _list.get_children():
		c.queue_free()
	var is_host: bool = false
	var humans: int = 0
	var all_ready: bool = true
	for p: Variant in m["players"] as Array:
		var pd: Dictionary = p as Dictionary
		if pd.get("bot", false):
			continue
		humans += 1
		var mine: bool = pd["id"] == my_id
		if mine:
			is_host = pd.get("host", false) as bool
			_me_ready = pd.get("ready", false) as bool
		if not pd.get("ready", false) and not pd.get("spec", false):
			all_ready = false
		var row: HBoxContainer = Ui.hbox(12)
		row.custom_minimum_size = Vector2(0, 64)
		var name: String = Profile.display_name(str(pd["id"]), str(pd["name"])) + ("  (you)" if mine else "")
		if pd.get("host", false):
			name = "★ " + name
		var nl: Label = Ui.label(name, 32, Ui.ACCENT if mine else Ui.TEXT)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		row.add_child(Ui.label("%d ms" % int(pd.get("pingMs", 0)), 24, Ui.MUTED))
		row.add_child(Ui.label("READY" if pd.get("ready", false) else ("watching" if pd.get("spec", false) else "…"), 28,
			Color(0.4, 1, 0.5) if pd.get("ready", false) else Ui.MUTED))
		if not mine:
			_add_moderation(row, str(pd["id"]), _host_is_me(m))
		_list.add_child(row)
	if m.get("bots", true):
		_list.add_child(Ui.label("+ bots fill the empty seats", 26, Ui.MUTED))
	_ready_btn.text = "NOT READY" if _me_ready else "READY"
	_settings.visible = is_host
	_start_btn.visible = is_host
	_start_btn.disabled = not all_ready
	_map_btn.set_selected(maxi(MAP_IDS.find(str(m.get("map", "sunny"))), 0))
	_laps_btn.set_selected(clampi(int(m.get("laps", 3)) - 2, 0, 1))
	_vis_btn.set_selected(1 if str(m.get("visibility", Protocol.PUBLIC)) == Protocol.PRIVATE else 0)
	_deadline_ms = int(m.get("deadline", 0))


var _deadline_ms: int = 0


func _process(_delta: float) -> void:
	if _deadline_ms > 0:
		var left: float = (float(_deadline_ms) - Time.get_unix_time_from_system() * 1000.0) / 1000.0
		_timer.text = "starts in %ds" % maxi(int(ceil(left)), 0)
	else:
		_timer.text = ""
