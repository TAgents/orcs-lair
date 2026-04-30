extends CanvasLayer

@onready var mode_label: Label = $Root/ModeLabel
@onready var hp_bar: ProgressBar = $Root/HPBar
@onready var hp_label: Label = $Root/HPBar/HPLabel
@onready var banner: Label = $Root/Banner
@onready var build_label: Label = $Root/BuildLabel
@onready var gold_label: Label = $Root/GoldLabel

var _champion: Champion = null
var _build_controller: BuildController = null

func _ready() -> void:
	Game.mode_changed.connect(_on_mode_changed)
	Game.game_over.connect(_on_game_over)
	Economy.gold_changed.connect(_on_gold_changed)
	banner.visible = false
	build_label.visible = false
	_refresh_mode()
	_refresh_gold()
	_find_champion()
	_find_build_controller()

func _process(_delta: float) -> void:
	if _champion != null and is_instance_valid(_champion):
		hp_bar.max_value = _champion.max_hp
		hp_bar.value = _champion.hp
		hp_label.text = "%d / %d" % [int(_champion.hp), int(_champion.max_hp)]

func _find_champion() -> void:
	var champs := get_tree().get_nodes_in_group("champions")
	if champs.size() > 0 and champs[0] is Champion:
		_champion = champs[0]

func _find_build_controller() -> void:
	var bc: Node = get_tree().get_first_node_in_group("build_controllers")
	if bc == null:
		# Fallback: walk siblings — BuildController is a sibling of HUD inside Lair.
		var lair: Node = get_parent()
		if lair != null:
			bc = lair.get_node_or_null("BuildController")
	if bc is BuildController:
		_build_controller = bc
		_build_controller.type_changed.connect(_on_build_type_changed)

func _on_mode_changed(_m: int) -> void:
	_refresh_mode()

func _refresh_mode() -> void:
	match Game.mode:
		Game.Mode.POSSESSING:
			mode_label.text = "POSSESSING — Tab to release"
			build_label.visible = false
		Game.Mode.BUILDING:
			mode_label.text = "BUILDING — B/Esc to exit"
			build_label.visible = true
			_refresh_build_label()
		_:
			mode_label.text = "LAIR — Tab NOW to possess · B to build"
			build_label.visible = false

func _on_build_type_changed(_t: int) -> void:
	_refresh_build_label()

func _refresh_build_label() -> void:
	if _build_controller == null:
		return
	var room := Room.make(_build_controller.current_type)
	build_label.text = "Selected: %s   [1 Sleeping · 2 Training · 3 Treasury · LMB place]" % room.display_name

func _on_game_over(victory: bool) -> void:
	banner.visible = true
	banner.text = "LAIR DEFENDED" if victory else "LAIR FALLEN"

func _on_gold_changed(_amount: int) -> void:
	_refresh_gold()

func _refresh_gold() -> void:
	gold_label.text = "Gold: %d" % Economy.gold
