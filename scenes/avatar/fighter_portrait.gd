class_name FighterPortrait
extends SubViewport
## Static standby replica: shares mesh/skin resources, never follows arena actions.
var fighter: VrmFighter
var camera: Camera3D
var _activity: RefCounted
var _standby_actor: Node3D
var _standby_skeleton: Skeleton3D

func _init() -> void:
	size = Vector2i(144,144)
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)
	camera = Camera3D.new()
	camera.fov = 30
	camera.cull_mask = 1
	# Portrait lighting stays readable across all three locations.
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.85,.9,1)
	environment.ambient_light_energy = .7
	camera.environment = environment
	add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -25, 0)
	light.light_energy = 0.7
	add_child(light)

func bind(value: VrmFighter,side: int) -> void:
	fighter = value
	# Arena fill lights already target these two actor layers; keep that contract.
	for mesh in fighter.meshes: mesh.layers = 1 << (18 + side)
	if is_instance_valid(_standby_actor):
		ModelLifetime.release(_standby_actor, get_tree())
	# Duplicate nodes only: no GLB/setup, animation callbacks or secondary motion.
	_standby_actor = fighter.actor.duplicate(0) as Node3D
	_standby_actor.name = "StandbyPortraitActor"
	_standby_actor.position = Vector3.ZERO
	_standby_actor.visible = true
	_standby_actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_standby_actor)
	_standby_skeleton = replica_node(fighter.skeleton) as Skeleton3D
	fighter.sample_standby_skeleton(_standby_skeleton)
	var portrait_meshes: Array[MeshInstance3D] = []
	for source in fighter.meshes:
		var mesh := replica_node(source) as MeshInstance3D
		mesh.layers = 1
		for shape in mesh.get_blend_shape_count(): mesh.set_blend_shape_value(shape, 0.0)
		portrait_meshes.append(mesh)
	fighter.apply_profile_face_to(portrait_meshes)
	_update_camera()
	if _activity != null: _activity.sync()
	else:
		# Isolated captures may bind without a UI consumer. Match HUD always watches one.
		render_target_update_mode = SubViewport.UPDATE_ALWAYS
		set_process(true)


## Runtime @ names change during duplication; the child hierarchy stays exact.
func replica_node(source: Node) -> Node:
	var indices: Array[int] = []
	var node := source
	while node != fighter.actor:
		indices.push_front(node.get_index())
		node = node.get_parent()
	node = _standby_actor
	for index in indices: node = node.get_child(index)
	return node

func watch_consumer(consumer: CanvasItem, hud: HudUI) -> void:
	set_process(true)
	_activity = preload("res://scenes/ui/preview_activity.gd").new(self,consumer)
	_activity.resumed.connect(_update_camera)
	hud.battle_mode_changed.connect(_activity.set_covered)
	_activity.set_covered(hud._battle)
	_update_camera()

func _process(_delta: float) -> void:
	_update_camera()

func _update_camera() -> void:
	if not is_instance_valid(_standby_skeleton): return
	var head := _standby_skeleton.get_bone_global_pose(_standby_skeleton.find_bone("Head")).origin
	var height := _standby_actor.scale.y
	var target := _standby_skeleton.to_global(head)+Vector3(0,.07*height,0)
	camera.global_position = target+Vector3(0,.035*height,.95*height)
	camera.look_at(target)
