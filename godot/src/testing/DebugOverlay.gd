extends CanvasLayer

## Dev overlay (GAME_PLAN §8): FPS, frame ms, draw calls, triangles, tier, render scale, ping,
## kbps. Toggle: triple-tap with two fingers (or F3). Debug builds only.

var _label: Label
var _taps: Array[float] = []
var _fingers: Dictionary = {}
var conn: Connection = null
var _last_bytes: int = 0
var _kbps: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(12, 640)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	visible = OS.is_debug_build() and Config.user_args().has("--overlay")


func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_F3:
		visible = not visible
	elif event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		if t.pressed:
			_fingers[t.index] = true
			if _fingers.size() == 2:
				var now: float = Time.get_ticks_msec() / 1000.0
				_taps.append(now)
				while _taps.size() > 0 and now - _taps[0] > 0.8:
					_taps.remove_at(0)
				if _taps.size() >= 3:
					_taps.clear()
					visible = not visible
		else:
			_fingers.erase(t.index)


func _process(delta: float) -> void:
	_t += delta
	if conn != null and _t >= 1.0:
		_kbps = float(conn.bytes_in - _last_bytes) * 8.0 / 1000.0 / _t
		_last_bytes = conn.bytes_in
		_t = 0.0
	if not visible:
		return
	_label.text = "FPS %d  frame %.1f ms  draws %d  tris %dk  tier %s  scale %.2f  ping %d ms  down %.1f kbps" % [
		Engine.get_frames_per_second(), Quality.avg_frame_ms(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
		Quality.tier, Quality.render_scale, conn.ping_ms if conn != null else 0, _kbps]
