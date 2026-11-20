extends Node3D

## Dev scene: all 8 cars as the game renders them (sunny-day light, sky reflections, shadows),
## for art reviews. Run windowed with DevTools' --shot:
##   Godot --path godot res://src/testing/CarLineup.tscn -- --shot out.png [--car bolt] [--angle 35]
## --car frames one car close up; --angle turns the camera around it (degrees, 0 = front).

func _ready() -> void:
	var args: PackedStringArray = Config.user_args()
	var env: Environment = Environment.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.55, 0.9)
	sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.95)
	sky_mat.ground_horizon_color = Color(0.6, 0.66, 0.6)
	sky_mat.ground_bottom_color = Color(0.25, 0.3, 0.22)
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 3.0
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.33, 0.36)
	gm.roughness = 0.85
	ground.material_override = gm
	add_child(ground)
	get_viewport().msaa_3d = Viewport.MSAA_4X

	var only: String = ""
	var ci: int = args.find("--car")
	if ci >= 0 and ci + 1 < args.size():
		only = args[ci + 1]
	var angle: float = 35.0
	var ai: int = args.find("--angle")
	if ai >= 0 and ai + 1 < args.size():
		angle = args[ai + 1].to_float()
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.current = true
	var vs: Array = GameData.vehicles()
	var i: int = 0
	for v: Variant in vs:
		var id: String = (v as Dictionary)["id"] as String
		if only != "" and id != only:
			continue
		var car: CarView = (load("res://src/render/CarView.tscn") as PackedScene).instantiate() as CarView
		add_child(car)
		car.force_lod0 = true
		car.configure(id, id, false)
		car.position = Vector3(-10.5 + (i % 4) * 7.0, CarView.RIDE_HEIGHT, -(i / 4) * 8.0) if only == "" else Vector3(0, CarView.RIDE_HEIGHT, 0)
		car.rotation.y = deg_to_rad(-30.0) if only == "" else 0.0
		i += 1
	if only == "":
		cam.fov = 40.0
		cam.position = Vector3(0, 9, 16)
		cam.look_at(Vector3(0, 0.6, -4))
	else:
		cam.fov = 35.0
		var a: float = deg_to_rad(angle)
		# car faces −Z (CarView forward); angle 0 = looking at the front
		cam.position = Vector3(sin(a) * 7.0, 2.2, -cos(a) * 7.0)
		cam.look_at(Vector3(0, 0.7, 0))
