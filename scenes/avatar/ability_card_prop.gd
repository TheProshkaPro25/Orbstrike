class_name AbilityCardProp
extends Node3D
## Resident hand prop. Uses the same card face as the played ability in the UI.
var card: ArenaCardNode
var back: ArenaCardNode
var light: OmniLight3D
var aura: MeshInstance3D
var aura_material: ShaderMaterial
var prepared := false
var element := -1
var card_id: StringName = &""
var strength := 0.0
var ignition := 1.25
var action_duration := 3.35

func _init() -> void:
	card = ArenaCardNode.new()
	card.scale = Vector3.ONE*(.12/ArenaCardNode.SIZE.x)
	add_child(card)
	back = ArenaCardNode.new()
	back.scale = card.scale
	back.rotation.x = PI
	back._box.hide()
	back.show_facedown(0,null)
	add_child(back)
	aura = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(.34,.42)
	aura.mesh = plane
	aura.position.y = -.002
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aura_material = ShaderMaterial.new()
	aura_material.shader = preload("res://scenes/avatar/ability_card_glow.gdshader")
	aura.material_override = aura_material
	add_child(aura)
	light = OmniLight3D.new()
	light.omni_range = .7
	light.position.y = .04
	light.shadow_enabled = false
	add_child(light)
	clear()

func configure(def: CardDef, attribute: int, ignition_time: float = 1.25, duration: float = 3.35) -> void:
	if def == null:
		clear()
		return
	prepared = true
	ignition = ignition_time
	action_duration = duration
	card_id = def.id
	element = attribute
	card.show_face(def)
	var color := VisualUtil.attr_color(element)
	card._mat.set_shader_parameter("flash_col",color)
	card._mat.set_shader_parameter("self_light",.7)
	aura_material.set_shader_parameter("element_color",color)
	light.light_color = color
	sample(0)

func sample(time: float) -> void:
	visible = prepared and time < action_duration-.17
	strength = smoothstep(ignition-.14,ignition+.06,time)*(1.0-smoothstep(ignition+.35,ignition+.90,time))
	card._mat.set_shader_parameter("flash",strength*.22)
	aura_material.set_shader_parameter("strength",strength)
	light.light_energy = strength*.25
	aura.scale = Vector3.ONE*(1.0+.12*strength)

func clear() -> void:
	prepared = false
	strength = 0
	hide()
	if light != null: light.light_energy = 0
	if aura_material != null: aura_material.set_shader_parameter("strength",0.0)
