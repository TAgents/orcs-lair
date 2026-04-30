extends Node

# Save/load for the lair. JSON format (human-readable, diffable, easy to
# author by hand for tests). Persists Economy.gold + the placed-rooms list.
# Champion state is intentionally not persisted yet — Phase 4 progression
# (XP, levels, gear) will own that.
#
# Format v1:
#   {
#     "version": 1,
#     "gold": 100,
#     "rooms": [
#       {"x": -4, "z": -4, "type": 0},
#       {"x":  2, "z": -4, "type": 1}
#     ]
#   }

const SAVE_FORMAT_VERSION: int = 1

signal saved(path: String)
signal loaded(path: String)
signal save_failed(path: String, reason: String)
signal load_failed(path: String, reason: String)

func save_to(path: String) -> bool:
	var data: Dictionary = _gather_state()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		save_failed.emit(path, "could not open for write")
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	saved.emit(path)
	return true

func load_from(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_failed.emit(path, "file not found")
		return false
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		load_failed.emit(path, "json parse error")
		return false
	_apply_state(parsed as Dictionary)
	loaded.emit(path)
	return true

func _gather_state() -> Dictionary:
	var bc: Node = _build_controller()
	var rooms: Array = []
	if bc != null:
		var seen: Dictionary = {}
		for grid in bc.occupied:
			var room_node: Node3D = bc.occupied[grid]
			if seen.has(room_node):
				continue
			seen[room_node] = true
			rooms.append({
				"x": room_node.grid_origin.x,
				"z": room_node.grid_origin.y,
				"type": room_node.room_type,
			})
	return {
		"version": SAVE_FORMAT_VERSION,
		"gold": Economy.gold,
		"rooms": rooms,
	}

func _apply_state(data: Dictionary) -> void:
	var bc: Node = _build_controller()
	if bc != null:
		bc.clear_all()
	Economy.reset()
	Economy.gold = int(data.get("gold", Economy.STARTING_GOLD))
	if bc != null:
		for r in data.get("rooms", []):
			bc.place_at_xy(int(r["x"]), int(r["z"]), int(r["type"]), false)

func _build_controller() -> Node:
	var lair: Node = get_tree().root.get_node_or_null("Lair")
	if lair == null:
		return null
	return lair.get_node_or_null("BuildController")
