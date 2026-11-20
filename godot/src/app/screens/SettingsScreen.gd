class_name SettingsScreen
extends Control

## Settings (GAME_PLAN §2.1, §5, §6.3): controls, haptics, reduce motion, volumes, contact.
## Values live in Profile; TouchControls/AudioDirector read them.

signal closed

const SUPPORT_CONTACT: String = "" # App Store 1.2 abuse contact — set by the human (HUMAN_TODO)


func _ready() -> void:
	var root: MarginContainer = Ui.safe_root(self)
	Ui.background(self)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var col: VBoxContainer = Ui.vbox(12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	var head: HBoxContainer = Ui.hbox(20)
	var title: Label = Ui.label("Settings", 38, Ui.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var done: Button = Ui.button("Done", true)
	done.pressed.connect(func() -> void:
		AudioDirector.apply_volumes()
		closed.emit())
	head.add_child(title)
	head.add_child(done)
	col.add_child(head)
	col.add_child(_toggle("Auto-accelerate", "auto_accelerate", true))
	col.add_child(_toggle("Steering buttons on the right", "swap_sides", false))
	col.add_child(_choice("Button size", "button_size", ["S", "M", "L"], "M"))
	col.add_child(_toggle("Tilt to steer", "tilt", false))
	col.add_child(_slider("Tilt sensitivity", "tilt_sensitivity", 0.5, 1.5, 1.0))
	col.add_child(_toggle("Haptics", "haptics", true))
	col.add_child(_toggle("Reduce motion (no camera shake)", "reduce_motion", false))
	col.add_child(_slider("Music volume", "vol_music", 0.0, 1.0, 0.8))
	col.add_child(_slider("Effects volume", "vol_sfx", 0.0, 1.0, 1.0))
	col.add_child(_slider("Engine volume", "vol_engine", 0.0, 1.0, 1.0))
	if SUPPORT_CONTACT != "":
		col.add_child(Ui.label("Report abuse or get help: " + SUPPORT_CONTACT, 20, Ui.MUTED))


func _row(text: String) -> HBoxContainer:
	var h: HBoxContainer = Ui.hbox(16)
	h.custom_minimum_size = Vector2(0, Ui.MIN_TOUCH)
	var l: Label = Ui.label(text, 26)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


func _toggle(text: String, key: String, def: bool) -> HBoxContainer:
	var h: HBoxContainer = _row(text)
	var cb: CheckButton = CheckButton.new()
	cb.button_pressed = bool(Profile.get_value(key, def))
	cb.custom_minimum_size = Vector2(120, Ui.MIN_TOUCH)
	cb.scale = Vector2(1.6, 1.6) # the default switch graphic is tiny on a phone
	cb.pivot_offset = Vector2(120, Ui.MIN_TOUCH / 2.0)
	cb.toggled.connect(func(on: bool) -> void: Profile.set_value(key, on))
	h.add_child(cb)
	return h


func _slider(text: String, key: String, lo: float, hi: float, def: float) -> HBoxContainer:
	var h: HBoxContainer = _row(text)
	var s: HSlider = HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = float(Profile.get_value(key, def))
	s.custom_minimum_size = Vector2(360, Ui.MIN_TOUCH)
	s.value_changed.connect(func(v: float) -> void:
		Profile.set_value(key, v)
		AudioDirector.apply_volumes())
	h.add_child(s)
	return h


func _choice(text: String, key: String, items: Array, def: String) -> HBoxContainer:
	var h: HBoxContainer = _row(text)
	var ob: OptionButton = OptionButton.new()
	ob.custom_minimum_size = Vector2(160, Ui.MIN_TOUCH)
	ob.add_theme_font_size_override("font_size", 24)
	for it: Variant in items:
		ob.add_item(str(it))
		if str(it) == str(Profile.get_value(key, def)):
			ob.select(ob.item_count - 1)
	ob.item_selected.connect(func(i: int) -> void: Profile.set_value(key, ob.get_item_text(i)))
	h.add_child(ob)
	return h
