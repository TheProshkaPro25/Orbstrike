extends "res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd"
## Каталожный actor перемещается между резервом, preview и матчем. Его GPU-данные
## принадлежат самому actor, а не одному пребыванию в SceneTree.
const VENDOR_PATH := "res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd"
const STORE_PATH := "res://scenes/loading/preparation_store.gd"
const CACHE_VERSION := 1
# This exact allocator-only vendor revision preserves canonical CPU bytes (verified
# against the previous revision on real cloth). Keep existing shipped .pdat keys;
# any future vendor edit gets its actual hash and invalidates normally.
const GPU_ALLOCATOR_VENDOR_SHA := "88b293bb0a1eaadf9c50dbd84d437fee350c390b544a7fca40022824631a6235"
const CPU_COMPATIBLE_VENDOR_SHA := "c788381a4b2e79a8ce0ec9b10c23e6fcff51746a559f1770d0b7d123369f5a5a"
const MEMORY_CACHE_LIMIT := 64 # Шесть стихий × шесть неизменяемых структур, с запасом.
static var canonical_cache_enabled := true
static var canonical_cache_hits: Dictionary = {}
static var canonical_cache_misses: Dictionary = {}
static var _canonical_cache: Dictionary = {}
static var _mesh_digests: Dictionary = {}
static var _vendor_stamp := ""
var _source_stamp := ""
var _topology_stamp := ""

func _initialize() -> void:
	# Base._ready() использует get_script(): у производного класса это уже scenes/.
	_plugin_dir = VENDOR_PATH.get_base_dir().get_base_dir()
	_source_stamp = ""
	_topology_stamp = ""
	super._initialize()


## Только канонические CPU-массивы. У каждого бойца остаются собственные mutable
## GPU/RID, текущие кости, collider nodes, материалы и результаты симуляции.
static func clear_canonical_cache() -> void:
	_canonical_cache.clear()
	_mesh_digests.clear()
	_vendor_stamp = ""
	canonical_cache_hits.clear()
	canonical_cache_misses.clear()


static func _digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()


func _source_key(kind: String, settings: Array = []) -> String:
	if not canonical_cache_enabled or not ResourceLoader.exists(STORE_PATH):
		return ""
	var store: GDScript = load(STORE_PATH)
	if not store.enabled:
		return ""
	if _source_stamp.is_empty():
		var source: PackedScene = get_meta("preparation_source", null)
		if source == null:
			return ""
		_source_stamp = store.source_key(source)
		if _source_stamp.is_empty():
			return ""
	if _vendor_stamp.is_empty():
		_vendor_stamp = FileAccess.get_sha256(VENDOR_PATH) if FileAccess.file_exists(VENDOR_PATH) else "compiled-vendor-v1"
	if _vendor_stamp == GPU_ALLOCATOR_VENDOR_SHA:
		_vendor_stamp = CPU_COMPATIBLE_VENDOR_SHA
	return _digest([CACHE_VERSION, Engine.get_version_info().get("hash",""), _vendor_stamp, _source_stamp, kind, settings])


func _cache_key(kind: String, settings: Array = []) -> String:
	var source_key := _source_key(kind)
	if source_key.is_empty(): return ""
	if _topology_stamp.is_empty():
		# Проверяется именно геометрия после фильтра поверхностей/weld/skin-offset,
		# а не instance_id или глобальная позиция нового экземпляра.
		_topology_stamp = _digest([_src_vertices, _src_indices, _src_colors,
			_src_bones, _src_weights, _welded_positions, _original_to_welded,
			_bind_to_bone, _particle_count, weld_epsilon, cloth_weight_channel, cloth_skin_offset])
	return _digest([source_key, _topology_stamp, settings])


static func _copy_data(value: Variant) -> Variant:
	# Packed arrays and ordinary arrays/dictionaries all implement duplicate().
	return value.duplicate(true) if value is Array or value is Dictionary else value.duplicate()


static func _remember(key: String, value: Variant) -> void:
	if not _canonical_cache.has(key) and _canonical_cache.size() >= MEMORY_CACHE_LIMIT:
		_canonical_cache.erase(_canonical_cache.keys()[0])
	_canonical_cache[key] = _copy_data(value)


func _read(kind: String, key: String) -> Variant:
	if key.is_empty(): return null
	var memory_key := kind + ":" + key
	if _canonical_cache.has(memory_key):
		canonical_cache_hits[kind] = int(canonical_cache_hits.get(kind,0)) + 1
		return _copy_data(_canonical_cache[memory_key])
	var store: GDScript = load(STORE_PATH)
	var cached: Variant = store.read_cache(kind,key)
	if cached != null and not (cached is Array or cached is Dictionary or cached is PackedFloat32Array or cached is PackedInt32Array):
		cached = null
	if cached != null:
		_remember(memory_key,cached)
		canonical_cache_hits[kind] = int(canonical_cache_hits.get(kind,0)) + 1
		return _copy_data(cached)
	canonical_cache_misses[kind] = int(canonical_cache_misses.get(kind,0)) + 1
	return null


