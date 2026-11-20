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
	# 4 wheels per detail level (LOD0 + LOD1 both animate, so switching never shows a jump)
	assert_int(cv._wheels.size()).is_equal(8)
	assert_int(cv._front.size()).is_equal(4)
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
