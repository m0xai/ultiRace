extends GdUnitTestSuite

## Device → tier mapping (GAME_PLAN §4.2: iPhone 11 family low, newer high).


func test_model_tiers() -> void:
	var q: GDScript = load("res://src/render/Quality.gd") as GDScript
	assert_str(q.call("model_tier", "iPhone12,1") as String).is_equal("low") # iPhone 11
	assert_str(q.call("model_tier", "iPhone12,8") as String).is_equal("low") # SE 2nd gen
	assert_str(q.call("model_tier", "iPhone16,2") as String).is_equal("high") # 15 Pro Max
	assert_str(q.call("model_tier", "iPhone14,7") as String).is_equal("high") # iPhone 14
	assert_str(q.call("model_tier", "MacBookPro18,1") as String).is_equal("high")
