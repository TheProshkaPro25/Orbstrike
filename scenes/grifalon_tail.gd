extends RefCounted
## Перьевой веер поворачивается у основания, а не складывается змейкой.
## Локальные rest-повороты сохраняют исходную форму всех его перьев.
static func prepare(animation: Animation, player: AnimationPlayer) -> void:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
		var path := animation.track_get_path(track)
		if path.get_subname_count() != 1 or path.get_subname(0) not in [&"tail2", &"tail3", &"tail4"]: continue
		var skeleton := player.get_node(player.root_node).get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
		if skeleton == null: continue
		var bone := skeleton.find_bone(path.get_subname(0))
		if bone < 0: continue
		var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		while animation.track_get_key_count(track) > 0:
			animation.track_remove_key(track,animation.track_get_key_count(track)-1)
		animation.rotation_track_insert_key(track,0.0,rest)
