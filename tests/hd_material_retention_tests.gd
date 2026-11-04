extends SceneTree
## Synthetic aliases prove that HD-only map release preserves native consumers.
const REMOVED := [&"normal_texture", &"roughness_texture", &"metallic_texture", &"ao_texture"]
const RETAINED := [&"albedo_texture", &"emission_texture", &"heightmap_texture", &"detail_albedo"]
var checks := 0
var failures := 0
var fixtures: Array[Node3D] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func material() -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	for slot in REMOVED + RETAINED: value.set(slot,GradientTexture1D.new())
	value.albedo_color = Color(0.2,0.4,0.6,0.37)
	value.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	value.emission_enabled = true
	return value

func mesh(parent: Node3D, value: Material, label: String = "Mesh") -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var box := BoxMesh.new()
	box.material = value
	node.mesh = box
	parent.add_child(node)
	return node

func fixture() -> Node3D:
	var node := Node3D.new()
	fixtures.append(node)
	return node

func snapshot(value: BaseMaterial3D) -> Dictionary:
	var result: Dictionary = {}
	for slot in REMOVED + RETAINED: result[slot] = value.get(slot)
	return result

func retained(value: BaseMaterial3D, before: Dictionary, label: String) -> void:
	for slot in RETAINED: check(value.get(slot) == before[slot],label+" retains "+String(slot))
	check(value.albedo_color == Color(0.2,0.4,0.6,0.37),label+" preserves albedo alpha")
	check(value.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,label+" preserves transparency mode")
	check(value.emission_enabled,label+" preserves emission flag")

func protected_maps(value: BaseMaterial3D, before: Dictionary, label: String) -> void:
	for slot in REMOVED: check(value.get(slot) == before[slot],label+" protects "+String(slot))
	retained(value,before,label)

func animation(parent: Node3D, value: Variant, path: NodePath, type: Animation.TrackType = Animation.TYPE_VALUE) -> void:
	var player := AnimationPlayer.new()
	parent.add_child(player)
	var clip := Animation.new()
	var track := clip.add_track(type)
	clip.track_set_path(track,path)
	clip.track_insert_key(track,0.0,value)
	var library := AnimationLibrary.new()
	library.add_animation(&"swap",clip)
	player.add_animation_library(&"",library)

func run() -> void:
	var root_model := fixture()
	var candidate := material()
	mesh(root_model,candidate)
	var before := snapshot(candidate)
	CreatureModels._release_unused_hd_maps(root_model)
	for slot in REMOVED: check(candidate.get(slot) == null,"converted-only clears "+String(slot))
	retained(candidate,before,"converted-only")
	for scenario in ["overlay","override","next-pass","shader-next-pass","shader-surface-next-pass","animation-material","animation-mesh","animation-method"]:
		root_model = fixture()
		candidate = material()
		before = snapshot(candidate)
		mesh(root_model,candidate,"Converted")
		var consumer := mesh(root_model,material(),"Consumer")
		match scenario:
			"overlay": consumer.material_overlay = candidate
			"override": consumer.material_override = candidate
			"next-pass":
				var native := material()
				native.next_pass = candidate
				consumer.material_override = native
			"shader-next-pass":
				var custom := ShaderMaterial.new()
				custom.next_pass = candidate
				consumer.material_override = custom
			"shader-surface-next-pass":
				var custom := ShaderMaterial.new()
				custom.next_pass = candidate
				consumer.mesh.material = custom
			"animation-material": animation(root_model,candidate,NodePath("Consumer:material_override"))
			"animation-mesh":
				var authored := BoxMesh.new()
				authored.material = candidate
				animation(root_model,authored,NodePath("Consumer:mesh"))
			"animation-method": animation(root_model,{"method":&"set_material_override","args":[candidate]},NodePath("Consumer"),Animation.TYPE_METHOD)
		CreatureModels._release_unused_hd_maps(root_model)
		protected_maps(candidate,before,scenario)
	for node in fixtures: node.free()
	fixtures.clear()
	print("HD MATERIAL RETENTION ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
