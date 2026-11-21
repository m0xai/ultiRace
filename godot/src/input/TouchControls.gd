class_name TouchControls
extends Control

## Race controls (GAME_PLAN §2.1): two big steer buttons bottom-left, ULT button
## bottom-right (+ optional accelerate button when auto-accelerate is off). True multi-touch:
## each touch index is tracked separately. Keyboard/gamepad map to the same state.
## Swap sides moves steering to the right.

signal ability_pressed

const BASE_SIZE: float = 150.0 # ≈ 90 pt on iPhone (plan: ≥ 80 pt); S/M/L scale it
const TILT_DEAD_DEG: float = 4.0
const TILT_FULL_DEG: float = 25.0

var STEER_SIZE: Vector2 = Vector2(150, 150)
var ULT_SIZE: float = 150.0
var _tilt: bool = false
var _tilt_sens: float = 1.0
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
	_tilt = bool(Profile.get_value("tilt", false))
	_tilt_sens = float(Profile.get_value("tilt_sensitivity", 1.0))
	if _log_tilt:
		printerr("TILT controls ready: tilt=%s sens=%.2f" % [_tilt, _tilt_sens])
	var k: float = {"S": 0.85, "M": 1.0, "L": 1.2}.get(str(Profile.get_value("button_size", "M")), 1.0) as float
	STEER_SIZE = Vector2(BASE_SIZE, BASE_SIZE) * k
	ULT_SIZE = BASE_SIZE * k
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
	_rects = {"ult": Rect2(Vector2(act_x, bottom - ULT_SIZE), Vector2(ULT_SIZE, ULT_SIZE))}
	if not _tilt:
		# tilt mode has no steer buttons: the thumbs holding the phone would press them
		_rects["left"] = Rect2(Vector2(steer_x, bottom - STEER_SIZE.y), STEER_SIZE)
		_rects["right"] = Rect2(Vector2(steer_x + STEER_SIZE.x + GAP, bottom - STEER_SIZE.y), STEER_SIZE)
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
	if _tilt and steer == 0:
		steer = _tilt_steer()
	throttle = 1 if (_auto_accel or a) else 0
	queue_redraw()


func _process(delta: float) -> void:
	_update() # keyboard / gamepad polling
	# press animation: each button eases toward pressed (fast in, slower out); a ring ripples
	# out on every new press
	var held: Array = _touches.values()
	for key: String in _rects:
		var on: bool = held.has(key) or (key == "left" and steer < 0) or (key == "right" and steer > 0)
		var p: float = float(_press.get(key, 0.0))
		if on and p < 0.05 and not bool(_was.get(key, false)):
			_ripple[key] = 1.0
		_was[key] = on
		_press[key] = move_toward(p, 1.0 if on else 0.0, delta * (14.0 if on else 6.0))
		_ripple[key] = maxf(float(_ripple.get(key, 0.0)) - delta * 3.0, 0.0)
	_pulse += delta
	queue_redraw()


var _press: Dictionary = {} # region → 0…1 eased press amount
var _was: Dictionary = {}
var _ripple: Dictionary = {} # region → 1…0 ring that expands after a press
var _pulse: float = 0.0
var ult_id: String = "" # own car's ULT (icon on the yellow button)

const ICON_INK: Color = Color(0.1, 0.07, 0.2)


func _draw() -> void:
	for key: String in _rects:
		var r: Rect2 = _rects[key] as Rect2
		var p: float = float(_press.get(key, 0.0))
		var c: Vector2 = r.get_center() + Vector2(0, 4.0 * p) # sinks a little when pressed
		var rad: float = r.size.x / 2.0 * (1.0 - 0.08 * p)
		var rip: float = float(_ripple.get(key, 0.0))
		if rip > 0.0:
			draw_arc(c, rad * (1.0 + 0.35 * (1.0 - rip)), 0, TAU, 48, Color(1, 1, 1, 0.5 * rip), 4.0, true)
		match key:
			"left", "right", "accel":
				draw_circle(c, rad, Color(0, 0, 0, 0.18)) # darken behind for contrast
				draw_circle(c, rad, Color(1, 1, 1, lerpf(0.16, 0.38, p)))
				draw_arc(c, rad, 0, TAU, 48, Color(1, 1, 1, lerpf(0.55, 0.95, p)), 3.0 + 2.0 * p, true)
				if key == "accel":
					draw_string(ThemeDB.fallback_font, c + Vector2(-30, 12), "GO", HORIZONTAL_ALIGNMENT_CENTER, 60, 30, Color.WHITE)
				else:
					_arrow(c, -1.0 if key == "left" else 1.0, 1.0 + 0.12 * p)
			"ult":
				_draw_ult(c, rad, p)


