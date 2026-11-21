class_name SettingsScreen
extends Control

## Settings (GAME_PLAN §2.1, §5, §6.3): controls, haptics, reduce motion, volumes, contact.
## Values live in Profile; TouchControls/AudioDirector read them.

signal closed

const SUPPORT_CONTACT: String = "" # App Store 1.2 abuse contact — set by the human (HUMAN_TODO)


var _scroll: ScrollContainer
var _drag_from: float = -1.0 # touch y where a possible scroll drag started
var _drag_scroll: int = 0
var _dragging: bool = false


func _ready() -> void:
	var root: MarginContainer = Ui.safe_root(self)
	Ui.background(self)
	var outer: VBoxContainer = Ui.vbox(14)
	root.add_child(outer)
	var head: HBoxContainer = Ui.hbox(20)
	var title: Label = Ui.label("Settings", 56, Ui.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var done: Button = Ui.button("Done", true)
	done.pressed.connect(func() -> void:
		AudioDirector.apply_volumes()
		closed.emit())
	head.add_child(title)
	head.add_child(done)
	outer.add_child(head)
	# Two columns fit an iPhone screen, so normally nothing scrolls. The ScrollContainer stays
	# for tall fonts / small screens; drags are handled in _input so they work on any row
	# (Godot's own touch-drag only starts on empty space between the cards).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)
	var cols: HBoxContainer = Ui.hbox(20)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(cols)
	var a: VBoxContainer = _column(cols, "Controls")
	a.add_child(Ui.card(_toggle("Auto-accelerate", "auto_accelerate", true)))
	a.add_child(Ui.card(_toggle("Steer on the right", "swap_sides", false)))
	a.add_child(Ui.card(_choice("Buttons", "button_size", ["S", "M", "L"], "M")))
	a.add_child(Ui.card(_toggle("Tilt to steer", "tilt", false)))
	a.add_child(Ui.card(_slider("Tilt", "tilt_sensitivity", 0.5, 1.5, 1.0)))
	var b: VBoxContainer = _column(cols, "Sound & feel")
	b.add_child(Ui.card(_slider("Music", "vol_music", 0.0, 1.0, 0.8)))
	b.add_child(Ui.card(_slider("Effects", "vol_sfx", 0.0, 1.0, 1.0)))
	b.add_child(Ui.card(_slider("Engine", "vol_engine", 0.0, 1.0, 1.0)))
	b.add_child(Ui.card(_toggle("Haptics", "haptics", true)))
	b.add_child(Ui.card(_toggle("Reduce motion", "reduce_motion", false)))
	if SUPPORT_CONTACT != "":
		outer.add_child(Ui.label("Report abuse or get help: " + SUPPORT_CONTACT, 20, Ui.MUTED))
	_pass_mouse(cols)


func _column(parent: HBoxContainer, heading: String) -> VBoxContainer:
	var v: VBoxContainer = Ui.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(Ui.label(heading, 24, Ui.MUTED))
	parent.add_child(v)
	return v


## Containers and cards let events through (the ScrollContainer then also sees them).
func _pass_mouse(n: Node) -> void:
	for c: Node in n.get_children():
		if c is Container:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		_pass_mouse(c)


## Vertical drag anywhere over the list scrolls it (after a small dead zone, so taps and
## horizontal slider drags still work).
func _input(event: InputEvent) -> void:
	if _scroll == null or not is_visible_in_tree():
		return
	var max_scroll: int = int(_scroll.get_v_scroll_bar().max_value - _scroll.size.y)
	if max_scroll <= 0:
		return
	if event is InputEventScreenTouch or (event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		var pos: Vector2 = (event as InputEventFromWindow).get("position") as Vector2
		var down: bool = (event as InputEventScreenTouch).pressed if event is InputEventScreenTouch else (event as InputEventMouseButton).pressed
		if down and _scroll.get_global_rect().has_point(pos):
			_drag_from = pos.y
			_drag_scroll = _scroll.scroll_vertical
			_dragging = false
		elif not down:
			if _dragging:
				get_viewport().set_input_as_handled()
			_drag_from = -1.0
			_dragging = false
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _drag_from >= 0.0:
		var y: float = ((event as InputEventFromWindow).get("position") as Vector2).y
		if not _dragging and absf(y - _drag_from) > 18.0:
			_dragging = true
		if _dragging:
			_scroll.scroll_vertical = clampi(_drag_scroll + int(_drag_from - y), 0, max_scroll)
			get_viewport().set_input_as_handled()


func _row(text: String) -> HBoxContainer:
	var h: HBoxContainer = Ui.hbox(16)
	h.custom_minimum_size = Vector2(0, Ui.MIN_TOUCH)
	var l: Label = Ui.label(text, 26)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


func _toggle(text: String, key: String, def: bool) -> HBoxContainer:
	var h: HBoxContainer = _row(text)
	var cb: CheckButton = Ui.switch(bool(Profile.get_value(key, def)))
	cb.toggled.connect(func(on: bool) -> void: Profile.set_value(key, on))
	h.add_child(cb)
	return h


func _slider(text: String, key: String, lo: float, hi: float, def: float) -> HBoxContainer:
	var h: HBoxContainer = _row(text)
	var s: HSlider = Ui.slider(lo, hi, float(Profile.get_value(key, def)))
	s.custom_minimum_size = Vector2(250, Ui.MIN_TOUCH)
	s.value_changed.connect(func(v: float) -> void:
		Profile.set_value(key, v)
		AudioDirector.apply_volumes())
	h.add_child(s)
	return h


func _choice(text: String, key: String, items: Array, def: String) -> HBoxContainer:
	var h: HBoxContainer = _row(text)
	var sw: Switcher = Switcher.new(items, maxi(items.find(str(Profile.get_value(key, def))), 0))
	sw.custom_minimum_size = Vector2(250, 0)
	sw.changed.connect(func(i: int) -> void: Profile.set_value(key, sw.items[i]))
	h.add_child(sw)
	return h
