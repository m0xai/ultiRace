class_name TouchControls
extends Control

## Race controls (GAME_PLAN §2.1): two big steer buttons bottom-left, ULT button
## bottom-right (+ optional accelerate button when auto-accelerate is off). True multi-touch:
## each touch index is tracked separately. Keyboard/gamepad map to the same state.
## Swap sides moves steering to the right.

signal ability_pressed

const STEER_SIZE: Vector2 = Vector2(150, 150) # ≈ 90 pt on iPhone (plan: ≥ 80 pt)
const ULT_SIZE: float = 150.0
const GAP: float = 20.0

var steer: int = 0 # screen direction: +1 = right (convert with Protocol.steer_from_screen)
var throttle: int = 1
var ult_ready: bool = false
var ult_progress: float = 0.0 # 0–1 cooldown ring (M6)

var taps: int = 0 # any new touch anywhere (start-boost timing)
var touching: bool = false

var _touches: Dictionary = {} # touch index → region name
var _any: Dictionary = {} # all active touch indices
var _rects: Dictionary = {}
var _auto_accel: bool = true
var _swap: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_auto_accel = Profile.auto_accelerate()
	_swap = Profile.swap_sides()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var ins: Vector4 = Ui.safe_insets(self)
	var bottom: float = vp.y - ins.w - 24.0
	var left_x: float = ins.x + 28.0
	var right_x: float = vp.x - ins.z - 28.0
	var steer_x: float = right_x - 2.0 * STEER_SIZE.x - GAP if _swap else left_x
	var act_x: float = left_x if _swap else right_x - ULT_SIZE
	_rects = {
		"left": Rect2(Vector2(steer_x, bottom - STEER_SIZE.y), STEER_SIZE),
		"right": Rect2(Vector2(steer_x + STEER_SIZE.x + GAP, bottom - STEER_SIZE.y), STEER_SIZE),
		"ult": Rect2(Vector2(act_x, bottom - ULT_SIZE), Vector2(ULT_SIZE, ULT_SIZE)),
	}
	if not _auto_accel:
		var ax: float = act_x + (ULT_SIZE + GAP if _swap else -ULT_SIZE - GAP)
		_rects["accel"] = Rect2(Vector2(ax, bottom - ULT_SIZE), Vector2(ULT_SIZE, ULT_SIZE))
	queue_redraw()


func _region_at(p: Vector2) -> String:
	for key: String in _rects:
		var r: Rect2 = (_rects[key] as Rect2).grow(18.0) # forgiving hit area
		if r.has_point(p):
			return key
	return ""


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		if t.pressed:
			taps += 1
			_any[t.index] = true
		else:
			_any.erase(t.index)
		touching = not _any.is_empty()
		if t.pressed:
			var region: String = _region_at(t.position)
			if region != "":
				_touches[t.index] = region
				if region == "ult":
					ability_pressed.emit()
		else:
			_touches.erase(t.index)
		_update()
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event as InputEventScreenDrag
		if _touches.has(d.index):
			var region: String = _region_at(d.position)
			if region == "left" or region == "right":
				_touches[d.index] = region # slide between steer buttons
			_update()
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event.is_action_pressed("ult"):
			ability_pressed.emit()
		_update()


func _update() -> void:
	var l: bool = Input.is_action_pressed("steer_left")
	var r: bool = Input.is_action_pressed("steer_right")
	var a: bool = Input.is_action_pressed("accelerate")
	for region: Variant in _touches.values():
		match region as String:
			"left":
				l = true
			"right":
				r = true
			"accel":
				a = true
	steer = (1 if r else 0) - (1 if l else 0)
	throttle = 1 if (_auto_accel or a) else 0
	queue_redraw()


func _process(_delta: float) -> void:
	_update() # keyboard / gamepad polling


func _draw() -> void:
	var held: Array = _touches.values()
	for key: String in _rects:
		var r: Rect2 = _rects[key] as Rect2
		var pressed: bool = held.has(key) or (key == "left" and steer < 0) or (key == "right" and steer > 0)
		var c: Vector2 = r.get_center()
		var rad: float = r.size.x / 2.0
		draw_circle(c, rad, Color(1, 1, 1, 0.32 if pressed else 0.16))
		draw_arc(c, rad, 0, TAU, 48, Color(1, 1, 1, 0.55), 3.0, true)
		match key:
			"left":
				_arrow(c, -1.0)
			"right":
				_arrow(c, 1.0)
			"ult":
				var ring: Color = Ui.ACCENT if ult_ready else Color(1, 1, 1, 0.5)
				draw_arc(c, rad - 8.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(ult_progress, 0.0, 1.0), 48, ring, 8.0, true)
				draw_string(ThemeDB.fallback_font, c + Vector2(-30, 12), "ULT", HORIZONTAL_ALIGNMENT_CENTER, 60, 30, ring)
			"accel":
				draw_string(ThemeDB.fallback_font, c + Vector2(-30, 12), "GO", HORIZONTAL_ALIGNMENT_CENTER, 60, 30, Color.WHITE)


func _arrow(c: Vector2, dir: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array([c + Vector2(dir * 34, 0), c + Vector2(-dir * 22, -34), c + Vector2(-dir * 22, 34)])
	draw_colored_polygon(pts, Color(1, 1, 1, 0.85))
