class_name ModelLifetime
extends RefCounted
## Материалы прежней модели живут до конца кадра: renderer успевает обработать
## зависимости при повторной установке или удалении модели в одном кадре.
static func release(node: Node, tree: SceneTree) -> void:
	var held: Array[Material] = []
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is MeshInstance3D:
			var mesh := current as MeshInstance3D
			for material in [mesh.material_override, mesh.material_overlay]:
				if material != null: held.append(material)
			if mesh.mesh != null:
				for i in mesh.mesh.get_surface_count():
					var material := mesh.get_active_material(i)
					if material != null: held.append(material)
		for child in current.get_children(): pending.append(child)
	node.free()
	if DisplayServer.get_name() == "headless":
		tree.process_frame.connect(held.clear, CONNECT_ONE_SHOT)
	else:
		RenderingServer.frame_post_draw.connect(held.clear, CONNECT_ONE_SHOT)
