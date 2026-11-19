extends Node

## Dev helpers driven by user command-line args (after `--`):
##   --shot <path.png> [--shot-delay <seconds>]  save a viewport screenshot, then quit.
## Used by `make screenshot` so Claude can check visuals without a human.

const DEFAULT_DELAY_S: float = 2.0

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
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
	get_tree().quit(0 if err == OK else 1)
