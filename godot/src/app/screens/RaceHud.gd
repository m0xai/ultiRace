class_name RaceHud
extends Control

## Race HUD (GAME_PLAN §4.5): big position, lap, race timer, countdown, minimap, name tags
## for the ≤ 4 nearest cars, reconnect pill. All values come from the server via RaceView.

const MINIMAP_SIZE: float = 220.0
const TAG_MAX: int = 4

signal pause_pressed

var view: RaceView = null
var _pause: Button
var laps: int = 3
var reconnecting: bool = false

var _pos: Label
var _lap: Label
var _time: Label
var _center: Label
var _pill: Label
var _map_pts: PackedVector2Array = PackedVector2Array()
var _map_rect: Rect2 = Rect2()
var _map_xform: Transform2D = Transform2D.IDENTITY
var _map_size: Vector2 = Vector2(MINIMAP_SIZE, MINIMAP_SIZE) # track bounds on screen (fits MINIMAP_SIZE)
var _map_box: StyleBoxFlat
var _go_flash: float = 0.0
var _banner: Label
var _banner_t: float = 0.0


const COUNT_COLORS: Array[Color] = [Color(1.0, 0.85, 0.1), Color(1.0, 0.55, 0.1), Color(1.0, 0.25, 0.2)] # 1, 2, 3


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var root: MarginContainer = Ui.safe_root(self)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top: HBoxContainer = Ui.hbox(28)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(top)
	_pos = Ui.label("–/–", 64, Ui.ACCENT)
	top.add_child(_pos)
	var col: VBoxContainer = Ui.vbox(0)
	_lap = Ui.label("LAP 1/3", 30)
	_time = Ui.label("0:00.00", 26, Ui.MUTED)
	col.add_child(_lap)
	col.add_child(_time)
	top.add_child(col)
	# pause button left of the minimap (the minimap box is drawn in _draw)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	_pause = Ui.button("II", false, 34)
	_pause.custom_minimum_size = Vector2(Ui.MIN_TOUCH, Ui.MIN_TOUCH)
	_pause.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause.pressed.connect(func() -> void: pause_pressed.emit())
	top.add_child(_pause)
	var map_gap: Control = Control.new()
	map_gap.custom_minimum_size = Vector2(MINIMAP_SIZE + 30.0 + 12.0 - 24.0 + 16.0, 0)
	map_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(map_gap)
	_center = Ui.label("", 140, Ui.ACCENT)
	_center.set_anchors_preset(Control.PRESET_CENTER)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.position = Vector2(-300, -170)
	_center.size = Vector2(600, 160)
	add_child(_center)
	_banner = Ui.label("", 40, Color(1, 0.55, 0.35))
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-400, 150)
	_banner.size = Vector2(800, 60)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_banner)
	_pill = Ui.label("Reconnecting…", 24)
	_pill.position = Vector2(540, 20)
	add_child(_pill)


func setup(v: RaceView, race_laps: int) -> void:
	view = v
	laps = race_laps
	_build_minimap()


func _build_minimap() -> void:
	_map_pts.clear()
	if view == null or view.track == null:
		return
	var tr: Track = view.track
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	var raw: PackedVector2Array = PackedVector2Array()
	for i: int in 160:
		var smp: Track.Sample = tr.at(tr.length * float(i) / 160.0)
		var p: Vector2 = Vector2(smp.px, smp.pz)
		raw.append(p)
		lo = lo.min(p)
		hi = hi.max(p)
	var k: float = MINIMAP_SIZE / maxf(hi.x - lo.x, hi.y - lo.y)
	_map_size = (hi - lo) * k
	_map_xform = Transform2D(0.0, Vector2(k, k), 0.0, -lo * k)
	for p: Vector2 in raw:
		_map_pts.append(_map_xform * p)
	_map_pts.append(_map_pts[0])


func banner(text: String) -> void:
	_banner.text = text
	_banner_t = 1.6


