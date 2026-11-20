class_name SelectScreen
extends Control

## Vehicle select (GAME_PLAN §2.3): 8 cards with stats and ULT, simultaneous pick, first lock
## wins (server decides), claimed cards grey out with the owner's name, 20 s timer.

signal send(msg: Dictionary)

const ULT_NAMES: Dictionary = {
	"nitro": "Nitro — big speed burst", "ram": "Ram Charge — dash, spins the first car hit",
	"ice": "Ice Slick — slippery trap behind", "emp": "EMP Pulse — slows cars nearby",
	"grapple": "Grapple — pull toward the car ahead", "goo": "Goo Bomb — sticky puddle ahead",
	"phase": "Phase — ghost through everything", "tornado": "Tornado — homing spin-out",
}

var my_id: String = ""
var names: Dictionary = {} # player id → name

var _cards: Dictionary = {} # vehicle id → Button
var _timer: Label
var _info: Label
var _lock: Button
var _chosen: String = ""
var _deadline_ms: int = 0
var _locked: bool = false


func _ready() -> void:
	var root: MarginContainer = Ui.safe_root(self)
	Ui.background(self)
	var col: VBoxContainer = Ui.vbox(12)
	root.add_child(col)
	var head: HBoxContainer = Ui.hbox(20)
	var title: Label = Ui.label("Choose your car", 34, Ui.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer = Ui.label("20", 34)
	head.add_child(title)
	head.add_child(_timer)
	col.add_child(head)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grid)
	for v: Variant in GameData.vehicles():
		var vd: Dictionary = v as Dictionary
		var b: Button = Ui.button("", false, 20)
		b.custom_minimum_size = Vector2(270, 150)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		var id: String = vd["id"] as String
		b.pressed.connect(func() -> void: _pick(id))
		var col_rect: ColorRect = ColorRect.new()
		col_rect.color = Color.html(vd["color"] as String)
		col_rect.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		col_rect.offset_left = 18
		col_rect.offset_right = -18
		col_rect.offset_top = 10
		col_rect.offset_bottom = 18
		col_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col_rect)
		grid.add_child(b)
		_cards[id] = b
		_label_card(id, "")
	var foot: HBoxContainer = Ui.hbox(20)
	_info = Ui.label("", 22, Ui.MUTED)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lock = Ui.button("LOCK", true, 34)
	_lock.custom_minimum_size = Vector2(300, 100)
	_lock.disabled = true
	_lock.pressed.connect(func() -> void:
		if _chosen != "":
			send.emit(Protocol.lock(_chosen)))
	foot.add_child(_info)
	foot.add_child(_lock)
	col.add_child(foot)


func reset() -> void:
	_chosen = ""
	_locked = false
	_lock.disabled = true
	_lock.text = "LOCK"
	for id: String in _cards:
		(_cards[id] as Button).button_pressed = false


func _stats_text(vd: Dictionary) -> String:
	var st: Dictionary = vd["stats"] as Dictionary
	var bar: Callable = func(n: int) -> String: return "■".repeat(n) + "□".repeat(5 - n)
	return "SPD %s\nACC %s\nHND %s\nWGT %s" % [bar.call(int(st["speed"])), bar.call(int(st["accel"])), bar.call(int(st["handling"])), bar.call(int(st["weight"]))]


func _label_card(id: String, owner: String) -> void:
	var vd: Dictionary = GameData.vehicle(id)
	var b: Button = _cards[id] as Button
	var head: String = (vd["name"] as String).to_upper()
	if owner != "":
		head += "  · " + owner
	b.text = head + "\n" + _stats_text(vd)


func _pick(id: String) -> void:
	if _locked:
		return
	var b: Button = _cards[id] as Button
	if b.disabled:
		return
	_chosen = id
	for k: String in _cards:
		(_cards[k] as Button).button_pressed = k == id
	var vd: Dictionary = GameData.vehicle(id)
	_info.text = "%s — %s" % [vd["name"], ULT_NAMES.get(vd["ult"], "")]
	_lock.disabled = false
	send.emit(Protocol.preview(id))


func update_select(m: Dictionary) -> void:
	_deadline_ms = int(m.get("deadline", 0))
	var claimed: Dictionary = {}
	for c: Variant in m["claims"] as Array:
		var cd: Dictionary = c as Dictionary
		claimed[cd["vehicle"]] = cd["playerId"]
	for id: String in _cards:
		var b: Button = _cards[id] as Button
		var owner_id: String = str(claimed.get(id, ""))
		var owner: String = ""
		if owner_id != "":
			owner = "YOU" if owner_id == my_id else str(names.get(owner_id, "taken"))
		_label_card(id, owner)
		b.disabled = owner_id != "" and owner_id != my_id
		if owner_id == my_id:
			_locked = true
			_lock.disabled = true
			_lock.text = "LOCKED"
		elif b.disabled and _chosen == id and not _locked:
			_chosen = ""
			_lock.disabled = true
			_info.text = "Taken! Pick another car."


func _process(_delta: float) -> void:
	if _deadline_ms > 0:
		var left: float = (float(_deadline_ms) - Time.get_unix_time_from_system() * 1000.0) / 1000.0
		_timer.text = str(maxi(int(ceil(left)), 0))
