class_name FighterPortrait
extends SubViewport
## A second camera on the same resident actor, isolated from the arena by layers.
var fighter: VrmFighter
var camera: Camera3D
var _activity: RefCounted

func _init() -> void:
	size = Vector2i(144,144)
	transparent_bg = true
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)
	camera = Camera3D.new()
	camera.fov = 30
	# Portrait lighting stays readable across all three locations.
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.85,.9,1)
	environment.ambient_light_energy = .7
	camera.environment = environment
	add_child(camera)

func bind(value: VrmFighter,side: int) -> void:
	fighter = value
	world_3d = fighter.get_world_3d()
	camera.cull_mask = 1 << (18+side)
	for mesh in fighter.meshes: mesh.layers = camera.cull_mask
	_update_camera()
	if _activity != null: _activity.sync()
	else:
		# Isolated captures may bind without a UI consumer. Match HUD always watches one.
		render_target_update_mode = SubViewport.UPDATE_ALWAYS
		set_process(true)

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
	if not is_instance_valid(fighter): return
	var head := fighter.skeleton.get_bone_global_pose(fighter.skeleton.find_bone("Head")).origin
	var height := fighter.actor.scale.y
	var target := fighter.skeleton.to_global(head)+fighter.global_basis*Vector3(0,.07*height,0)
	camera.global_position = target+fighter.global_basis*Vector3(0,.035*height,.95*height)
	camera.look_at(target)
