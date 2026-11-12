extends SceneTree
## Fast component contracts, no Boot, GLB setup, server or rendered acceptance.
const Interaction := preload("res://scenes/interaction/interaction_controller.gd")
const Request := preload("res://scenes/interaction/interaction_request.gd")
const Action := preload("res://scenes/interaction/card_action.gd")
const Target := preload("res://scenes/interaction/ability_target.gd")
const Modes := preload("res://scenes/modes/game_modes.gd")
const Presentation := preload("res://scenes/presentation/match_presentation.gd")
const HelpPolicy := preload("res://scenes/presentation/online_help_policy.gd")
const Lifetime := preload("res://scenes/model_lifetime.gd")

class Recorder extends MatchController:
	var recorded: Array = []
	func throw_with_gate(player: int, card: StringName, slot: int, uid: int) -> int:
		recorded = [player,card,slot,uid]
		return OK
	func play_ability(player: int, card: StringName, target: Dictionary = {}) -> int:
		recorded = [player,card,target]
		return OK

class ChoiceProbe extends Interaction:
	var restored := ""
	func show_pre_throw() -> void: restored = "pre_throw"
	func do_attach(_player: int) -> void: restored = "after_landing"
	func do_ability(_player: int) -> void: restored = "battle"

var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",why)
func run() -> void:
	CardDB.load_all()
	var recorder := Recorder.new(CardDB.preset_deck(0),CardDB.preset_deck(1),771)
	var input := ChoiceProbe.new()
	root.add_child(input)
	input.bind_controller(recorder,AIPlayer.new(1,772))
	var request: Request = Request.make(Request.Kind.LAUNCH,1,4) as Request
	check(request.expected_phase() == MatchController.Phase.AWAIT_LANDING and request.to_legacy() == {"kind":"launch","player":1,"uid":4},"typed launch request preserves uid/side/phase")
	var restored: Request = Request.from_legacy(request.to_legacy()) as Request
	check(restored.kind == request.kind and restored.uid == 4,"legacy view roundtrips at the boundary")
	input.stop()
	input.queue_request(request)
	check(input.state == Interaction.State.STOPPED and input.pending.is_empty(),"stop rejects a late queued request even with a live controller")
	input.ability_target_moment = &"battle"
	input.on_ability_target_cancelled()
	check(input.state == Interaction.State.STOPPED and input.restored.is_empty(),"late target cancel cannot revive stopped interaction")
	for moment in [&"pre_throw",&"after_landing",&"battle"]:
		input.ability_target_card = &"ability_surge"
		input.ability_target_moment = moment
		input.state = Interaction.State.CHOOSING_ABILITY_TARGET
		input.on_ability_target_cancelled()
		check(input.restored == String(moment) and input.ability_target_card == &"","cancel returns to the exact ability moment: "+String(moment))
	check(input._execute(Action.Kind.THROW_WITH_GATE,0,&"arena_altar",2,5) == OK and recorder.recorded == [0,&"arena_altar",5,2],"typed compound command preserves controller slot/uid ordering")
	var target := {"target_uid":3}
	input._execute(Action.Kind.PLAY_ABILITY,0,&"ability_surge",-1,-1,target)
	target.target_uid = 5
	check(recorder.recorded[2] == {"target_uid":3},"typed target snapshots the selected uid")
	input._execute(Action.Kind.PLAY_ABILITY,1,&"ability_surge",-1,-1,{"target_card":&"ability_surge","label":"UI name"})
	check(recorder.recorded[2] == {"target_card":&"ability_surge"},"AI legal-target label is normalized away from the typed command")
	var invalid := Target.new()
	invalid.assign_core({"unknown":2})
	check(not invalid.valid,"target schema rejects unknown keys")
	check(input._execute(Action.Kind.PLAY_ABILITY,0,&"ability_surge",-1,-1,{"target_uid":3,"target_card":&"arena_altar"}) == ERR_INVALID_PARAMETER,"ambiguous target never reaches controller")
	var presentation := Presentation.new()
	root.add_child(presentation)
	presentation.bind_controller(recorder)
	var policy := HelpPolicy.new(presentation)
	policy.set_view({"legal":{"setup_slots":[0]}},1)
	var view := recorder.get_view(0)
	view.phase = MatchController.Phase.SETUP
	view.active_player = 1
	check(not policy.slot_tip(0,view.slots[0],view).is_empty(),"network seat1 policy uses authoritative setup slots")
	var help := policy.creature_tip(3,view)
	check(String(help[1]).contains("ваше существо") and String(help[6]).contains("Выберите подсвеченные"),"network seat1 help keeps its own creature/launch meaning")
	var root_source := FileAccess.get_file_as_string("res://scenes/main.gd")
	var director_source := FileAccess.get_file_as_string("res://scenes/presentation/arena_director.gd")
	check(not director_source.contains("game.") and not director_source.contains("var game"),"director has no game backpointer")
	check(not root_source.contains(".choose_ability(") and not root_source.contains(".select_creature(") and not root_source.contains("BALL_SCENE.instantiate"),"composition root owns neither decisions nor actor creation")
	# Replicas may share every material; release still installs distinct one-shots.
	var shared := StandardMaterial3D.new()
	var nodes: Array[Node] = []
	for i in 2:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.material_override = shared
		root.add_child(mesh)
		nodes.append(mesh)
		Lifetime.release(mesh,self)
	await process_frame
	await process_frame
	check(not is_instance_valid(nodes[0]) and not is_instance_valid(nodes[1]),"shared-material releases complete without duplicate callback errors")
	# Compare the ordinary RNG boundary with the original opponent-deck→seed order.
	var random := RandomNumberGenerator.new()
	random.seed = 771
	var reference := RandomNumberGenerator.new()
	reference.seed = 771
	CardDB.opponent_deck(reference)
	var expected_seed := reference.randi()
	var modes := Modes.new()
	var team := TeamMenu.new()
	var hud := HudUI.new()
	var layer := CanvasLayer.new()
	modes.configure(team,hud,layer,random)
	modes.player_deck = Tournament.deck_ids(CardDB.preset_deck(0))
	var spec := modes.prepare_match_spec()
	check(spec.seed == expected_seed and random.state == reference.state,"mode spec consumes ordinary deck/seed RNG exactly once")
	check(spec.decks.size() == 2 and spec.profiles.size() == 2 and spec.power_snapshots.size() == 2,"typed match specification contains complete two-side inputs")
	input.queue_free()
	presentation.queue_free()
	modes.free()
	team.free()
	hud.free()
	layer.free()
	await process_frame
	print("ARCHITECTURE CONTRACTS ",checks,"/",failures)
	quit(1 if failures else 0)
