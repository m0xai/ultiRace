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
var _car_name: Label
var _stats: Label
var _showroom: Showroom
var _lock: Button
var _chosen: String = ""
var _deadline_ms: int = 0
var _locked: bool = false


func _ready() -> void:
	var root: MarginContainer = Ui.safe_root(self)
	Ui.background(self)
	var col: VBoxContainer = Ui.vbox(10)
	root.add_child(col)
	var head: HBoxContainer = Ui.hbox(20)
	var title: Label = Ui.label("Choose your car", 48, Ui.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer = Ui.label("20", 48)
	head.add_child(title)
	head.add_child(_timer)
	col.add_child(head)
	var row: HBoxContainer = Ui.hbox(18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	# left: showroom + the selected car's name, ULT and stats
	var left: VBoxContainer = Ui.vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.1
	_showroom = Showroom.new()
	_showroom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_showroom.custom_minimum_size = Vector2(520, 300)
	left.add_child(_showroom)
	_car_name = Ui.label("", 40, Ui.TEXT)
	_car_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_car_name)
	_info = Ui.label("", 22, Ui.ACCENT)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_info)
	_stats = Ui.label("", 22, Ui.MUTED)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_stats)
	row.add_child(left)

	# right: compact cards (colour strip + name) and the lock button
	var right: VBoxContainer = Ui.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(grid)
	for v: Variant in GameData.vehicles():
		var vd: Dictionary = v as Dictionary
		var b: Button = Ui.button("", false, 26)
		b.custom_minimum_size = Vector2(250, Ui.MIN_TOUCH)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		var id: String = vd["id"] as String
		b.pressed.connect(func() -> void: _pick(id))
		var strip: ColorRect = ColorRect.new()
		strip.color = Color.html(vd["color"] as String)
		strip.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		strip.offset_left = 12
		strip.offset_right = 24
		strip.offset_top = 14
		strip.offset_bottom = -20
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(strip)
		b.add_theme_stylebox_override("pressed", Ui._lip_box(Ui.ACCENT, 2))
		b.add_theme_stylebox_override("hover_pressed", Ui._lip_box(Ui.ACCENT, 2))
		grid.add_child(b)
		_cards[id] = b
		_label_card(id, "")
	_lock = Ui.button("LOCK", true, 34)
	_lock.custom_minimum_size = Vector2(300, 100)
	_lock.disabled = true
	_lock.pressed.connect(func() -> void:
		if _chosen != "":
			send.emit(Protocol.lock(_chosen)))
	right.add_child(_lock)
	row.add_child(right)
	_show(((GameData.vehicles()[0]) as Dictionary)["id"] as String)
	Ui.pop_in(right, 0.1)


## Puts a car in the showroom with its name, ULT and stats.
func _show(id: String) -> void:
	var vd: Dictionary = GameData.vehicle(id)
	_showroom.show_car(id)
	_car_name.text = (vd["name"] as String).to_upper()
	_info.text = "ULT: " + str(ULT_NAMES.get(vd["ult"], ""))
	_stats.text = _stats_text(vd).replace("\n", "   ")


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
	b.text = head


func _pick(id: String) -> void:
	if _locked:
		return
	var b: Button = _cards[id] as Button
	if b.disabled:
		return
	_chosen = id
	for k: String in _cards:
		(_cards[k] as Button).button_pressed = k == id
	_show(id)
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
