extends "res://tools/low_load_benchmark.gd"
## Same real resident match; isolated resolution intervention and actual preset pair.
## Root query times are viewport timings, not whole GPU occupancy.
class TimedAI extends AIPlayer:
	var spans: Array = []
	func record(method: String, begin: int) -> void:
		spans.append({"method":method,"side":player,"begin_usec":begin,"end_usec":Time.get_ticks_usec()})
	func choose_setup(view: MatchState, legal = null, can_skip: bool = false) -> Dictionary:
		var t := Time.get_ticks_usec(); var result := super.choose_setup(view,legal,can_skip); record("choose_setup",t); return result
	func choose_throw(view: MatchState) -> Dictionary:
		var t := Time.get_ticks_usec(); var result := super.choose_throw(view); record("choose_throw",t); return result
	func should_open_gate(view: MatchState, pre: BattleResult) -> bool:
		var t := Time.get_ticks_usec(); var result := super.should_open_gate(view,pre); record("should_open_gate",t); return result
	func choose_ability(view: MatchState, pre: BattleResult, legal = null) -> StringName:
		var t := Time.get_ticks_usec(); var result := super.choose_ability(view,pre,legal); record("choose_ability",t); return result
	func choose_attach(view: MatchState, uid: int, legal: Array, moment: StringName = &"after_landing") -> StringName:
		var t := Time.get_ticks_usec(); var result := super.choose_attach(view,uid,legal,moment); record("choose_attach",t); return result
	func choose_ability_target(view: MatchState, pre: BattleResult, id: StringName, legal: Array = []) -> Dictionary:
		var t := Time.get_ticks_usec(); var result := super.choose_ability_target(view,pre,id,legal); record("choose_ability_target",t); return result

var main: Node
var bot: TimedAI
var enemy: TimedAI
var events_trace: Array = []
var raw: Array = []
var hz := 100.0
var target_slot := -1
var camera_transform: Transform3D
var frozen_state := ""
var measured_viewports: Array[Viewport] = []
var post_draw_count := 0
var battle_seen := false
var external_processes: Dictionary={}
var external_cpu: Array=[]

func collect_viewports(node: Node) -> void:
	if node is Viewport:
		measured_viewports.append(node)
		RenderingServer.viewport_set_measure_render_time(node.get_viewport_rid(),true)
	for child in node.get_children(): collect_viewports(child)
func viewport_states() -> Array:
	var result: Array=[]
	for vp in measured_viewports:
		if not is_instance_valid(vp): continue
		result.append({"path":str(vp.get_path()),"size":str(vp.size),"update_mode":vp.render_target_update_mode if vp is SubViewport else -1,"disable_3d":vp.disable_3d})
	return result

func ticks(path: String) -> int:
	var output: Array=[]
	if OS.execute("cat",[path],output)!=0 or output.is_empty(): return -1
	var text := String(output[0])
	var fields := text.substr(text.rfind(")")+2).split(" ")
	return int(fields[11])+int(fields[12]) if fields.size()>12 else -1
func active_ticks() -> Array:
	var pid := OS.get_process_id()
	var result: Array=[ticks("/proc/%d/stat" % pid),ticks("/proc/%d/task/%d/stat" % [pid,pid])]
	check(result[0]>=0 and result[1]>=0,"Linux process and main-thread active CPU counters readable")
	return result
func discover_external() -> void:
	var output: Array=[]
	OS.execute("ps",["-C","godot","-o","pid=,args="],output)
	if output.is_empty(): return
	for line in String(output[0]).split("\n"):
		var clean := line.strip_edges()
		var pid := int(clean.get_slice(" ",0))
		if pid>0 and pid!=OS.get_process_id(): external_processes[str(pid)]=clean
func external_ticks() -> Dictionary:
	var result: Dictionary={}
	for pid in external_processes:
		if FileAccess.file_exists("/proc/%s/stat"%pid): result[pid]=ticks("/proc/%s/stat"%pid)
	return result
func gpu_state() -> String:
	var output: Array=[]
	OS.execute("nvidia-smi",["--query-gpu=utilization.gpu,clocks.current.graphics,power.draw,temperature.gpu","--format=csv,noheader"],output)
	return str(output)
func mark(label: String, data: Dictionary = {}) -> void:
	if EngineDebugger.is_active(): EngineDebugger.send_message("orbstrike:mark",[label])
	print("MATCH_MARK ",label," ",JSON.stringify(data))
	events_trace.append({"label":label,"usec":Time.get_ticks_usec(),"frame":Engine.get_process_frames(),"data":data})