## Yellow ULT button: dim while charging (a bright wedge fills clockwise), full yellow with a
## soft pulse when ready; the car's ULT icon in the middle.
func _draw_ult(c: Vector2, rad: float, p: float) -> void:
	var prog: float = clampf(ult_progress, 0.0, 1.0)
	draw_circle(c + Vector2(0, 6), rad, Color(0.55, 0.36, 0.0, 0.85)) # lip
	if ult_ready:
		var glow: float = 0.5 + 0.5 * sin(_pulse * 5.0)
		draw_circle(c, rad + 6.0 + 6.0 * glow, Color(1.0, 0.8, 0.1, 0.25 * (1.0 - p)))
		draw_circle(c, rad, Ui.ACCENT.lightened(0.15 * glow))
	else:
		draw_circle(c, rad, Color(0.45, 0.4, 0.3, 0.75))
		if prog > 0.0:
			var pts: PackedVector2Array = PackedVector2Array([c])
			var n: int = maxi(int(48.0 * prog), 2)
			for k: int in n + 1:
				var a: float = -PI / 2.0 + TAU * prog * float(k) / float(n)
				pts.append(c + Vector2(cos(a), sin(a)) * rad)
			draw_colored_polygon(pts, Color(Ui.ACCENT, 0.75))
	draw_arc(c, rad, 0, TAU, 48, Color(1, 1, 1, 0.85 if ult_ready else 0.45), 3.0, true)
	var ink: Color = ICON_INK if ult_ready else Color(ICON_INK, 0.6)
	draw_ult_icon(self, ult_id, c, rad * 0.52 * (1.0 + 0.1 * p), ink, Ui.ACCENT if ult_ready else Color(0.6, 0.55, 0.4))


## Simple vector icons per ULT, drawn into a radius-s box around c (also used by other UI).
static func draw_ult_icon(ci: CanvasItem, id: String, c: Vector2, s: float, ink: Color, bg: Color) -> void:
	var w: float = maxf(s * 0.16, 3.0)
	match id:
		"nitro": # flame with three tongues and a hot core
			var flame: Array[Vector2] = [Vector2(0, -1.0), Vector2(0.2, -0.5), Vector2(0.42, -0.78), Vector2(0.52, -0.25),
				Vector2(0.62, 0.22), Vector2(0.48, 0.62), Vector2(0.22, 0.84), Vector2(0, 0.88), Vector2(-0.22, 0.84),
				Vector2(-0.48, 0.62), Vector2(-0.62, 0.22), Vector2(-0.55, -0.2), Vector2(-0.4, -0.55), Vector2(-0.22, -0.32)]
			var outer: PackedVector2Array = PackedVector2Array()
			var inner: PackedVector2Array = PackedVector2Array()
			for v: Vector2 in flame:
				outer.append(c + v * s)
				inner.append(c + (v * 0.45 + Vector2(0, 0.42)) * s)
			ci.draw_colored_polygon(outer, ink)
			ci.draw_colored_polygon(inner, bg)
		"ram": # double chevron forward
			for k: int in 2:
				var y: float = 0.35 - 0.6 * float(k)
				ci.draw_polyline(PackedVector2Array([c + Vector2(-0.7, y + 0.45) * s, c + Vector2(0, y - 0.25) * s,
					c + Vector2(0.7, y + 0.45) * s]), ink, w * 1.4, true)
		"ice": # snowflake
			for k: int in 3:
				var d: Vector2 = Vector2.from_angle(PI / 2.0 + float(k) * PI / 3.0)
				ci.draw_line(c - d * s, c + d * s, ink, w, true)
				for sg: float in [-1.0, 1.0]:
					var tip: Vector2 = c + d * s * 0.62 * sg
					ci.draw_line(tip, tip + (d * sg).rotated(0.8) * s * 0.3, ink, w * 0.8, true)
					ci.draw_line(tip, tip + (d * sg).rotated(-0.8) * s * 0.3, ink, w * 0.8, true)
		"emp": # lightning bolt
			var bolt: PackedVector2Array = PackedVector2Array([Vector2(0.2, -1.0), Vector2(-0.55, 0.12), Vector2(-0.05, 0.12),
				Vector2(-0.25, 1.0), Vector2(0.55, -0.15), Vector2(0.05, -0.15)])
			for k: int in bolt.size():
				bolt[k] = c + bolt[k] * s
			ci.draw_colored_polygon(bolt, ink)
		"grapple": # hook
			ci.draw_line(c + Vector2(0.15, -1.0) * s, c + Vector2(0.15, 0.25) * s, ink, w * 1.4, true)
			ci.draw_arc(c + Vector2(-0.2, 0.25) * s, 0.35 * s, 0.0, PI, 16, ink, w * 1.4, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.75, 0.25) * s, c + Vector2(-0.4, 0.0) * s,
				c + Vector2(-0.4, 0.42) * s]), ink)
			ci.draw_circle(c + Vector2(0.15, -0.95) * s, 0.16 * s, ink)
		"goo": # blob with drips
			ci.draw_circle(c + Vector2(0, -0.15) * s, 0.6 * s, ink)
			ci.draw_circle(c + Vector2(-0.35, 0.55) * s, 0.2 * s, ink)
			ci.draw_rect(Rect2(c + Vector2(-0.48, 0.0) * s, Vector2(0.26, 0.55) * s), ink)
			ci.draw_circle(c + Vector2(0.3, 0.75) * s, 0.15 * s, ink)
			ci.draw_rect(Rect2(c + Vector2(0.2, 0.2) * s, Vector2(0.2, 0.55) * s), ink)
			ci.draw_circle(c + Vector2(-0.2, -0.35) * s, 0.14 * s, bg)
		"phase": # ghost
			var g: PackedVector2Array = PackedVector2Array()
			for k: int in 17:
				g.append(c + Vector2.from_angle(PI + PI * float(k) / 16.0) * 0.65 * s + Vector2(0, -0.2) * s)
			for k: int in 7:
				var x: float = 0.65 - 1.3 * float(k) / 6.0
				g.append(c + Vector2(x, 0.8 - (0.2 if k % 2 == 1 else 0.0)) * s)
			ci.draw_colored_polygon(g, ink)
			ci.draw_circle(c + Vector2(-0.25, -0.2) * s, 0.13 * s, bg)
			ci.draw_circle(c + Vector2(0.25, -0.2) * s, 0.13 * s, bg)
		"tornado": # funnel of shrinking swirls
			for k: int in 5:
				var y: float = -0.8 + 0.4 * float(k)
				var hw: float = 0.85 - 0.16 * float(k)
				var x0: float = 0.12 * sin(float(k) * 1.7)
				ci.draw_line(c + Vector2(x0 - hw, y) * s, c + Vector2(x0 + hw, y) * s, ink, w * 1.1, true)
		_:
			ci.draw_string(ThemeDB.fallback_font, c + Vector2(-s, s * 0.35), "ULT", HORIZONTAL_ALIGNMENT_CENTER, s * 2.0, int(s * 0.8), ink)


