extends Node

## Graphics tiers (GAME_PLAN §4.2, §8). Autoload "Quality".
## Start tier from the device model (iPhone 11 = low; newer = high), then adapt at runtime:
## rolling frame time → step render scale → drop tier; raise slowly with headroom.
## High tier on ProMotion targets 120 fps when frame time allows. Manual: Auto / High / Low.

signal tier_changed(tier: String)

const LOW: String = "low"
const HIGH: String = "high"

var tier: String = HIGH
var render_scale: float = 1.0
var target_fps: int = 60
var _avg_ms: float = 16.0
var _cooldown: float = 3.0


static func model_tier(model: String) -> String:
	# iPhoneXX,Y — A13 (iPhone 11 family) is iPhone12,x; SE 2nd gen is iPhone12,8
	if model.begins_with("iPhone"):
		var major: int = model.trim_prefix("iPhone").get_slice(",", 0).to_int()
		return LOW if major <= 12 else HIGH
	return HIGH


func _ready() -> void:
	var setting: String = str(Profile.get_value("quality", "auto"))
	tier = setting if setting in [LOW, HIGH] else model_tier(OS.get_model_name())
	var refresh: float = DisplayServer.screen_get_refresh_rate()
	target_fps = 120 if tier == HIGH and refresh > 100.0 else 60
	Engine.max_fps = target_fps
	render_scale = 1.0 if tier == HIGH else 0.8
	_apply()


func _apply() -> void:
	var vp: Viewport = get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale
	vp.msaa_3d = Viewport.MSAA_2X if tier == HIGH else Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(4096 if tier == HIGH else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW if tier == HIGH else RenderingServer.SHADOW_QUALITY_HARD)
	tier_changed.emit(tier)


## Environment/light settings per tier (called by TrackBuilder output owners).
func configure_environment(env: Environment, sun: DirectionalLight3D) -> void:
	env.glow_enabled = env.glow_enabled and tier == HIGH
	sun.shadow_enabled = tier == HIGH
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 3.0 # curved glossy car bodies showed self-shadow acne (shimmer/flicker)


func _process(delta: float) -> void:
	if str(Profile.get_value("quality", "auto")) != "auto":
		return
	_avg_ms = lerpf(_avg_ms, delta * 1000.0, 0.05)
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var budget_ms: float = 1000.0 / float(target_fps)
	if _avg_ms > budget_ms * 1.15:
		_cooldown = 2.0
		if target_fps > 60:
			target_fps = 60 # first give up 120 Hz
			Engine.max_fps = 60
		elif render_scale > 0.7:
			render_scale = maxf(render_scale - 0.1, 0.7)
			_apply()
		elif tier == HIGH:
			tier = LOW
			_apply()
	elif _avg_ms < budget_ms * 0.7 and render_scale < (1.0 if tier == HIGH else 0.85):
		_cooldown = 6.0 # raise slowly
		render_scale = minf(render_scale + 0.05, 1.0)
		_apply()


func avg_frame_ms() -> float:
	return _avg_ms
