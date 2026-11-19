extends Node

## Dev helpers driven by user command-line args (after `--`):
##   --shot <path.png> [--shot-delay <seconds>]  save a viewport screenshot, then quit.
## Used by `make screenshot` so Claude can check visuals without a human.

const DEFAULT_DELAY_S: float = 2.0

func _ready() -> void:
	var args: PackedStringArray = Config.user_args()
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
	get_tree().quit(0 if err == OK else 1)
