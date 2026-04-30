extends Node

enum Mode { LAIR, POSSESSING }

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

func toggle_possession(target: Node) -> void:
	if mode == Mode.POSSESSING and possessed == target:
		set_mode(Mode.LAIR, null)
	else:
		set_mode(Mode.POSSESSING, target)

func end_game(victory: bool) -> void:
	game_over.emit(victory)
