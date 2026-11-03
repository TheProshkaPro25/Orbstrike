extends RefCounted
## В исходных idle/attack Драгнара и Грифона hips неподвижен, а chest изгибает спину.
## Переносим эту дугу в таз: корпус и основание хвоста движутся одной фазой,
## сохраняя исходное направление груди, головы и крыльев.
const VERSION := 3

static func prepare(animation: Animation, _player: AnimationPlayer, synchronize: bool) -> void:
	if not synchronize or animation.get_meta("dragnar_torso_sync", 0) == VERSION: return
	var hips := -1
	var chest := -1
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
		var path := animation.track_get_path(track)
		if path.get_subname_count() != 1: continue
		if path.get_subname(0) == &"hips": hips = track
		if path.get_subname(0) == &"chest": chest = track
	if hips < 0 or chest < 0 or animation.length <= 0: return
	var lower := animation.rotation_track_interpolate(hips, 0).normalized()
	# Новые клипы с самостоятельной анимацией таза требуют отдельной оценки.
	for key in animation.track_get_key_count(hips):
		var value: Quaternion = animation.track_get_key_value(hips, key)
		if absf(lower.dot(value.normalized())) < .9999999: return
	var reference := animation.rotation_track_interpolate(chest, 0).normalized()
	var times := PackedFloat64Array()
	var values: Array[Quaternion] = []
	for key in animation.track_get_key_count(chest):
		times.append(animation.track_get_key_time(chest, key))
		var upper: Quaternion = animation.track_get_key_value(chest, key)
		values.append((lower * upper * reference.inverse()).normalized())
	var interpolation := animation.track_get_interpolation_type(chest)
	var wrap := animation.track_get_interpolation_loop_wrap(chest)
	for track in [hips, chest]:
		while animation.track_get_key_count(track) > 0:
			animation.track_remove_key(track, animation.track_get_key_count(track) - 1)
		animation.track_set_interpolation_type(track, interpolation)
		animation.track_set_interpolation_loop_wrap(track, wrap)
	for key in times.size(): animation.rotation_track_insert_key(hips, times[key], values[key])
	animation.rotation_track_insert_key(chest, 0, reference)
	# (H*C*C0^-1)*C0 == H*C. Только поворот: длины костей и положения
	# таза/корня не меняются, грудь следует естественной дуге без телепортации.
	animation.set_meta("dragnar_torso_sync", VERSION)
