class_name Ui
extends RefCounted

## Tiny UI kit so every screen looks consistent. Viewport is 1280×720 (canvas_items stretch);
## on an iPhone 1 pt ≈ 1.67 units, so 44 pt ≈ 74 units: keep touch targets ≥ 80 units high.

## Style (docs/UI_STYLE.md): chunky "toy" buttons with a dark lip underneath, saturated colours,
## heavy rounded display font (Lilita One) with dark outlines, bouncy press feedback.
const BG: Color = Color(0.07, 0.08, 0.16, 0.92)
const PANEL: Color = Color(0.12, 0.16, 0.32, 0.95)
const ACCENT: Color = Color(1.0, 0.76, 0.08)
const SECONDARY: Color = Color(0.18, 0.5, 0.98)
const LIP: int = 8
const TEXT: Color = Color(0.95, 0.96, 1.0)
const MUTED: Color = Color(0.6, 0.64, 0.72)
const MIN_TOUCH: float = 80.0


static func _box(c: Color, radius: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func label(text: String, size: int = 24, color: Color = TEXT) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.12, 0.95))
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	if size >= 40: # titles get a drop shadow
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		l.add_theme_constant_override("shadow_offset_y", maxi(3, size / 12))
		l.add_theme_constant_override("shadow_offset_x", 0)
	return l


static func button(text: String, primary: bool = false, size: int = 28) -> Button:
	var b: Button = Button.new()
	b.text = text.to_upper() if primary else text
	b.custom_minimum_size = Vector2(220, MIN_TOUCH)
	b.add_theme_font_size_override("font_size", size + (4 if primary else 0))
	var base: Color = ACCENT if primary else SECONDARY
	var fg: Color = TEXT
	b.add_theme_stylebox_override("normal", _lip_box(base, LIP))
	b.add_theme_stylebox_override("hover", _lip_box(base.lightened(0.12), LIP))
	b.add_theme_stylebox_override("pressed", _lip_box(base.darkened(0.08), 2))
	b.add_theme_stylebox_override("disabled", _lip_box(base.darkened(0.55), LIP))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, fg)
	b.add_theme_color_override("font_disabled_color", fg.darkened(0.45))
	b.add_theme_color_override("font_outline_color", base.darkened(0.6))
	b.add_theme_constant_override("outline_size", 6)
	b.button_down.connect(_squash.bind(b, true))
	b.button_up.connect(_squash.bind(b, false))
	return b


## Toy-button box: rounded face with a darker lip below (lip shrinks while pressed, so the
## face appears to move down) and a soft drop shadow.
static func _lip_box(c: Color, lip: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = _box(c, 20)
	sb.border_width_bottom = lip
	sb.border_color = c.darkened(0.45)
	sb.content_margin_top = 10 + (LIP - lip)
	sb.content_margin_bottom = 10 + lip
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 4)
	return sb


static func _squash(b: Button, down: bool) -> void:
	b.pivot_offset = b.size / 2.0
	var tw: Tween = b.create_tween()
	if down:
		tw.tween_property(b, "scale", Vector2(0.94, 0.94), 0.06)
	else:
		tw.tween_property(b, "scale", Vector2(1.05, 1.05), 0.08)
		tw.tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Applies the toy-button look to any button (OptionButton etc.).
