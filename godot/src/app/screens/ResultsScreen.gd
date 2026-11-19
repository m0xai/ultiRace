class_name ResultsScreen
extends Control

## Results (GAME_PLAN §2.3): finish table from the server, Rematch / Leave.

signal send(msg: Dictionary)
signal leave

var my_id: String = ""

var _list: VBoxContainer
var _rematch: Button


func _ready() -> void:
	var root: MarginContainer = Ui.safe_root(self)
	var center: CenterContainer = CenterContainer.new()
	root.add_child(center)
	var panel: PanelContainer = Ui.panel(Vector2(760, 0))
	center.add_child(panel)
	var col: VBoxContainer = Ui.vbox(10)
	panel.add_child(col)
	col.add_child(Ui.label("Results", 40, Ui.ACCENT))
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
	_rematch.text = "Rematch"
	for r: Variant in m["rows"] as Array:
		var rd: Dictionary = r as Dictionary
		var mine: bool = rd["playerId"] == my_id
		var row: HBoxContainer = Ui.hbox(14)
		var pos: Label = Ui.label("%d." % int(rd["pos"]), 26, Ui.ACCENT if mine else Ui.TEXT)
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
