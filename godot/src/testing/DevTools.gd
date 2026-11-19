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
