extends Node3D

const ScenarioRunnerCls: GDScript = preload("res://scripts/test/scenario_runner.gd")

@onready var champion: Champion = $Champion
@onready var raiders_root: Node3D = $Raiders

var _ended: bool = false
var _scenario_mode: bool = false

func _ready() -> void:
	if _maybe_run_scenario():
		# Scenario mode: ScenarioRunner spawns/configures raiders and signals;
		# we connect the same per-raider death signals after the runner has
		# replaced them, which it does inside _wire_signals().
		# Champion-died signal is still ours to own.
		champion.died.connect(_on_champion_died)
		_scenario_mode = true
		return

	champion.died.connect(_on_champion_died)
	for r in raiders_root.get_children():
		if r is Raider:
			r.died.connect(_on_raider_died)

func _unhandled_input(event: InputEvent) -> void:
	if _ended or _scenario_mode:
		return
	if event.is_action_pressed("possess_toggle") and is_instance_valid(champion) and champion.is_alive():
		Game.toggle_possession(champion)
	elif event.is_action_pressed("build_toggle") and Game.mode != Game.Mode.POSSESSING:
		Game.toggle_build()
	elif event.is_action_pressed("build_cancel") and Game.mode == Game.Mode.BUILDING:
		Game.set_mode(Game.Mode.LAIR, null)

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

# --- Scenario harness ---------------------------------------------------------

func _maybe_run_scenario() -> bool:
	var args := OS.get_cmdline_user_args()
	var scenario_path := ""
	var output_path := ""
	var auto_possess := false
	for a in args:
		if a.begins_with("--scenario="):
			scenario_path = a.substr("--scenario=".length())
		elif a.begins_with("--output="):
			output_path = a.substr("--output=".length())
		elif a == "--auto-possess":
			auto_possess = true
	if scenario_path == "":
		return false

	var data := _load_scenario(scenario_path)
	if data.is_empty():
		push_error("[lair] failed to load scenario: %s" % scenario_path)
		get_tree().quit(2)
		return true

	var runner: ScenarioRunner = ScenarioRunnerCls.new()
	runner.name = "ScenarioRunner"
	add_child(runner)
	runner.setup(data, output_path, self)

	if auto_possess or bool(data.get("auto_possess", false)):
		# Possess the champion immediately (the bot can also do this via inputs).
		Game.toggle_possession(champion)
	return true

func _load_scenario(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		# Try res:// fallback for shipped scenarios.
		file = FileAccess.open("res://scenarios/" + path, FileAccess.READ)
	if file == null:
		return {}
	var raw := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary
