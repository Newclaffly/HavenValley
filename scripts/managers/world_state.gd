extends Node
## Changes the player has made to the world (autoload "WorldState").
##
## Every harvestable thing has a permanent id (for example "tree:C5/tree_oak_a/12" or
## "forage:mushroom/031"). When it is harvested its id is recorded with the time it grows back.
## The SaveManager (Phase 6) will save to_dict() and restore it with from_dict(). Until the day
## cycle exists (Phase 6), regrowth is measured in seconds of play time.

## Emitted when something is harvested or grows back.
signal harvest_changed(id: String, harvested: bool)

var _harvested: Dictionary = {}  # id -> play time (seconds) when it grows back
var _play_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	_play_time += delta


func play_time() -> float:
	return _play_time


func is_harvested(id: String) -> bool:
	return _harvested.has(id)


## Record a harvest. regrow_seconds < 0 means it never grows back.
func mark_harvested(id: String, regrow_seconds: float) -> void:
	_harvested[id] = INF if regrow_seconds < 0.0 else _play_time + regrow_seconds
	harvest_changed.emit(id, true)


## Ids whose regrow time has passed. The caller decides when to restore them (for example only
## when the player is not standing on the spot) and then calls clear_harvested().
func due_for_regrowth(prefix: String = "") -> PackedStringArray:
	var due := PackedStringArray()
	for id: String in _harvested:
		if _harvested[id] <= _play_time and (prefix == "" or id.begins_with(prefix)):
			due.append(id)
	return due


func clear_harvested(id: String) -> void:
	if _harvested.erase(id):
		harvest_changed.emit(id, false)


func harvested_ids(prefix: String = "") -> PackedStringArray:
	var ids := PackedStringArray()
	for id: String in _harvested:
		if prefix == "" or id.begins_with(prefix):
			ids.append(id)
	return ids


## Forget everything (new game).
func reset() -> void:
	_harvested.clear()
	_play_time = 0.0


func to_dict() -> Dictionary:
	var remaining := {}
	for id: String in _harvested:
		remaining[id] = -1.0 if is_inf(_harvested[id]) else maxf(0.0, _harvested[id] - _play_time)
	return {"harvested": remaining, "play_time": _play_time}


func from_dict(data: Dictionary) -> void:
	reset()
	_play_time = float(data.get("play_time", 0.0))
	var remaining: Dictionary = data.get("harvested", {})
	for id: String in remaining:
		var left := float(remaining[id])
		_harvested[id] = INF if left < 0.0 else _play_time + left
