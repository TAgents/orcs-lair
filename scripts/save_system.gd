extends Node

# Save/load for the lair. JSON format (human-readable, diffable, easy to
# author by hand for tests). Persists Economy.gold, placed rooms, and
# champion progression (level + xp + max_hp + damage).
#
# Format v2:
#   {
#     "version": 2,
#     "gold": 100,
#     "rooms": [{"x": -4, "z": -4, "type": 0}, …],
#     "champions": [
#       {"name": "Champion",  "level": 3, "xp": 12, "max_hp": 140, "damage": 22},
#       {"name": "Champion2", "level": 1, "xp":  0, "max_hp": 100, "damage": 18}
#     ]
#   }
#
# v1 saves (no "champions" field) load cleanly — champions keep their
# scene-default stats.

const SAVE_FORMAT_VERSION: int = 2

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
	var champs: Array = []
	for c in get_tree().get_nodes_in_group("champions"):
		if c is Champion:
			champs.append({
				"name": String(c.name),
				"level": c.level,
				"xp": c.xp,
				"max_hp": c.max_hp,
				"damage": c.damage,
			})
	return {
		"version": SAVE_FORMAT_VERSION,
		"gold": Economy.gold,
		"rooms": rooms,
		"champions": champs,
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
	# v2: restore per-champion progression. v1 saves omit "champions" → keep
	# scene-default stats.
	for c_data in data.get("champions", []):
		var name_str: String = String(c_data.get("name", ""))
		var champ: Node = get_tree().root.get_node_or_null("Lair/" + name_str)
		if champ == null or not (champ is Champion):
			continue
		champ.level = int(c_data.get("level", 1))
		champ.xp = int(c_data.get("xp", 0))
		champ.max_hp = float(c_data.get("max_hp", champ.max_hp))
		champ.damage = float(c_data.get("damage", champ.damage))
		champ.hp = champ.max_hp  # full heal on load

func _build_controller() -> Node:
	var lair: Node = get_tree().root.get_node_or_null("Lair")
	if lair == null:
		return null
	return lair.get_node_or_null("BuildController")
