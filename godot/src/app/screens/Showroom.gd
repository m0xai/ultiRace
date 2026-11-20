class_name Showroom
extends SubViewportContainer

## 3D car showroom for menus (A2): the real car model turning slowly on a glowing platform,
## in its own small world (transparent background, so the screen gradient shows through).
## show_car(id) swaps the model with a little drop-in bounce.

const SPIN_SPEED: float = 0.45 # rad/s

var _vp: SubViewport
var _pivot: Node3D
var _car: CarView = null
var _car_id: String = ""
var _pending: String = ""


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE # no cost while racing
	add_child(_vp)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.85)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.adjustment_enabled = true # same grade as the tracks (AgX alone looked washed out)
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.2
	# reflections only (background stays transparent): chrome and paint need something to mirror
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.5, 0.85)
	sky_mat.sky_horizon_color = Color(0.85, 0.88, 0.95)
	sky_mat.ground_horizon_color = Color(0.5, 0.52, 0.6)
	sky_mat.ground_bottom_color = Color(0.12, 0.13, 0.2)
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	e.sky = sky
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.environment = e
	_vp.add_child(env)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -35, 0)
	key.light_energy = 1.5
	key.shadow_enabled = true
	_vp.add_child(key)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.8
	rim.light_color = Color(0.7, 0.8, 1.0)
	_vp.add_child(rim)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 35.0
	cam.position = Vector3(0, 2.6, 8.2)
	cam.rotation_degrees = Vector3(-14, 0, 0)
	_vp.add_child(cam)
	var plat: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 2.9
	cyl.bottom_radius = 3.0
	cyl.height = 0.18
	cyl.radial_segments = 48
	plat.mesh = cyl
	plat.position = Vector3(0, -0.09, 0)
	var pm: StandardMaterial3D = StandardMaterial3D.new()
	pm.albedo_color = Color(0.16, 0.2, 0.42)
	pm.metallic = 0.3
	pm.roughness = 0.35
	pm.emission_enabled = true
	pm.emission = Color(0.1, 0.18, 0.5)
	plat.material_override = pm
	_vp.add_child(plat)
	var ring: MeshInstance3D = MeshInstance3D.new()
	var tor: TorusMesh = TorusMesh.new()
	tor.inner_radius = 2.9
	tor.outer_radius = 3.04
	tor.rings = 48
	ring.mesh = tor
	var rm: StandardMaterial3D = StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Ui.ACCENT
	ring.material_override = rm
	_vp.add_child(ring)
	_pivot = Node3D.new()
	_pivot.rotation.y = 0.6
	_vp.add_child(_pivot)


func _ready() -> void:
	if _pending != "":
		show_car(_pending)


func show_car(vehicle_id: String) -> void:
	if not is_inside_tree(): # CarView needs its @onready nodes: wait until we are in the tree
		_pending = vehicle_id
		return
	if vehicle_id == _car_id:
		return
	_car_id = vehicle_id
	if _car != null:
		_car.queue_free()
	_car = (load("res://src/render/CarView.tscn") as PackedScene).instantiate() as CarView
	_pivot.add_child(_car)
	_car.configure(vehicle_id, "", false)
	# CarView's origin sits RIDE_HEIGHT above the road (its model is offset down by that)
	_car.position = Vector3(0, CarView.RIDE_HEIGHT + 0.9, 0)
	var tw: Tween = _car.create_tween()
	tw.tween_property(_car, "position:y", CarView.RIDE_HEIGHT, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_pivot.rotation.y = fmod(_pivot.rotation.y + SPIN_SPEED * delta, TAU)