func _write(kind: String, key: String, value: Variant) -> void:
	if key.is_empty(): return
	_remember(kind+":"+key,value)
	# Store отвечает за explicit writing_enabled: обычный запуск только читает.
	var store: GDScript = load(STORE_PATH)
	store.write_cache(kind,key,value)


func _prepare_mesh_data(mesh: Mesh) -> Dictionary:
	var key := _source_key("cloth-extract")
	if not key.is_empty():
		var mesh_id := str(mesh.get_instance_id())+":complete"
		if not _mesh_digests.has(mesh_id):
			var arrays: Array = []
			for surface in mesh.get_surface_count():
				arrays.append([mesh.surface_get_primitive_type(surface),mesh.surface_get_arrays(surface)])
			if _mesh_digests.size() >= MEMORY_CACHE_LIMIT:
				_mesh_digests.erase(_mesh_digests.keys()[0])
			_mesh_digests[mesh_id] = _digest(arrays)
		key = _source_key("cloth-extract",[_mesh_digests[mesh_id]])
	var cached: Variant = _read("cloth-extract",key)
	if cached is Dictionary and cached.get("vertices") is PackedVector3Array and cached.get("uvs") is PackedVector2Array and cached.get("colors") is PackedColorArray and cached.get("indices") is PackedInt32Array and cached.get("bones") is PackedInt32Array and cached.get("weights") is PackedFloat32Array and cached.get("surface_ranges") is Array:
		return cached
	var data := super._prepare_mesh_data(mesh)
	_write("cloth-extract",key,data)
	return data


func _prepare_weld(vertices: PackedVector3Array, epsilon: float) -> Dictionary:
	# Вызывается до заполнения _welded_positions/_original_to_welded: только
	# входные позиции и epsilon определяют результат исходного spatial hash.
	var key := _source_key("cloth-weld",[vertices,epsilon])
	var cached: Variant = _read("cloth-weld",key)
	if cached is Dictionary and cached.get("welded_positions") is PackedVector3Array and cached.get("original_to_welded") is PackedInt32Array:
		if cached.original_to_welded.size() == vertices.size(): return cached
	var data := super._prepare_weld(vertices,epsilon)
	_write("cloth-weld",key,data)
	return data


func _build_mesh_constraints(mesh_to_ref: Transform3D) -> PackedFloat32Array:
	var key := _cache_key("cloth-constraints", [mesh_to_ref,stiffness,bend_stiffness,bending_from_topology])
	var cached: Variant = _read("cloth-constraints",key)
	if cached is Dictionary and cached.get("data") is PackedFloat32Array and cached.get("groups") is Array:
		var data: PackedFloat32Array = cached.data
		var groups: Array = cached.groups
		var count := 0
		var valid := data.size() % 4 == 0
		for group in groups:
			if not group is Dictionary or group.get("offset",-1) != count or int(group.get("count",-1)) < 0:
				valid = false
				break
			count += int(group.count)
		if valid and count * 4 == data.size():
			_constraint_groups = groups
			return data
	var data := super._build_mesh_constraints(mesh_to_ref)
	_write("cloth-constraints",key,{"data":data,"groups":_constraint_groups})
	return data


func _body_signature() -> Array:
	var body := get_node_or_null(body_mesh) as MeshInstance3D
	if body == null or body.mesh == null or body.skin == null:
		return []
	var binds: Array = []
	for i in body.skin.get_bind_count():
		binds.append([body.skin.get_bind_bone(i),body.skin.get_bind_name(i),body.skin.get_bind_pose(i)])
	var bones: Array = []
	for i in _skeleton_node.get_bone_count():
		bones.append([_skeleton_node.get_bone_name(i),_skeleton_node.get_bone_parent(i),_skeleton_node.get_bone_rest(i)])
	var mesh_id := body.mesh.get_instance_id()
	if not _mesh_digests.has(mesh_id):
		var geometry: Array = []
		for surface in body.mesh.get_surface_count():
			var arrays := body.mesh.surface_get_arrays(surface)
			geometry.append([arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_INDEX],arrays[Mesh.ARRAY_BONES],arrays[Mesh.ARRAY_WEIGHTS]])
		if _mesh_digests.size() >= MEMORY_CACHE_LIMIT:
			_mesh_digests.erase(_mesh_digests.keys()[0])
		_mesh_digests[mesh_id] = _digest(geometry)
	var body_to_ref: Transform3D = _ref_node.global_transform.affine_inverse() * body.global_transform
	# NodePath содержит автоматически созданное имя HD-обёртки (@Node3D@N),
	# которое различается у двух одинаковых экземпляров. Геометрия, bind/rest
	# и относительный transform полностью задают результат без имени обёртки.
	return [_mesh_digests[mesh_id],body_to_ref,binds,bones,body_collider_voxel_resolution]


