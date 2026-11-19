class_name Ui
extends RefCounted

## Tiny UI kit so every screen looks consistent. Viewport is 1280×720 (canvas_items stretch);
## on an iPhone 1 pt ≈ 1.67 units, so 44 pt ≈ 74 units: keep touch targets ≥ 80 units high.

const BG: Color = Color(0.07, 0.08, 0.12, 0.92)
const PANEL: Color = Color(0.13, 0.15, 0.22, 0.95)
const ACCENT: Color = Color(1.0, 0.8, 0.1)
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
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	return l


static func button(text: String, primary: bool = false, size: int = 28) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, MIN_TOUCH)
	b.add_theme_font_size_override("font_size", size)
	var base: Color = ACCENT if primary else Color(0.22, 0.25, 0.34)
	var fg: Color = Color(0.08, 0.08, 0.1) if primary else TEXT
	b.add_theme_stylebox_override("normal", _box(base, 18))
	b.add_theme_stylebox_override("hover", _box(base.lightened(0.1), 18))
	b.add_theme_stylebox_override("pressed", _box(base.darkened(0.2), 18))
	b.add_theme_stylebox_override("disabled", _box(base.darkened(0.5), 18))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, fg)
	b.add_theme_color_override("font_disabled_color", fg.darkened(0.4))
	return b


static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(PANEL, 22))
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
	e.add_theme_stylebox_override("normal", _box(Color(0.1, 0.11, 0.16), 14))
	e.add_theme_stylebox_override("focus", _box(Color(0.14, 0.16, 0.22), 14))
	return e


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
	if win.x <= 0 or safe.size.x <= 0 or safe.size.x > win.x:
		return Vector4.ZERO
	var vp: Vector2 = node.get_viewport().get_visible_rect().size
	var k: float = vp.x / float(win.x)
	return Vector4(safe.position.x * k, safe.position.y * k,
		(win.x - safe.end.x) * k, (win.y - safe.end.y) * k)