func _arrow(c: Vector2, dir: float, k: float = 1.0) -> void:
	var pts: PackedVector2Array = PackedVector2Array([c + Vector2(dir * 34, 0) * k, c + Vector2(-dir * 22, -34) * k, c + Vector2(-dir * 22, 34) * k])
	var outline: PackedVector2Array = pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.45), 6.0, true) # contrast on bright curbs/snow
	draw_colored_polygon(pts, Color(1, 1, 1, 0.9))


## Tilt maps device roll (steering-wheel style, phone held in landscape with both hands) to
## −1/0/1 steering. On the device Godot reports gravity in the phone's *portrait* axes (x = short
## edge, y = long edge toward the top, z = out of the screen; checked on an iPhone 15 Pro Max),
## so in landscape "down" lies along ±x and a steering-wheel turn shows up on y. The sign of x
## tells which way the phone is held (latched, so holding it nearly flat does not flip it):
##   roll = atan2(side·gy, √(gx² + gz²)),  side = sign(gx)
## Dead zone 4° with hysteresis so it does not flicker at the edge.
func _tilt_steer() -> int:
	var g: Vector3 = Input.get_gravity()
	if g.length() < 0.1:
		_tilt_state = 0
		return 0
	_tilt_side = tilt_side(g, _tilt_side)
	_tilt_state = tilt_from_gravity(g, _tilt_sens, _tilt_state, _tilt_side)
	if _log_tilt and Engine.get_process_frames() % 15 == 0:
		printerr("TILT g=(%.2f, %.2f, %.2f) side=%d roll=%+.1f steer=%d final=%d" % [g.x, g.y, g.z, _tilt_side, tilt_roll_deg(g, _tilt_side), _tilt_state, steer])
	return _tilt_state


var _tilt_state: int = 0
var _tilt_side: float = -1.0
var _log_tilt: bool = FileAccess.file_exists(Config.DEV_FILE) # dev builds: log tilt to the console


## Which landscape side is down: −1 home/charging port on the right (gx < 0), +1 on the left.
## Only changes when the phone is clearly upright enough to tell.
static func tilt_side(g: Vector3, prev: float) -> float:
	if absf(g.x) > 3.0 and absf(g.x) > absf(g.y):
		return signf(g.x)
	return prev


static func tilt_roll_deg(g: Vector3, side: float) -> float:
	return rad_to_deg(atan2(side * g.y, Vector2(g.x, g.z).length()))


static func tilt_from_gravity(g: Vector3, sens: float, prev: int, side: float) -> int:
	var roll: float = tilt_roll_deg(g, side) * maxf(sens, 0.1)
	var enter: float = TILT_DEAD_DEG
	var stay: float = TILT_DEAD_DEG * 0.6
	if prev != 0 and signf(roll) == float(prev) and absf(roll) > stay:
		return prev
	if absf(roll) < enter:
		return 0
	return 1 if roll > 0.0 else -1
