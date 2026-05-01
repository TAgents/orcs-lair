extends Node

# Save/load for the lair. JSON format (human-readable, diffable, easy to
# author by hand for tests). Persists Economy.gold, placed rooms, and
# champion progression (level + xp + max_hp + damage).
#
# Format v6:
#   {
#     "version": 6,
#     "gold": 100,
#     "inventory": ["iron_axe", "leather_jerkin"],
#     "raids_completed": 2,
#     "rooms": [{"x": -4, "z": -4, "type": 0}, …],
#     "champions": [
#       {"name": "Champion", "level": 3, "xp": 12, "max_hp": 140, "damage": 22,
#        "gear": ["iron_axe", "warrior_charm"],
#        "attr_points": 1, "str": 2, "vit": 0, "agi": 0}
#     ]
#   }
#
# raids_completed is the meta-difficulty driver — each completed city raid
# bumps it, and the next raid spawns guards with +10 hp / +1 damage per
# completed raid. Persisting it carries that curve across runs.
#
# Backward-compatible: v1..v5 saves load cleanly. Missing fields default to
# zero across the board.

const SAVE_FORMAT_VERSION: int = 9

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
				"max_hp": c.max_hp - c.gear_max_hp_bonus_total(),
				"damage": c.damage,
				"gear": c.gear_item_ids(),
				"attr_points": c.attribute_points,
				"str": c.str_pts,
				"vit": c.vit_pts,
				"agi": c.agi_pts,
			})
	var lair: Node = get_tree().root.get_node_or_null("Lair")
	var raids_completed: int = 0
	if lair != null and "raids_completed" in lair:
		raids_completed = int(lair.raids_completed)
	return {
		"version": SAVE_FORMAT_VERSION,
		"gold": Economy.gold,
		"ore": Economy.ore,
		"food": Economy.food,
		"inventory": Inventory.items(),
		"raids_completed": raids_completed,
		"day_index": Clock.day_index,
		"time_of_day": Clock.time_of_day,
		"rooms": rooms,
		"champions": champs,
	}

func _apply_state(data: Dictionary) -> void:
	var bc: Node = _build_controller()
	if bc != null:
		bc.clear_all()
	Economy.reset()
	Economy.gold = int(data.get("gold", Economy.STARTING_GOLD))
	Economy.ore = int(data.get("ore", Economy.STARTING_ORE))
	Economy.food = int(data.get("food", Economy.STARTING_FOOD))
	Inventory.clear()
	for item_id in data.get("inventory", []):
		Inventory.add(String(item_id))
	# Restore day/time. Older saves (v1..v6) default to day 1 / sunrise.
	Clock.reset(int(data.get("day_index", 1)), float(data.get("time_of_day", 0.25)))
	var lair: Node = get_tree().root.get_node_or_null("Lair")
	if lair != null and "raids_completed" in lair:
		lair.raids_completed = int(data.get("raids_completed", 0))
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
		# Strip gear first so any pre-existing gear bonuses don't get
		# layered on top of the saved (gear-exclusive) max_hp.
		champ.unequip_all()
		champ.level = int(c_data.get("level", 1))
		champ.xp = int(c_data.get("xp", 0))
		champ.max_hp = float(c_data.get("max_hp", champ.max_hp))
		champ.damage = float(c_data.get("damage", champ.damage))
		champ.attribute_points = int(c_data.get("attr_points", 0))
		champ.str_pts = int(c_data.get("str", 0))
		champ.vit_pts = int(c_data.get("vit", 0))
		champ.agi_pts = int(c_data.get("agi", 0))
		for item_id in c_data.get("gear", []):
			champ.equip(String(item_id))
		champ.hp = champ.max_hp  # full heal on load

func _build_controller() -> Node:
	var lair: Node = get_tree().root.get_node_or_null("Lair")
	if lair == null:
		return null
	return lair.get_node_or_null("BuildController")
