class_name EventPlayer
extends Node
## Очередь анимаций: каждая запись - Callable (может быть корутиной). После опустошения - drained.

signal drained

var _queue: Array[Callable] = []
var _running := false
var _stopped := false


func push(anim: Callable) -> void:
	if _stopped:
		return
	_queue.append(anim)
	if not _running:
		_running = true
		call_deferred("_run")


func is_busy() -> bool:
	return _running or not _queue.is_empty()


## Остановить очередь перед удалением сцены; активная корутина принадлежит ей.
func stop() -> void:
	_stopped = true
	_queue.clear()


func _run() -> void:
	while not _stopped and not _queue.is_empty():
		var anim: Callable = _queue.pop_front()
		if anim.is_valid():
			await anim.call()
	_running = false
	if not _stopped:
		drained.emit()
