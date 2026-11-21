class_name ResultsScreen
extends Control

## Results (GAME_PLAN §2.3): finish table from the server, Rematch / Leave.

signal send(msg: Dictionary)
signal leave

var my_id: String = ""

var _list: VBoxContainer
var _rematch: Button
var _title: Label
var _panel: PanelContainer

const MEDALS: Array[Color] = [Color(1.0, 0.8, 0.15), Color(0.82, 0.86, 0.92), Color(0.86, 0.55, 0.3)]


func _ready() -> void:
	var root: MarginContainer = Ui.safe_root(self)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.12, 0.3) # light: the finish camera orbits your car behind it
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	move_child(dim, 0)
	var row: HBoxContainer = Ui.hbox(0)
	root.add_child(row)
	var spacer: Control = Control.new() # left part of the screen shows your car
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var center: CenterContainer = CenterContainer.new()
	row.add_child(center)
	var panel: PanelContainer = Ui.panel(Vector2(640, 0))
	center.add_child(panel)
	var col: VBoxContainer = Ui.vbox(10)
	panel.add_child(col)
	_title = Ui.label("Results", 64, Ui.ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_panel = panel
	_list = Ui.vbox(4)
	col.add_child(_list)
	var buttons: HBoxContainer = Ui.hbox(16)
	_rematch = Ui.button("Rematch", true)
	_rematch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rematch.pressed.connect(func() -> void:
		send.emit(Protocol.rematch())
		_rematch.disabled = true
		_rematch.text = "Waiting…")
	var quit: Button = Ui.button("Leave")
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(func() -> void: leave.emit())
	buttons.add_child(_rematch)
	buttons.add_child(quit)
	col.add_child(buttons)


func show_results(m: Dictionary) -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	_rematch.disabled = false
	_rematch.text = "REMATCH"
	var i: int = 0
	var my_pos: int = 0
	for r: Variant in m["rows"] as Array:
		var rd: Dictionary = r as Dictionary
		var mine: bool = rd["playerId"] == my_id
		var place: int = int(rd["pos"])
		if mine:
			my_pos = place
		var row: HBoxContainer = Ui.hbox(14)
		var pos_col: Color = MEDALS[place - 1] if place >= 1 and place <= 3 else (Ui.ACCENT if mine else Ui.TEXT)
		var pos: Label = Ui.label("%d." % place, 30 if place <= 3 else 26, pos_col)
		pos.custom_minimum_size = Vector2(50, 0)
		row.add_child(pos)
		var nm: Label = Ui.label("%s%s" % [Profile.display_name(str(rd["playerId"]), str(rd["name"])), " (bot)" if rd.get("bot", false) else ""], 26, Ui.ACCENT if mine else Ui.TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		row.add_child(Ui.label(str(GameData.vehicle(rd["vehicle"] as String).get("name", "")), 22, Ui.MUTED))
		var t: String = ("%.2f s" % (float(rd["timeMs"]) / 1000.0)) if rd["finished"] else "DNF"
		row.add_child(Ui.label(t, 24))
		if not mine and not rd.get("bot", false):
			var pid: String = str(rd["playerId"])
			var rep: Button = Ui.button("Report", false, 16)
			rep.custom_minimum_size = Vector2(84, 52)
			rep.pressed.connect(func() -> void:
				send.emit(Protocol.report(pid, "name"))
				rep.disabled = true)
			var blk: Button = Ui.button("Block", false, 16)
			blk.custom_minimum_size = Vector2(84, 52)
			blk.pressed.connect(func() -> void:
				Profile.block(pid)
				blk.disabled = true)
			row.add_child(rep)
			row.add_child(blk)
		_list.add_child(row)
		Ui.pop_in(row, 0.15 + 0.07 * float(i))
		i += 1
	AudioDirector.play_music(result_music(my_pos, i))
	_title.text = "YOU WON!" if my_pos == 1 else ("P%d — PODIUM!" % my_pos if my_pos in [2, 3] else ("P%d" % my_pos if my_pos > 0 else "RESULTS"))
	Ui.pop_in(_panel, 0.0)
	if my_pos >= 1 and my_pos <= 3:
		_confetti()


## Confetti burst from the top of the screen (podium finishes).
func _confetti() -> void:
	var c: CPUParticles2D = CPUParticles2D.new()
	c.position = Vector2(get_viewport_rect().size.x / 2.0, -20)
	c.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	c.emission_rect_extents = Vector2(get_viewport_rect().size.x / 2.0, 10)
	c.amount = 160
	c.lifetime = 3.0
	c.one_shot = true
	c.explosiveness = 0.85
	c.direction = Vector2(0, 1)
	c.spread = 25.0
	c.initial_velocity_min = 120.0
	c.initial_velocity_max = 320.0
	c.gravity = Vector2(0, 260)
	c.angular_velocity_min = -360.0
	c.angular_velocity_max = 360.0
	c.scale_amount_min = 6.0
	c.scale_amount_max = 11.0
	var g: Gradient = Gradient.new()
	g.set_color(0, Ui.ACCENT)
	g.set_color(1, Ui.SECONDARY)
	g.add_point(0.33, Color(1.0, 0.3, 0.45))
	g.add_point(0.66, Color(0.3, 1.0, 0.5))
	c.color_initial_ramp = g
	add_child(c)
	c.emitting = true
	c.finished.connect(c.queue_free)


## Podium → "best", upper half → "good", otherwise "bad" (also DNF / spectating).
static func result_music(pos: int, total: int) -> String:
	if pos >= 1 and pos <= 3:
		return "result_best"
	if pos >= 1 and pos <= int(ceil(float(total) / 2.0)):
		return "result_good"
	return "result_bad"
