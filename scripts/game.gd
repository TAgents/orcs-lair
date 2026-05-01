extends Node

enum Mode { LAIR, POSSESSING, BUILDING, WORLD_MAP }

# Direction A campaign goal: survive past day campaign_target_day. When
# Clock.day_index exceeds this number, lair.gd fires game_over(true).
# Adjustable per-run; defaults to 30 (Dungeon-Keeper-style "30 nights").
var campaign_target_day: int = 30

signal mode_changed(new_mode: Mode)
signal game_over(victory: bool)

var mode: Mode = Mode.LAIR
var possessed: Node = null

func set_mode(new_mode: Mode, target: Node = null) -> void:
	if new_mode == mode and target == possessed:
		return
	mode = new_mode
	possessed = target if new_mode == Mode.POSSESSING else null
	mode_changed.emit(mode)

func toggle_build() -> void:
	if mode == Mode.BUILDING:
		set_mode(Mode.LAIR, null)
	else:
		set_mode(Mode.BUILDING, null)

# World-map: only enterable from LAIR (not while possessing or building).
# Pressing M from WORLD_MAP returns to LAIR.
func toggle_world_map() -> void:
	if mode == Mode.WORLD_MAP:
		set_mode(Mode.LAIR, null)
	elif mode == Mode.LAIR:
		set_mode(Mode.WORLD_MAP, null)

func toggle_possession(target: Node) -> void:
	if mode == Mode.POSSESSING and possessed == target:
		set_mode(Mode.LAIR, null)
	else:
		set_mode(Mode.POSSESSING, target)

func end_game(victory: bool) -> void:
	game_over.emit(victory)
