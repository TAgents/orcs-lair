extends CanvasLayer

@onready var mode_label: Label = $Root/ModeLabel
@onready var hp_bar: ProgressBar = $Root/HPBar
@onready var hp_label: Label = $Root/HPBar/HPLabel
@onready var banner: Label = $Root/Banner

var _champion: Champion = null

func _ready() -> void:
	Game.mode_changed.connect(_on_mode_changed)
	Game.game_over.connect(_on_game_over)
	banner.visible = false
	_refresh_mode()
	_find_champion()

func _process(_delta: float) -> void:
	if _champion != null and is_instance_valid(_champion):
		hp_bar.max_value = _champion.max_hp
		hp_bar.value = _champion.hp
		hp_label.text = "%d / %d" % [int(_champion.hp), int(_champion.max_hp)]

func _find_champion() -> void:
	var champs := get_tree().get_nodes_in_group("champions")
	if champs.size() > 0 and champs[0] is Champion:
		_champion = champs[0]

func _on_mode_changed(_m: int) -> void:
	_refresh_mode()

func _refresh_mode() -> void:
	if Game.mode == Game.Mode.POSSESSING:
		mode_label.text = "POSSESSING — Tab to release"
	else:
		mode_label.text = "LAIR — Tab to possess champion"

func _on_game_over(victory: bool) -> void:
	banner.visible = true
	banner.text = "LAIR DEFENDED" if victory else "LAIR FALLEN"
