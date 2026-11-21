class_name PauseMenu
extends Control

## In-race pause menu: Resume, Settings, Leave race. Races are run by the server for everyone
## (also practice: the bots live there), so the race keeps going — the menu says so, and steering
## is released while it is open (auto-accelerate keeps the car rolling).

signal resumed
signal settings
signal leave_race

var _confirm: bool = false
var _leave_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.1, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var root: MarginContainer = Ui.safe_root(self)
	var center: CenterContainer = CenterContainer.new()
	root.add_child(center)
	var panel: PanelContainer = Ui.panel(Vector2(520, 0))
	center.add_child(panel)
	var col: VBoxContainer = Ui.vbox(14)
	panel.add_child(col)
	var title: Label = Ui.label("Paused", 64, Ui.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var note: Label = Ui.label("The race keeps going: you are racing live.", 22, Ui.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	var resume: Button = Ui.button("Resume", true, 34)
	resume.custom_minimum_size = Vector2(0, 96)
	resume.pressed.connect(func() -> void: resumed.emit())
	col.add_child(resume)
	var set_btn: Button = Ui.button("Settings")
	set_btn.pressed.connect(func() -> void: settings.emit())
	col.add_child(set_btn)
	_leave_btn = Ui.button("Leave race")
	_leave_btn.pressed.connect(_on_leave)
	col.add_child(_leave_btn)
	Ui.pop_in(panel, 0.0)


## Leaving needs a second tap (the race cannot be rejoined as the same car).
func _on_leave() -> void:
	if _confirm:
		leave_race.emit()
		return
	_confirm = true
	_leave_btn.text = "Tap again to leave"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resumed.emit()
