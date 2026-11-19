extends GdUnitTestSuite

## TrackBuilder produces the expected parts for every map (headless smoke test).


func test_builds_every_map() -> void:
	for map_id: String in GameData.map_ids():
		var tr: Track = Track.load_map(map_id)
		var root: Node3D = auto_free(TrackBuilder.build(tr)) as Node3D
		for part: String in ["Road", "Curbs", "Walls", "StartLine", "StartGate", "Ground", "Scenery", "Lighting"]:
			assert_object(root.get_node_or_null(part)).override_failure_message("%s: missing %s" % [map_id, part]).is_not_null()
		var road: MeshInstance3D = root.get_node("Road") as MeshInstance3D
		assert_int(road.mesh.get_surface_count()).is_equal(1)
		# the road surface faces up (winding matters: down-facing faces are culled)
		var arrays: Array = road.mesh.surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var up: int = 0
		for nrm: Vector3 in normals:
			if nrm.y > 0.5:
				up += 1
		assert_float(float(up) / float(normals.size())).override_failure_message("%s: road normals not up" % map_id).is_greater(0.95)
		if map_id == "neon":
			assert_object(root.get_node_or_null("Pillars")).is_not_null()
		if map_id == "frosty":
			assert_object(root.get_node_or_null("Ramps")).is_not_null()