func _process(delta: float) -> void:
	_banner_t -= delta
	_banner.visible = _banner_t > 0.0
	if view == null or view.interp == null:
		return
	var me: int = view.follow
	var st: Physics.CarState = view.state_of(me)
	var n: int = view.cars.size()
	var p: int = view.position_of(me)
	_pos.text = ("%d/%d" % [p, n]) if p > 0 else "–/%d" % n
	if st != null:
		_lap.text = "LAP %d/%d" % [clampi(st.lap + 1, 1, laps), laps]
	var t: float = view.race_time()
	if t < 0.0 and t > -10.0:
		var k: int = int(ceil(-t))
		_set_center(str(k), COUNT_COLORS[clampi(k, 1, 3) - 1])
		_go_flash = 0.8
	elif _go_flash > 0.0:
		_set_center("GO!", Color(0.3, 1.0, 0.4))
		_go_flash -= delta
	elif view.finished(me):
		_set_center("FINISH", Ui.ACCENT)
	else:
		_set_center("", Ui.ACCENT)
	if t >= 0.0:
		_time.text = "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]
	_pill.visible = reconnecting
	queue_redraw()


## Countdown/finish text: each new value punches in (big → normal, back-eased).
func _set_center(text: String, color: Color) -> void:
	if text == _center.text:
		return
	_center.text = text
	_center.add_theme_color_override("font_color", color)
	if text == "":
		return
	_center.pivot_offset = _center.size / 2.0
	_center.scale = Vector2(1.9, 1.9)
	_center.modulate.a = 0.4
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_center, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_center, "modulate:a", 1.0, 0.15)


func _draw() -> void:
	if view == null or view.track == null:
		return
	var vp: Vector2 = get_viewport_rect().size
	var ins: Vector4 = Ui.safe_insets(self)
	# minimap, top-right; the backing follows the track's own shape (wide maps get a wide, low box)
	var origin: Vector2 = Vector2(vp.x - ins.z - 30.0 - _map_size.x, ins.y + 24.0)
	if _map_box == null:
		_map_box = StyleBoxFlat.new()
		_map_box.bg_color = Color(0.02, 0.03, 0.1, 0.38)
		_map_box.set_corner_radius_all(14)
	draw_style_box(_map_box, Rect2(origin - Vector2(14, 14), _map_size + Vector2(28, 28)))
	if _map_pts.size() > 1:
		var shifted: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in _map_pts:
			shifted.append(p + origin)
		draw_polyline(shifted, Color(1, 1, 1, 0.8), 4.0, true)
	for i: int in view.cars.size():
		var st: Physics.CarState = view.state_of(i)
		if st == null:
			continue
		var smp: Track.Sample = view.track.at(st.s)
		var dot: Vector2 = origin + _map_xform * Vector2(smp.px, smp.pz)
		var col: Color = Color.html(GameData.vehicle(view.cars[i].vehicle_id).get("color", "#ffffff") as String)
		draw_circle(dot, 9.0 if i == view.follow else 6.0, col)
		if i == view.follow:
			draw_arc(dot, 11.0, 0, TAU, 20, Color.WHITE, 2.0)
	# name tags for the nearest cars ahead of the camera
	var cam: Camera3D = view.camera()
	var tags: Array = []
	const TAG_RANGE: float = 80.0
	for i: int in view.cars.size():
		if i == view.follow or view.state_of(i) == null:
			continue
		var wp: Vector3 = view.cars[i].global_position + Vector3.UP * 2.0
		if cam.is_position_behind(wp) or cam.global_position.distance_to(wp) > TAG_RANGE:
			continue
		tags.append([cam.global_position.distance_to(wp), i, wp])
	tags.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var used: Array[Rect2] = []
	var shown: int = 0
	for k: int in tags.size():
		if shown >= TAG_MAX:
			break
		var i: int = int(tags[k][1])
		var sp: Vector2 = cam.unproject_position(tags[k][2] as Vector3)
		var r: Rect2 = Rect2(sp + Vector2(-80, -20), Vector2(160, 26))
		var overlaps: bool = false
		for u: Rect2 in used:
			if u.intersects(r):
				overlaps = true
		if overlaps:
			continue
		used.append(r)
		shown += 1
		var gd: Dictionary = view.grid[i] as Dictionary
		var name: String = Profile.display_name(str(gd["playerId"]), str(gd["name"]))
		draw_string(ThemeDB.fallback_font, sp + Vector2(-80, 0), name, HORIZONTAL_ALIGNMENT_CENTER, 160, 20, Color(1, 1, 1, 0.9))
