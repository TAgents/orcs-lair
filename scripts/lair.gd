extends Node3D

@onready var champion: Champion = $Champion
@onready var raiders_root: Node3D = $Raiders

var _ended: bool = false

func _ready() -> void:
	champion.died.connect(_on_champion_died)
	for r in raiders_root.get_children():
		if r is Raider:
			r.died.connect(_on_raider_died)

func _unhandled_input(event: InputEvent) -> void:
	if _ended:
		return
	if event.is_action_pressed("possess_toggle") and is_instance_valid(champion) and champion.is_alive():
		Game.toggle_possession(champion)

func _on_champion_died(_o: Orc) -> void:
	if _ended:
		return
	_ended = true
	if Game.possessed == champion:
		Game.set_mode(Game.Mode.LAIR, null)
	Game.end_game(false)

func _on_raider_died(_o: Orc) -> void:
	if _ended:
		return
	for r in raiders_root.get_children():
		if r is Raider and r.is_alive():
			return
	_ended = true
	Game.end_game(true)
