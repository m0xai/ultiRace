extends Node

## Dev helpers driven by user command-line args (after `--`):
##   --shot <path.png> [--shot-delay <seconds>]  save a viewport screenshot, then quit.
## Used by `make screenshot` so Claude can check visuals without a human.

const DEFAULT_DELAY_S: float = 2.0

## iPhone 11 projection (`--iphone11`, `make iphone11`): the game runs at the iPhone 11's pixel
## size, safe area, model id (→ low tier) and 60 Hz; this Mac's measured GPU/CPU time per frame is
## scaled to the A13 with published benchmarks (research 2026-11-20, docs/IPHONE11_SIM.md):
##   GPU: GFXBench Aztec Ruins High offscreen — A13 ≈ 31 fps, M2 Pro 16-core ≈ 181 fps → ×5.8
##   sustained: iPhone 11 throttles to ≈ 52–72 % of peak in long GPU loads (3DMark Wild Life
##   stress) → peak ÷ 0.62
##   CPU: ×1.6 (single-core gap A13 vs M2 Pro, estimate)
const IP11_GPU_RATIO: float = 5.8
const IP11_SUSTAINED: float = 0.62
const IP11_CPU_RATIO: float = 1.6
const IP11_SIZE: Vector2i = Vector2i(1792, 828)

var _ip11: bool = false
var _feel: bool = false
var _acc: Dictionary = {"n": 0, "gpu": 0.0, "cpu": 0.0, "gpu_max": 0.0}
var _report_t: float = 0.0
var _frame_start_us: int = 0
var _logic_ms: float = 0.0 # last frame: process start → render start (game logic, scripts, physics)


func _ready() -> void:
	var args: PackedStringArray = Config.user_args()
	_ip11 = args.has("--iphone11")
	_feel = args.has("--ip11-feel")
	if _ip11:
		DisplayServer.window_set_size(IP11_SIZE)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		get_tree().process_frame.connect(func() -> void: _frame_start_us = Time.get_ticks_usec())
		RenderingServer.frame_pre_draw.connect(func() -> void:
			if _frame_start_us > 0:
				_logic_ms = float(Time.get_ticks_usec() - _frame_start_us) / 1000.0)
		var rs: String = Config.arg("--render-scale", "")
		if rs != "": # e.g. 0.7 = what adaptive quality steps down to on a hot phone
			(func() -> void:
				var q: Node = get_node("/root/Quality")
				q.set("render_scale", rs.to_float())
				q.call("_apply")).call_deferred()
		if not _feel: # measure: render as fast as possible (no vsync / fps cap) → real frame cost
			(func() -> void:
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)).call_deferred()
		(func() -> void: print("IPHONE11 emulation: %s px, model %s, safe area %s px, tier %s" % [IP11_SIZE, Config.model_name(),
			Config.safe_area_override(), get_node("/root/Quality").get("tier")])).call_deferred()
	_shot_flow(args)


func _process(delta: float) -> void:
	if not _ip11:
		return
	var rid: RID = get_viewport().get_viewport_rid()
	var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var cpu: float = _logic_ms
	if gpu <= 0.0:
		# no GPU timer on this renderer: the rest of the uncapped frame (render submission + GPU)
		# counts as GPU work (slightly pessimistic: render-thread CPU is scaled like the GPU)
		if _feel or delta > 0.25:
			return
		gpu = maxf(delta * 1000.0 - cpu, 0.1)
	_acc["n"] = int(_acc["n"]) + 1
	_acc["gpu"] = float(_acc["gpu"]) + gpu
	_acc["cpu"] = float(_acc["cpu"]) + cpu
	_acc["gpu_max"] = maxf(float(_acc["gpu_max"]), gpu)
	_report_t += delta
	if _report_t >= 2.0:
		_report_t = 0.0
		var p: Dictionary = ip11_projection()
		print("IP11 mac gpu %.2f cpu %.2f ms | iPhone 11 gpu %.1f (sustained %.1f) cpu %.1f ms → %d fps (sustained %d) | draws %d tris %d" % [
			p["mac_gpu"], p["mac_cpu"], p["gpu"], p["gpu_sus"], p["cpu"], p["fps"], p["fps_sus"],
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		if _feel: # play at the projected sustained iPhone 11 frame rate
			Engine.max_fps = clampi(int(p["fps_sus"]), 15, 60)
		_acc = {"n": 0, "gpu": 0.0, "cpu": 0.0, "gpu_max": float(_acc["gpu_max"])}


## Average of the last window: Mac ms, projected iPhone 11 ms and fps (capped at 60 Hz).
func ip11_projection() -> Dictionary:
	var n: int = maxi(int(_acc["n"]), 1)
	var mg: float = float(_acc["gpu"]) / n
	var mc: float = float(_acc["cpu"]) / n
	var g: float = mg * IP11_GPU_RATIO
	var gs: float = g / IP11_SUSTAINED
	var c: float = mc * IP11_CPU_RATIO
	return {"mac_gpu": mg, "mac_cpu": mc, "gpu": g, "gpu_sus": gs, "cpu": c,
		"fps": mini(60, int(1000.0 / maxf(maxf(g, c), 0.001))), "fps_sus": mini(60, int(1000.0 / maxf(maxf(gs, c), 0.001)))}


func _shot_flow(args: PackedStringArray) -> void:
	var shot_i: int = args.find("--shot")
	if shot_i < 0 or shot_i + 1 >= args.size():
		return
	var path: String = args[shot_i + 1]
	var delay: float = DEFAULT_DELAY_S
	var delay_i: int = args.find("--shot-delay")
	if delay_i >= 0 and delay_i + 1 < args.size():
		delay = args[delay_i + 1].to_float()
	await get_tree().create_timer(delay).timeout
	var bi: int = args.find("--burst")
	if bi >= 0 and bi + 1 < args.size():
		# consecutive frames path_0.png … path_{n-1}.png (frame-to-frame artefacts like flicker)
		var frames: Array[Image] = []
		var times: PackedFloat64Array = []
		for k: int in args[bi + 1].to_int():
			await RenderingServer.frame_post_draw
			frames.append(get_viewport().get_texture().get_image()) # keep in memory: no stalls between frames
			times.append(Time.get_ticks_usec() / 1000.0)
		for k: int in frames.size():
			frames[k].save_png(path.get_basename() + "_%d.png" % k)
		print("BURST saved, frame times ms: ", times)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(path)
	print("SCREENSHOT %s err=%d size=%s" % [path, err, img.get_size()])
	# Render budget check (GAME_PLAN §8): draw calls and triangles of the captured frame.
	var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objs: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	print("PERF draw_calls=%d primitives=%d objects=%d fps=%d" % [draws, prims, objs, Engine.get_frames_per_second()])
	if _ip11:
		var p: Dictionary = ip11_projection()
		var rv: Node = get_tree().root.find_child("RaceView", true, false)
		var map_id: String = str(rv.get("track").get("id")) if rv != null and rv.get("track") != null else "?"
		print("IP11_SUMMARY map=%s mac_gpu=%.2f mac_cpu=%.2f ip11_gpu=%.1f ip11_gpu_sustained=%.1f ip11_cpu=%.1f fps=%d fps_sustained=%d draws=%d tris=%d" % [
			map_id, p["mac_gpu"], p["mac_cpu"], p["gpu"], p["gpu_sus"], p["cpu"], p["fps"], p["fps_sus"], draws, prims])
	get_tree().quit(0 if err == OK else 1)
