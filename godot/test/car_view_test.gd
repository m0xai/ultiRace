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