func frame_row(label: String, last: int) -> int:
	var now := Time.get_ticks_usec()
	var views: Dictionary={}
	var all_gpu := 0.0
	var all_cpu := 0.0
	for vp in measured_viewports:
		if not is_instance_valid(vp): continue
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid())
		var mode: int=vp.render_target_update_mode if vp is SubViewport else RenderingServer.VIEWPORT_UPDATE_ALWAYS
		var counted := not vp is SubViewport or mode==SubViewport.UPDATE_ALWAYS
		views[str(vp.get_path())]={"gpu_ms":gpu,"cpu_ms":cpu,"update_mode":mode,"included_in_always_update_sum":counted}
		if counted:
			all_gpu+=gpu
			all_cpu+=cpu
	raw.append({"segment":label,"usec":now,"frame":Engine.get_process_frames(),"wall_ms":(now-last)/1000.0,"process_monitor_window_max_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_monitor_window_max_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"root_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"root_render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"viewport_timings":views,"sum_always_update_viewport_gpu_ms":all_gpu,"sum_always_update_viewport_render_cpu_ms":all_cpu,"frame_setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),"post_draw_count":post_draw_count,"frames_drawn":Engine.get_frames_drawn(),"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"active_physics3d":Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),"collision_pairs3d":Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),"physics3d_islands":Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)})
	return now
func stats(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	var over := 0
	var over17 := 0
	for v in values:
		total+=float(v)
		if float(v)>1000.0/60.0: over+=1
		if float(v)>17.0: over17+=1
	return {"mean":total/values.size(),"p50":values[int((values.size()-1)*.5)],"p95":values[int((values.size()-1)*.95)],"p99":values[int((values.size()-1)*.99)],"max":values[-1],"fraction_over_16_667":float(over)/values.size(),"fraction_over_17":float(over17)/values.size()}
func summarize(label: String, samples: Array, active0: Array, active1: Array) -> Dictionary:
	var result := {"mode":label,"samples":samples.size(),"scale":root.scaling_3d_scale,"preset":GraphicsSettings.level_name(),"shadow_enabled":main._sun.shadow_enabled,"msaa":root.msaa_3d,"ssao":main._env.ssao_enabled,"ssil":main._env.ssil_enabled,"ssr":main._env.ssr_enabled,"glow":main._env.glow_enabled,"scene_detail":GraphicsSettings.option("scene_detail"),"vsync":DisplayServer.window_get_vsync_mode()}
	var elapsed := float(samples[-1].usec-samples[0].usec)/1000000.0
	for key in ["wall_ms","process_monitor_window_max_ms","physics_monitor_window_max_ms","root_gpu_ms","root_render_cpu_ms","sum_always_update_viewport_gpu_ms","sum_always_update_viewport_render_cpu_ms","frame_setup_cpu_ms","draws","primitives","active_physics3d","collision_pairs3d","physics3d_islands"]:
		var values: Array=[]
		for sample in samples: values.append(sample[key])
		result[key]=stats(values)
	result["elapsed_seconds"]=elapsed
	result["post_draw_delta"]=samples[-1].post_draw_count-samples[0].post_draw_count
	result["frames_drawn_delta"]=samples[-1].frames_drawn-samples[0].frames_drawn
	result["viewport_states"]=viewport_states()
	result["main_thread_active_cpu_ms_per_frame"]=float(active1[1]-active0[1])/hz*1000.0/samples.size()
	result["process_all_threads_active_cpu_ms_per_frame"]=float(active1[0]-active0[0])/hz*1000.0/samples.size()
	result["main_thread_one_core_percent"]=float(active1[1]-active0[1])/hz/elapsed*100.0
	result["process_all_threads_one_core_percent"]=float(active1[0]-active0[0])/hz/elapsed*100.0
	return result
func bench(label: String, preset: int, scale: float = -1.0) -> void:
	GraphicsSettings.force_level(preset)
	GraphicsSettings.overrides.clear()
	if scale>0.0: GraphicsSettings.overrides["render_scale"]=scale
	main.apply_graphics()
	await frames(120)
	check(main.cam.global_transform.is_equal_approx(camera_transform),label+" same camera")
	check(JSON.stringify(main.ctrl.action_trace)==frozen_state,label+" unchanged match actions")
	var start_index := raw.size()
	discover_external()
	var external0 := external_ticks()
	var gpu0 := gpu_state()
	var active0 := active_ticks()
	var last := Time.get_ticks_usec()
	mark(label+"-begin")
	for i in 360:
		await process_frame
		last=frame_row(label,last)
	var active1 := active_ticks()
	var external1 := external_ticks()
	var competitors: Dictionary={}
	for pid in external0:
		if external1.has(pid) and external0[pid]>=0 and external1[pid]>=0: competitors[pid]={"active_cpu_ms_per_sample":float(external1[pid]-external0[pid])/hz*1000.0/360.0,"command":external_processes[pid]}
	external_cpu.append({"mode":label,"processes":competitors,"gpu_before":gpu0,"gpu_after":gpu_state()})
	mark(label+"-end")
	var row := summarize(label,raw.slice(start_index),active0,active1)
	rows.append(row)
	print("MATCH_BOTTLENECK ",JSON.stringify(row))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label+".png"))