static func style_button(b: Button, base: Color = SECONDARY) -> void:
	b.add_theme_stylebox_override("normal", _lip_box(base, LIP))
	b.add_theme_stylebox_override("hover", _lip_box(base.lightened(0.12), LIP))
	b.add_theme_stylebox_override("pressed", _lip_box(base.darkened(0.08), 2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_outline_color", base.darkened(0.6))
	b.add_theme_constant_override("outline_size", 6)


static var _icons: Dictionary = {}


## Anti-aliased pill / circle images drawn in code (cached): switch on/off, slider knob.
static func icon(kind: String) -> Texture2D:
	if _icons.has(kind):
		return _icons[kind] as Texture2D
	var w: int = 112 if kind != "knob" else 44
	var h: int = 60 if kind != "knob" else 44
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var on: bool = kind == "on"
	var track: Color = ACCENT if on else Color(0.05, 0.07, 0.18)
	var r: float = float(h) / 2.0
	var knob_c: Vector2 = Vector2(float(w) - r if on else r, r)
	for y: int in h:
		for x: int in w:
			var p: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var col: Color = Color(0, 0, 0, 0)
			if kind != "knob":
				# pill: distance to the centre segment
				var cx: float = clampf(p.x, r, float(w) - r)
				var dp: float = p.distance_to(Vector2(cx, r))
				var a: float = clampf(r - dp, 0.0, 1.0)
				if a > 0.0:
					var border: bool = dp > r - 3.0
					col = (track.darkened(0.4) if border else track)
					col.a = a
				var dk: float = p.distance_to(knob_c)
				var ka: float = clampf(r - 6.0 - dk, 0.0, 1.0)
				if ka > 0.0:
					var knob: Color = Color(1, 1, 1) if on else Color(0.62, 0.66, 0.76)
					col = col.lerp(knob, ka) if col.a > 0.0 else Color(knob, ka)
			else:
				var d: float = p.distance_to(Vector2(r, r))
				var a2: float = clampf(r - 1.0 - d, 0.0, 1.0)
				if a2 > 0.0:
					col = Color(1, 1, 1) if d < r - 5.0 else ACCENT.darkened(0.45)
					col.a = a2
			img.set_pixel(x, y, col)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_icons[kind] = tex
	return tex


static func switch(on: bool) -> CheckButton:
	var cb: CheckButton = CheckButton.new()
	cb.button_pressed = on
	cb.custom_minimum_size = Vector2(130, MIN_TOUCH)
	cb.add_theme_icon_override("checked", icon("on"))
	cb.add_theme_icon_override("unchecked", icon("off"))
	cb.add_theme_icon_override("checked_mirrored", icon("on"))
	cb.add_theme_icon_override("unchecked_mirrored", icon("off"))
	for st: String in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		cb.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	return cb


static func slider(lo: float, hi: float, value: float) -> HSlider:
	var s: HSlider = HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(360, MIN_TOUCH)
	var track: StyleBoxFlat = _box(Color(0.05, 0.07, 0.18), 8)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	var fill: StyleBoxFlat = _box(ACCENT, 8)
	fill.content_margin_top = 7
	fill.content_margin_bottom = 7
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", icon("knob"))
	s.add_theme_icon_override("grabber_highlight", icon("knob"))
	return s


## Wraps a row in a rounded card (settings lists).
static func card(content: Control) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = _box(Color(0.1, 0.14, 0.32, 0.85), 18)
	sb.content_margin_left = 22
	sb.content_margin_right = 16
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(content)
	return p


## Pops a control in (scale + fade) after `delay` seconds: use for menus appearing.
static func pop_in(c: Control, delay: float = 0.0) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2(0.85, 0.85)
	var tw: Tween = c.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void: c.pivot_offset = c.size / 2.0)
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.18)
	tw.tween_property(c, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = _box(PANEL, 26)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = min_size
	return p


static func vbox(sep: int = 14) -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 14) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func line_edit(placeholder: String, max_len: int) -> LineEdit:
	var e: LineEdit = LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(320, MIN_TOUCH)
	e.add_theme_font_size_override("font_size", 28)
	var normal: StyleBoxFlat = _box(Color(0.05, 0.07, 0.18), 16)
	normal.set_border_width_all(3)
	normal.border_color = Color(1, 1, 1, 0.15)
	var focus: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	focus.border_color = ACCENT
	e.add_theme_stylebox_override("normal", normal)
	e.add_theme_stylebox_override("focus", focus)
	return e


## Game background behind a screen: deep blue → purple gradient with diagonal speed stripes.
static func background(owner: Control) -> void:
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(0.1, 0.18, 0.46))
	g.set_color(1, Color(0.2, 0.06, 0.3))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 1)
	tex.width = 64
	tex.height = 64
	var bg: TextureRect = TextureRect.new()
	bg.texture = tex
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.clip_contents = true
	for i: int in 7:
		var stripe: ColorRect = ColorRect.new()
		stripe.color = Color(1, 1, 1, 0.035 + 0.02 * float(i % 3))
		stripe.size = Vector2(60.0 + 50.0 * float(i % 3), 2400)
		stripe.position = Vector2(-500.0 + 330.0 * float(i), -700)
		stripe.rotation = deg_to_rad(-28.0)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(stripe)
	owner.add_child(bg)
	owner.move_child(bg, 0)


## Full-screen root control that respects the iOS safe area (notch, Dynamic Island, home bar).
static func safe_root(owner: Control) -> MarginContainer:
	owner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m: MarginContainer = MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset: Vector4 = safe_insets(owner)
	m.add_theme_constant_override("margin_left", int(inset.x) + 24)
	m.add_theme_constant_override("margin_top", int(inset.y) + 16)
	m.add_theme_constant_override("margin_right", int(inset.z) + 24)
	m.add_theme_constant_override("margin_bottom", int(inset.w) + 16)
	owner.add_child(m)
	return m


## Safe-area insets (left, top, right, bottom) in viewport units.
static func safe_insets(node: Node) -> Vector4:
	var win: Vector2i = DisplayServer.window_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var emu: Vector4i = Config.safe_area_override() # device emulation on desktop (`--iphone11`)
	if emu.x >= 0:
		safe = Rect2i(emu.x, emu.y, win.x - emu.x - emu.z, win.y - emu.y - emu.w)
	if win.x <= 0 or safe.size.x <= 0 or safe.size.x > win.x:
		return Vector4.ZERO
	var vp: Vector2 = node.get_viewport().get_visible_rect().size
	var k: float = vp.x / float(win.x)
	return Vector4(safe.position.x * k, safe.position.y * k,
		(win.x - safe.end.x) * k, (win.y - safe.end.y) * k)
