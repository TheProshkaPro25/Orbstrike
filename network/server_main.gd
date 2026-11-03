extends SceneTree
## godot --headless --path . -s res://network/server_main.gd -- --port=8910 --bind=127.0.0.1
const Server = preload("res://network/online_server.gd")
var service: Node

func _initialize() -> void:
	Engine.max_fps = 60
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	var port := 8910
	var address := "127.0.0.1"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port=") and arg.substr(7).is_valid_int(): port = int(arg.substr(7))
		elif arg.begins_with("--bind="): address = arg.substr(7)
		else:
			printerr("Usage: --port=8910 --bind=127.0.0.1")
			quit(2)
			return
	service = Server.new()
	root.add_child(service)
	var err: Error = service.listen(port, address)
	if err != OK:
		printerr("Online server failed to listen: ", error_string(err))
		quit(1)
		return
	print("ONLINE SERVER listening %s:%d protocol1" % [address, port])
