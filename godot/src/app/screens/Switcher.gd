class_name Switcher
extends PanelContainer

## Segmented switcher (replaces dropdowns): a dark pill track with one big touch segment per
## option; the selected one is a coloured toy button. Tap a segment to select it.
##   var sw := Switcher.new(["Sunny", "Neon", "Frosty"], 0)
##   sw.changed.connect(func(i: int) -> void: ...)

signal changed(index: int)

var items: Array[String] = []
var selected: int = 0
var font_size: int = 26
var _buttons: Array[Button] = []
var _row: HBoxContainer


func _init(options: Array = [], index: int = 0, size: int = 26) -> void:
	for o: Variant in options:
		items.append(str(o))
	selected = clampi(index, 0, maxi(items.size() - 1, 0))
	font_size = size
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(0.04, 0.06, 0.16, 0.9)
	track.set_corner_radius_all(24)
	track.set_content_margin_all(6)
	track.border_color = Color(1, 1, 1, 0.1)
	track.set_border_width_all(2)
	add_theme_stylebox_override("panel", track)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	add_child(_row)
	for i: int in items.size():
		var b: Button = Button.new()
		b.text = items[i]
		b.custom_minimum_size = Vector2(0, Ui.MIN_TOUCH - 8.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", font_size)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_constant_override("outline_size", 6)
		b.pressed.connect(_on_pressed.bind(i))
		_row.add_child(b)
		_buttons.append(b)
	_restyle()


func _on_pressed(i: int) -> void:
	if i == selected:
		return
	set_selected(i)
	changed.emit(i)


## Selects without emitting `changed` (use for state coming from the server).
func set_selected(i: int) -> void:
	selected = clampi(i, 0, items.size() - 1)
	_restyle()


func select_text(text: String) -> void:
	var i: int = items.find(text)
	if i >= 0 and i != selected:
		set_selected(i)


func text() -> String:
	return items[selected] if selected < items.size() else ""


func _restyle() -> void:
	for i: int in _buttons.size():
		var b: Button = _buttons[i]
		var on: bool = i == selected
		if on:
			Ui.style_button(b, Ui.ACCENT)
			b.add_theme_stylebox_override("disabled", b.get_theme_stylebox("normal"))
		else:
			var flat: StyleBoxFlat = StyleBoxFlat.new()
			flat.bg_color = Color(1, 1, 1, 0.0)
			flat.set_corner_radius_all(18)
			flat.content_margin_left = 14
			flat.content_margin_right = 14
			var hover: StyleBoxFlat = flat.duplicate() as StyleBoxFlat
			hover.bg_color = Color(1, 1, 1, 0.08)
			for st: String in ["normal", "disabled"]:
				b.add_theme_stylebox_override(st, flat)
			b.add_theme_stylebox_override("hover", hover)
			b.add_theme_stylebox_override("pressed", hover)
			b.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.1))
		var fg: Color = Ui.TEXT if on else Ui.MUTED.lightened(0.15)
		for st: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(st, fg)
