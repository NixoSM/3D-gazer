extends Node
## Per-level records, persisted to user://progress.cfg. Autoloaded as `Progress`.

const PATH := "user://progress.cfg"

var _config := ConfigFile.new()


func _ready() -> void:
	_config.load(PATH)


## Furthest progress ever reached on a level, in [0, 1].
func best_progress(level_id: String) -> float:
	return _config.get_value(level_id, "best_progress", 0.0)


func is_completed(level_id: String) -> bool:
	return _config.get_value(level_id, "completed", false)


## Fastest finish (s), or INF if never finished.
func best_time(level_id: String) -> float:
	return _config.get_value(level_id, "best_time", INF)


## Stores a finish time. Returns true if it is the fastest yet.
func record_time(level_id: String, seconds: float) -> bool:
	if seconds >= best_time(level_id):
		return false
	_config.set_value(level_id, "best_time", seconds)
	_config.save(PATH)
	return true


func best_chain(level_id: String) -> int:
	return _config.get_value(level_id, "best_chain", 0)


## Records a finished attempt. Returns true if it set a new best.
func record_attempt(level_id: String, progress: float, completed: bool, longest_chain: int) -> bool:
	var improved := progress > best_progress(level_id) + 0.0001
	if improved:
		_config.set_value(level_id, "best_progress", progress)
	if completed:
		_config.set_value(level_id, "completed", true)
	if longest_chain > best_chain(level_id):
		_config.set_value(level_id, "best_chain", longest_chain)
	_config.set_value(level_id, "attempts", int(_config.get_value(level_id, "attempts", 0)) + 1)
	_config.save(PATH)
	return improved
