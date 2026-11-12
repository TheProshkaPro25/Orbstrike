extends SceneTree
## Narrow UI fixture: no creature/model loading; counters show redundant work.
class CountingAnim extends CreatureAnim:
	var appearances := 0
	func appear(_from_ball: bool = true) -> void: appearances += 1
class CountingPreview extends CreaturePreview:
	var labels := 0
	var name_fits := 0
	var requests := 0
	func _line(text: String, color: Color, font_size: int) -> void:
		labels += 1
		super._line(text,color,font_size)
	func _set_name(text: String) -> void:
		name_fits += 1
		super._set_name(text)
	func _request(definition: CreatureDef) -> void:
		requests += 1
		_drop_model()
		_anim = CountingAnim.new()
		_norm.add_child(_anim)
		_shown_id = definition.id
var checks := 0
var failures := 0
var baseline := OS.get_environment("SFERY_CREATURE_PREVIEW_BASELINE") == "1"
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func frames() -> void:
	for i in 3: await process_frame
func _run() -> void:
	CardDB.load_all()
	var preview := CountingPreview.new()
	preview.position = Vector2(20,20)
	preview.size = Vector2(420,240)
	root.add_child(preview)
	var definition := CardDB.creature(CardDB.creature_ids()[0])
	preview.show_creature(definition)
	await frames()
	var initial_labels := preview.labels
	var initial_fits := preview.name_fits
	var initial_requests := preview.requests
	var label := preview._lines.get_child(0)
	preview._explanation.scroll_vertical = 20
	await frames()
	var scroll := preview._explanation.scroll_vertical
	var begin := Time.get_ticks_usec()
	for i in 30: preview.show_creature(definition,false,i % 2 == 0,"note-%d" % i)
	var elapsed := Time.get_ticks_usec()-begin
	var report := {"baseline":baseline,"requests":30,"labels_created":preview.labels-initial_labels,"name_fits":preview.name_fits-initial_fits,"model_requests":preview.requests-initial_requests,"cpu_usec":elapsed,"scope":"same CreatureDef UI calls; no FPS/graphics/model claim"}
	print("CREATURE_PREVIEW_REPEAT ",JSON.stringify(report))
	if not baseline:
		check(preview.labels == initial_labels,"same creature creates no repeated Labels/card-list text")
		check(preview.name_fits == initial_fits,"same width avoids repeated name measurement")
		check(preview._lines.get_child(0) == label,"same creature retains description nodes")
		check(preview._explanation.scroll_vertical == scroll,"same creature retains reading position")
	check(preview.requests == initial_requests,"same creature does not request another model")
	check(preview._status.text == "note-29","same creature updates note")
	check(preview._status.get_theme_color("font_color").is_equal_approx(Color(1,.85,.5)),"same creature updates in_team=false")
	var anim := preview._anim as CountingAnim
	preview.show_creature(definition,true,true,"selected")
	check(anim.appearances == 1 and preview._want_pose,"same creature preserves pose")
	check(preview._status.text == "selected" and preview._status.get_theme_color("font_color").is_equal_approx(Color(.55,.95,.6)),"selected status updates")
	if not baseline:
		var alternate := definition.duplicate() as CreatureDef
		alternate.display_name = "Очень длинное проверочное имя существа"
		preview.show_creature(alternate)
		check(preview.labels > initial_labels and preview._name.text == alternate.display_name,"new definition with same id refreshes description")
		await frames()
		preview.size.x = 240
		await frames()
		var narrow := preview._name.get_theme_font_size("font_size")
		preview.size.x = 900
		await frames()
		check(preview._name.get_theme_font_size("font_size") > narrow,"resize recalculates name without another hover")
		var fits := preview.name_fits
		preview.show_creature(alternate)
		check(preview.name_fits == fits,"same request after resize keeps current name fit")
		preview.show_hint("hint")
		preview.show_creature(definition)
		check(preview._name.text == definition.display_name and preview._lines.get_child_count() > 0,"return from hint restores creature details")
		preview.show_card(CardDB.card(CardDB.arena_ids()[0]))
		preview.show_creature(definition)
		check(preview._stage.visible and not preview._full_card_scroll.visible and preview._want == definition,"return from card restores creature context")
		var next := CardDB.creature(CardDB.creature_ids()[1])
		preview.show_creature(next)
		check(preview._shown_id == next.id and preview._name.text == next.display_name,"different creature refreshes model and text")
	preview.queue_free()
	await frames()
	print("CREATURE PREVIEW REFRESH ",checks,"/",failures)
	quit(1 if failures else 0)