func _build_collider_mesh() -> void:
	var key := _cache_key("cloth-collider")
	if not key.is_empty(): key = _cache_key("cloth-collider",_body_signature())
	var cached: Variant = _read("cloth-collider",key)
	if cached is Array:
		_collider_tris = cached
		return
	super._build_collider_mesh()
	_write("cloth-collider",key,_collider_tris)


func _build_adjacency() -> Dictionary:
	var key := _cache_key("cloth-adjacency")
	var cached: Variant = _read("cloth-adjacency",key)
	if cached is Dictionary and cached.get("counts") is PackedInt32Array and cached.get("offsets") is PackedInt32Array and cached.get("list") is PackedInt32Array:
		if cached.counts.size() == _particle_count and cached.offsets.size() == _particle_count:
			return cached
	var data := super._build_adjacency()
	_write("cloth-adjacency",key,data)
	return data


func _build_peer_proxy_indices() -> PackedInt32Array:
	var key := _cache_key("cloth-peer-proxy",[peer_collider_voxel_resolution])
	var cached: Variant = _read("cloth-peer-proxy",key)
	if cached is PackedInt32Array and cached.size() % 3 == 0:
		return cached
	var data := super._build_peer_proxy_indices()
	_write("cloth-peer-proxy",key,data)
	return data

func _exit_tree() -> void:
	# Reparent не повторяет _ready(). Буферы должны пережить выход из дерева,
	# но новая позиция/масштаб требуют старта с актуального скелета.
	reset_simulation()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Vendor сначала сбрасывает _gpu_init_done и отвязывает Texture2DRD,
		# затем передаёт только список RID в render-thread lambda (без self).
		# Поэтому освобождение безопасно и при удалении всей подготовленной сцены.
		super._exit_tree()


## Content-addressed GPU storage, accessed exclusively on the render thread.
## Values contain no actor/Node references. Only readonly shader inputs belong here;
## poses, lambdas, skin targets, colliders, output images and normals stay local.
static var _shared_gpu_buffers: Dictionary = {}
var _shared_gpu_keys: Array[String] = []


func _immutable_buffer_create(kind: String, size: int, data: PackedByteArray) -> RID:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	var key := kind + ":" + str(size) + ":" + hash.finish().hex_encode()
	if not _shared_gpu_buffers.has(key):
		_shared_gpu_buffers[key] = {"rid":_rd.storage_buffer_create(size,data),"bytes":size,"refs":0}
	_shared_gpu_buffers[key].refs += 1
	_shared_gpu_keys.append(key)
	return _shared_gpu_buffers[key].rid


## Call only on the render thread (including diagnostic readback).
static func shared_gpu_stats() -> Dictionary:
	var result := {"buffers":_shared_gpu_buffers.size(),"bytes":0,"references":0,"entries":{}}
	for key in _shared_gpu_buffers:
		var item: Dictionary = _shared_gpu_buffers[key]
		result.bytes += item.bytes
		result.references += item.refs
		result.entries[key] = {"rid":item.rid.get_id(),"bytes":item.bytes,"refs":item.refs}
	return result


func _queue_gpu_cleanup(rids: Array) -> void:
	var keys := _shared_gpu_keys.duplicate()
	_shared_gpu_keys.clear()
	# Capture a script resource and plain keys, never a dying solver instance.
	var script: GDScript = get_script()
	RenderingServer.call_on_render_thread(func() -> void:
		script._free_gpu_resources(rids,keys))


static func _free_gpu_resources(rids: Array, keys: Array) -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null: return
	var pooled: Dictionary = {}
	for key in keys:
		assert(_shared_gpu_buffers.has(key),"unbalanced cloth GPU reference")
		pooled[_shared_gpu_buffers[key].rid] = true
	# Descriptor sets precede resources in the vendor list. They must disappear
	# before the last shared storage reference is freed.
	for rid: RID in rids:
		if rid.is_valid() and not pooled.has(rid): rd.free_rid(rid)
	for key in keys:
		var item: Dictionary = _shared_gpu_buffers[key]
		item.refs -= 1
		if item.refs == 0:
			rd.free_rid(item.rid)
			_shared_gpu_buffers.erase(key)
