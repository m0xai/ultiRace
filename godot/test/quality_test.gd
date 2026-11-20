extends GdUnitTestSuite

## Device → tier mapping (GAME_PLAN §4.2: iPhone 11 family low, newer high).


func test_model_tiers() -> void:
	var q: GDScript = load("res://src/render/Quality.gd") as GDScript
	assert_str(q.call("model_tier", "iPhone12,1") as String).is_equal("low") # iPhone 11
	assert_str(q.call("model_tier", "iPhone12,8") as String).is_equal("low") # SE 2nd gen
	assert_str(q.call("model_tier", "iPhone16,2") as String).is_equal("high") # 15 Pro Max
	assert_str(q.call("model_tier", "iPhone14,7") as String).is_equal("high") # iPhone 14
	assert_str(q.call("model_tier", "MacBookPro18,1") as String).is_equal("high")


func _q() -> Node:
	var q: Node = auto_free((load("res://src/render/Quality.gd") as GDScript).new()) as Node
	q.set("target_fps", 120)
	q.set("_avg_ms", 8.0)
	return q


func test_loading_hitch_does_not_downgrade() -> void:
	var q: Node = _q()
	q.call("step_adapt", 1.2) # track build at race start
	for i: int in 240:
		q.call("step_adapt", 1.0 / 120.0)
	assert_int(int(q.get("target_fps"))).is_equal(120)
	Engine.max_fps = 0


func test_sustained_slowness_drops_to_60_once() -> void:
	var q: Node = _q()
	for i: int in 200: # ~4 s at 50 fps
		q.call("step_adapt", 0.02)
	assert_int(int(q.get("target_fps"))).is_equal(60)
	assert_float(float(q.get("render_scale"))).is_equal(1.0) # not stepped further yet
	Engine.max_fps = 0
