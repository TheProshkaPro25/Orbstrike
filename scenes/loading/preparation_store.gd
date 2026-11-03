class_name PreparationStore
extends RefCounted
## Неизменяемые производные расчёты. Геометрия/анимация не заменяются кэшем.
## Генератор пишет данные заранее; обычная игра только читает их или считает заново.
const DIRECTORY := "res://assets/prepared"
const SCHEMA := 1
static var enabled := true
static var writing_enabled := false
static var cache_directory := DIRECTORY
static var _sources: Dictionary = {}
static var _memory: Dictionary = {}
static var _hits := 0
static var _misses := 0
static var _writes := 0
static var _hash_usec := 0

static func source_key(source: PackedScene) -> String:
	if not enabled or source == null: return ""
	var path := source.resource_path
	if _sources.has(path): return _sources[path]
	# Без доступного источника не доверяем данным другого импорта/пакета.
	# Безопасный fallback также поддерживает экспорт без исходных GLB.
	if not FileAccess.file_exists(path):
		_sources[path] = ""
		return ""
	var begin := Time.get_ticks_usec()
	var digest := FileAccess.get_sha256(path)
	var import_digest := FileAccess.get_sha256(path + ".import") if FileAccess.file_exists(path + ".import") else ""
	var artifact_stamp := ""
	if not import_digest.is_empty():
		var config := ConfigFile.new()
		if config.load(path + ".import") == OK:
			var imported: String = config.get_value("remap","path","")
			var stamp_path := imported.get_basename()+".md5"
			if FileAccess.file_exists(stamp_path): artifact_stamp = FileAccess.get_sha256(stamp_path)
	# Учитывается и текущий импорт: raw GLB могли изменить ещё до reimport.
	var key := str([SCHEMA,Engine.get_version_info().hex,path,digest,import_digest,artifact_stamp]).sha256_text()
	_hash_usec += Time.get_ticks_usec()-begin
	_sources[path] = key
	return key

static func read_cache(kind: String, key: String) -> Variant:
	if not enabled or key.is_empty(): return null
	var path := _path(kind,key)
	if _memory.has(path):
		_hits += 1
		return _memory[path]
	if not FileAccess.file_exists(path):
		_misses += 1
		return null
	var file := FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
	if file == null:
		_misses += 1
		return null
	var contents: Variant = file.get_var(false)
	file.close()
	if not contents is Dictionary or contents.get("schema") != SCHEMA or contents.get("key") != key:
		_misses += 1
		return null
	var value: Variant = contents.get("data")
	_remember(path,value)
	_hits += 1
	return value

static func write_cache(kind: String, key: String, data: Variant) -> void:
	if not enabled or key.is_empty() or not writing_enabled: return
	DirAccess.make_dir_recursive_absolute(cache_directory)
	var path := _path(kind,key)
	var file := FileAccess.open_compressed(path,FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
	if file == null:
		push_error("Не удалось сохранить подготовку: " + path)
		return
	file.store_var({"schema":SCHEMA,"key":key,"data":data},false)
	file.close()
	_remember(path,data)
	_writes += 1

static func _path(kind: String, key: String) -> String:
	return cache_directory.path_join(kind.validate_filename()+"-"+key.sha256_text()+".pdat")

static func _remember(path: String, data: Variant) -> void:
	if not _memory.has(path) and _memory.size() >= 128:
		_memory.erase(_memory.keys()[0])
	_memory[path] = data

static func statistics() -> Dictionary:
	return {"hits":_hits,"misses":_misses,"writes":_writes,"source_hash_ms":_hash_usec/1000.0,"resident_entries":_memory.size()}

static func clear() -> void:
	_sources.clear()
	_memory.clear()