func run() -> void:
	out="res://build/checks/presentation/match-bottleneck"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(OS.get_environment("XDG_DATA_HOME").begins_with(ProjectSettings.globalize_path("res://build/checks/")),"isolated check.py data")
	var hz_out: Array=[]
	OS.execute("getconf",["CLK_TCK"],hz_out)
	if not hz_out.is_empty(): hz=float(hz_out[0])
	GraphicsSettings.force_level(GraphicsSettings.Level.LOW)
	GraphicsSettings.custom_options["vsync"]=false
	GraphicsSettings.max_fps=60
	Engine.max_fps=60
	Engine.time_scale=1.0
	Engine.physics_ticks_per_second=60
	root.size=Vector2i(1280,720)
	root.content_scale_size=root.size
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for path in ["tools/match_bottleneck_benchmark.gd","tools/low_load_benchmark.gd","tools/check.py","tools/test_window.gd","scenes/graphics_settings.gd","scenes/main.gd","scenes/arena.gd","core/ai_player.gd","core/match_controller.gd","scenes/interaction/interaction_controller.gd","scenes/creature_ball.gd"]:
		source_hashes[path]=FileAccess.get_sha256("res://"+path)
	change_scene_to_file("res://scenes/loading/boot.tscn")
	var deadline := Time.get_ticks_msec()+180000
	while current_scene==null or current_scene.scene_file_path!="res://scenes/menu/main_menu.tscn":
		await process_frame
		if Time.get_ticks_msec()>deadline: check(false,"Boot timeout"); quit(1); return
	ArenaLocations.choose(3)
	current_scene._enter_game("")
	while current_scene.scene_file_path!="res://scenes/main.tscn": await process_frame
	main=current_scene
	main.team_menu._rng.seed=777
	main.rng.seed=777
	var before_counts: Array=[GameLoading.i().actor_build_count,GameLoading.i().arena_build_count]
	main.team_menu.pick_random_and_start()
	while not main._lifecycle.input_allowed():
		if main._lifecycle.intro!=null: await key(KEY_ESCAPE)
		else: await process_frame
	bot=TimedAI.new(0,12345)
	enemy=TimedAI.new(1,778,-1.0,main.ai.difficulty)
	enemy._rng.state=main.ai._rng.state
	enemy.configure_personality(main.ai.personality)
	enemy._my_gates=main.ai._my_gates.duplicate(true)
	enemy._aim_error=main.ai._aim_error
	main.ai=enemy
	collect_viewports(root)
	RenderingServer.frame_post_draw.connect(func():post_draw_count+=1)
	main.ctrl.phase_changed.connect(func(phase,side):mark("phase",{"phase":phase,"side":side}))
	main.ctrl.creature_selected.connect(func(side,uid,_recall):mark("creature_selected",{"side":side,"uid":uid}))
	main.ctrl.creature_stood.connect(func(uid,slot):mark("creature_stood",{"uid":uid,"slot":slot}))
	main.ctrl.battle_started.connect(func(slot,attacker,defender):battle_seen=true;mark("battle_started",{"slot":slot,"attacker":attacker,"defender":defender}))
	mark("actions-begin")
	var last := Time.get_ticks_usec()
	deadline=Time.get_ticks_msec()+95000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		last=frame_row("actions",last)
		if main.ctrl.get_turn()>=3 and battle_seen and main._next_turn.visible and not main.events.is_busy(): break
		autoplay_step()
	mark("actions-end")
	check(main.ctrl.get_turn()>=3 and battle_seen and not main.events.is_busy(),"real unaccelerated actions include battle and reach stable turn boundary")
	main.cam.snap_overview()
	main.cam.set_process(false)
	await frames(10)
	camera_transform=main.cam.global_transform
	frozen_state=JSON.stringify(main.ctrl.action_trace)
	await bench("low-scale100-a",GraphicsSettings.Level.LOW,1.0)
	await bench("low-scale50",GraphicsSettings.Level.LOW,.5)
	await bench("low-scale50-b",GraphicsSettings.Level.LOW,.5)
	await bench("low-scale100-b",GraphicsSettings.Level.LOW,1.0)
	await bench("high-preset",GraphicsSettings.Level.HIGH)
	await bench("low-preset75",GraphicsSettings.Level.LOW)
	await bench("high-preset-b",GraphicsSettings.Level.HIGH)
	check(before_counts==[GameLoading.i().actor_build_count,GameLoading.i().arena_build_count],"no resident actor or arena rebuild")
	check(Engine.max_fps==60 and Engine.time_scale==1.0 and Engine.physics_ticks_per_second==60,"wrapper60 FPS normal simulation")
	var match_snapshot := {"seed":main.ctrl.match_seed,"turn":main.ctrl.get_turn(),"actions":main.ctrl.action_trace,"events":main.ctrl.event_log,"camera":str(camera_transform),"arena":main.arena.location_id,"definitions":{}}
	for uid in main._defs: match_snapshot.definitions[str(uid)]=String(main._defs[uid].id)
	var report := {"date":Time.get_datetime_string_from_system(),"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":root.size,"fps_cap":60,"clk_tck":hz,"script_profiler_requested":OS.get_environment("ORBSTRIKE_BENCH_DEBUG_PORT")!="","source_hashes":source_hashes,"checks":checks,"failures":failures,"match":match_snapshot,"rows":rows,"external_processes":external_processes,"external_cpu":external_cpu,"ai_spans":bot.spans+enemy.spans,"event_trace":events_trace,"limits":["Single Linux Vulkan host, offscreen minimized wrapper; not Windows or weak GPU.","Viewport timing sums include only root+UPDATE_ALWAYS, avoiding stale UPDATE_DISABLED/ONCE readouts; raw mode+values for all Viewports retained. Other on-demand views can be omitted, so sum is not exhaustive GPU occupancy.","CPU active clocks are Linux /proc user+system ticks; aggregate segments exclude sleep but include benchmark overhead.","Performance TIME_PROCESS/TIME_PHYSICS_PROCESS are periodically updated window maxima, not per-frame script costs; separate and not additive. Main-thread CPU excludes sleep, but may include wait busywork.","Script profiler, when connected, enabled only during actions; idle pairs exclude profiler overhead. Debugger connection remains active.","AI public-method spans can nest; do not sum overlaps. View/legal construction excluded from AI spans.","Wall includes mandatory 60 FPS pacing; >16.667 fraction is sensitive to timer jitter; >17ms also reported.","Live idle animations/particles continue. Match state and camera are fixed; screenshots are not identical time samples."]}
	FileAccess.open(out.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	FileAccess.open(out.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(raw,"\t"))
	main.ctrl.save_debug_trace(out.path_join("match-trace.json"))
	main._release_game_resources()
	main.queue_free()
	main=null
	await frames(3)
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	await frames(3)
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(3)
	print("Match bottleneck: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func autoplay_step() -> void:
	if main.hud._reading>0: main.hud._skip_flag=true
	if main.battle_overlay._open: main.battle_overlay._close()
	if preload("res://tools/autoplay.gd").press_next_turn(main): return
	var view: MatchState=main.ctrl.get_view(0)
	if preload("res://tools/autoplay.gd").choose_pending_target(main,bot): return
	if main.setup_panel._panel.visible:
		var choice:=bot.choose_setup(view,main.ctrl.legal_setup_slots(),main.ctrl.can_skip_gate())
		main.setup_panel.hide_panel()
		if choice.is_empty(): main._on_setup_skipped()
		else: main._on_setup_placed(choice["card_id"],int(choice["slot"]))
	elif main.hud._creature_panel.visible:
		var choice:=bot.choose_throw(view)
		target_slot=int(choice["target_slot"])
		main._on_creature_chosen(int(choice["uid"]))
	elif main._active_ball!=null and not main.director.flying and main.ctrl.get_active_player()==0 and not main.events.is_busy():
		var slots: Array=main._gate_slots()
		if not slots.is_empty(): main._on_slot_picked(target_slot if slots.has(target_slot) else int(slots[0]))
	elif main.ability_panel._panel.visible:
		var id: StringName=&""
		if main.ctrl.get_ability_moment()==&"battle":
			if main.ctrl.can_reveal_gate(0) and bot.should_open_gate(view,main.ctrl.get_battle_preview()): main._on_gate_open_requested(); return
			id=bot.choose_ability(view,main.ctrl.get_battle_preview(),main.ctrl.legal_abilities(0))
		elif main.ctrl.get_ability_moment()==&"after_landing": id=bot.choose_attach(view,main.ctrl.get_landed_uid(),main.ctrl.legal_abilities(0))
		else: return
		if id==&"": main._on_ability_passed()
		else: main._on_ability_chosen(id)
