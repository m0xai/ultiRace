extends GdUnitTestSuite

## CarView places the car (and its tag) at the track-space position.


func test_car_and_tag_follow_state() -> void:
	var tr: Track = Track.load_map("sunny")
	var root: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(root)
	var cv: CarView = (load("res://src/render/CarView.tscn") as PackedScene).instantiate() as CarView
	root.add_child(cv)
	cv.configure("bolt", "Tester", true)
	var st: Physics.CarState = Physics.CarState.new()
	st.s = 500.0
	st.d = 3.0
	cv.show_state(st, tr)
	var want: Vector3 = tr.world(500.0, 3.0, CarView.RIDE_HEIGHT)
	assert_float(cv.global_position.distance_to(want)).is_less(0.01)
	var tag: Node3D = cv.get_node("Tag") as Node3D
	assert_float(tag.global_position.distance_to(want)).is_less(3.0)
	# forward axis points along the track tangent
	var smp: Track.Sample = tr.at(500.0)
	var fwd: Vector3 = -cv.global_transform.basis.z
	assert_float(fwd.dot(Vector3(smp.tx, smp.ty, smp.tz))).is_greater(0.99)


## Regression (2026-11-20, seen on device): wheels must spin around the axle only — no tumbling.
func test_wheels_spin_around_axle_only() -> void:
	var tr: Track = Track.load_map("sunny")
	var root: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(root)
	var cv: CarView = (load("res://src/render/CarView.tscn") as PackedScene).instantiate() as CarView
	root.add_child(cv)
	cv.configure("bolt", "Tester", true)
	# 4 wheels per detail level (high, mid, light all animate, so switching never shows a jump)
	assert_int(cv._wheels.size()).is_equal(12)
	assert_int(cv._front.size()).is_equal(6)
	var st: Physics.CarState = Physics.CarState.new()
	for i: int in 90:
		st.s = 100.0 + float(i) * 1.1
		st.yaw_rel = 0.2 * sin(float(i) * 0.3)
		cv.show_state(st, tr)
	for w: Node3D in cv._wheels:
		var delta_rot: Basis = w.basis * (cv._rest[w] as Basis).inverse()
		var axle: Vector3 = delta_rot * Vector3.RIGHT
		if cv._front.has(w):
			assert_float(absf(axle.y)).override_failure_message("front axle tilted %s" % axle).is_less(1e-4)
		else:
			assert_float(axle.distance_to(Vector3.RIGHT)).override_failure_message("rear axle moved %s" % axle).is_less(1e-4)


## Detail levels: own car shows the high model; a far-away car shows the light one, which also
## casts the shadow (the finer levels never do).
func test_lod_levels() -> void:
	var tr: Track = Track.load_map("sunny")
	var root: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(root)
	var cam: Camera3D = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var own: CarView = (load("res://src/render/CarView.tscn") as PackedScene).instantiate() as CarView
	root.add_child(own)
	own.configure("bolt", "Me", true)
	var far: CarView = (load("res://src/render/CarView.tscn") as PackedScene).instantiate() as CarView
	root.add_child(far)
	far.configure("rhino", "Bot", false)
	var st: Physics.CarState = Physics.CarState.new()
	st.s = 100.0
	own.show_state(st, tr)
	cam.global_position = own.global_position + Vector3(0, 3, 6)
	var st2: Physics.CarState = Physics.CarState.new()
	st2.s = 300.0
	far.show_state(st2, tr)
	assert_int(own._lod).is_equal(0)
	assert_int(far._lod).is_equal(2)
	for m: MeshInstance3D in far._lods[2]:
		assert_bool(m.visible).is_true()
		assert_int(m.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	for m: MeshInstance3D in far._lods[1]:
		assert_bool(m.visible).is_false()
	for m: MeshInstance3D in own._lods[0]:
		assert_int(m.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
