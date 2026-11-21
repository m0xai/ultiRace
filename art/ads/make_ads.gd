extends Control
## Renders the roadside ad boards (fictional brands only) to godot/assets/env/ads/ad<i>.png.
## Run (windowed, needs the renderer):
##   cp art/ads/make_ads.gd godot/ && Godot --path godot --resolution 1024x512 res://make_ads.tscn
## (see HANDOFF.md / graphics pass 5). 1024×512 each, 2:1 like the boards.

const ADS: Array = [
	# [top colour, bottom colour, accent, headline, tagline, motif]
	[Color(0.08, 0.1, 0.3), Color(0.15, 0.3, 0.75), Color(1.0, 0.76, 0.08), "ULTIRACE", "8 CARS · 8 ULTS · GO!", "flag"],
	[Color(0.95, 0.45, 0.05), Color(0.85, 0.1, 0.1), Color(1, 1, 1), "TURBO JUICE", "FUEL FOR THE FAST", "bolt"],
	[Color(0.1, 0.1, 0.12), Color(0.25, 0.25, 0.3), Color(1.0, 0.82, 0.1), "GRIP+ TYRES", "STICK TO EVERY CORNER", "tyre"],
	[Color(0.75, 0.05, 0.25), Color(0.35, 0.02, 0.2), Color(0.4, 1.0, 0.9), "NITRO COLA", "ICE COLD · EXTRA FIZZ", "bubbles"],
	[Color(0.75, 0.88, 1.0), Color(0.3, 0.55, 0.9), Color(1, 1, 1), "SNOWCAP CHAINS", "WINTER? NO PROBLEM", "flake"],
	[Color(0.98, 0.75, 0.35), Color(0.75, 0.35, 0.15), Color(0.15, 0.08, 0.05), "DUNE OIL", "SMOOTH AS SAND", "drop"],
]

var _i: int = 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/env/ads"))
	for i: int in ADS.size():
		_i = i
		queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.resize(1024, 512, Image.INTERPOLATE_LANCZOS)
		img.save_png("res://assets/env/ads/ad%d.png" % i)
	get_tree().quit()


func _draw() -> void:
	var sz: Vector2 = get_viewport_rect().size
	var a: Array = ADS[_i]
	var top: Color = a[0]
	var bot: Color = a[1]
	var acc: Color = a[2]
	for y: int in int(sz.y):
		draw_line(Vector2(0, y), Vector2(sz.x, y), top.lerp(bot, float(y) / sz.y))
	# diagonal speed stripes
	for k: int in 6:
		var x0: float = sz.x * 0.55 + k * 70.0
		draw_colored_polygon(PackedVector2Array([Vector2(x0, sz.y), Vector2(x0 + 40, sz.y), Vector2(x0 + 260, 0), Vector2(x0 + 220, 0)]),
			Color(1, 1, 1, 0.07))
	var font: Font = load("res://assets/fonts/ui_font.tres") as Font
	var head: String = a[3]
	var hs: int = 150 if head.length() <= 10 else 112
	var w: float = font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
	var pos: Vector2 = Vector2(60, sz.y * 0.55)
	draw_string_outline(font, pos + Vector2(6, 8), head, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, 18, Color(0, 0, 0, 0.35))
	draw_string_outline(font, pos, head, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, 14, Color(0, 0, 0, 0.6))
	draw_string(font, pos, head, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, acc)
	draw_string(font, Vector2(64, sz.y * 0.78), a[4], HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(1, 1, 1, 0.92))
	draw_rect(Rect2(60, sz.y * 0.6, minf(w, sz.x * 0.62), 10), acc)
	var c: Vector2 = Vector2(sz.x * 0.84, sz.y * 0.45)
	match str(a[5]):
		"flag":
			for yy: int in 5:
				for xx: int in 5:
					var col: Color = Color.WHITE if (xx + yy) % 2 == 0 else Color(0.05, 0.05, 0.08)
					draw_rect(Rect2(c + Vector2(-110 + xx * 44, -110 + yy * 44), Vector2(44, 44)), col)
		"bolt":
			draw_colored_polygon(PackedVector2Array([c + Vector2(20, -130), c + Vector2(-70, 15), c + Vector2(-5, 15), c + Vector2(-30, 130),
				c + Vector2(70, -25), c + Vector2(5, -25)]), acc)
		"tyre":
			draw_circle(c, 125, Color(0.05, 0.05, 0.06))
			draw_circle(c, 80, Color(0.75, 0.77, 0.8))
			draw_circle(c, 30, Color(0.3, 0.3, 0.33))
			for k: int in 16:
				var ang: float = TAU * k / 16.0
				draw_line(c + Vector2.from_angle(ang) * 92, c + Vector2.from_angle(ang) * 122, Color(0.2, 0.2, 0.22), 10)
		"bubbles":
			for k: int in 12:
				var p: Vector2 = c + Vector2(sin(k * 2.3) * 90, cos(k * 1.7) * 110)
				draw_arc(p, 14 + (k % 4) * 9, 0, TAU, 32, acc, 5, true)
		"flake":
			for k: int in 3:
				var d: Vector2 = Vector2.from_angle(PI / 2 + k * PI / 3) * 120
				draw_line(c - d, c + d, acc, 14, true)
		"drop":
			var pts: PackedVector2Array = PackedVector2Array()
			for k: int in 33:
				var t: float = TAU * k / 32.0
				pts.append(c + Vector2(sin(t) * 85 * (1.0 - 0.5 * maxf(-cos(t), 0.0)), -(40 - cos(t) * 100 * (0.7 + 0.3 * absf(sin(t * 0.5))))))
			draw_colored_polygon(pts, acc)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.9), false, 12)
