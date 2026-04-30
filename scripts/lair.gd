extends Node3D

const ScenarioRunnerCls: GDScript = preload("res://scripts/test/scenario_runner.gd")

@onready var raiders_root: Node3D = $Raiders

var _champions: Array[Champion] = []
var _ended: bool = false
var _scenario_mode: bool = false

func _ready() -> void:
	_collect_champions()

	if _maybe_run_scenario():
		# Scenario mode: ScenarioRunner spawns/configures raiders.
		# Champion deaths are still ours to own (game-over when all dead).
		for c in _champions:
			c.died.connect(_on_champion_died)
		_scenario_mode = true
		# Disable wave director so it doesn't spawn extra raiders in scenarios.
		var wd_node := get_node_or_null("WaveDirector")
		if wd_node:
			wd_node.queue_free()
		return

	# Debug arg for interactive runs: skip raider spawn so the player can
	# explore lair / build mode without combat. Use as:
	#   godot --path orcs-lair ++ --no-raiders
	var no_raiders: bool = "--no-raiders" in OS.get_cmdline_user_args()
	if no_raiders:
		for r in raiders_root.get_children():
			r.queue_free()
		var wd_node := get_node_or_null("WaveDirector")
		if wd_node:
			wd_node.queue_free()

	for c in _champions:
		c.died.connect(_on_champion_died)
	for r in raiders_root.get_children():
		if r is Raider:
			r.died.connect(_on_raider_died)

	# Start wave progression: subsequent waves spawn after current is wiped.
	if not no_raiders:
		var wd: Node = get_node_or_null("WaveDirector")
		if wd != null:
			wd.wave_started.connect(_on_wave_started)
			wd.all_waves_cleared.connect(_on_all_waves_cleared)
			wd.start()

func _collect_champions() -> void:
	_champions.clear()
	for c in get_tree().get_nodes_in_group("champions"):
		if c is Champion:
			_champions.append(c)

const QUICKSAVE_PATH: String = "user://quicksave.json"

func _unhandled_input(event: InputEvent) -> void:
	# ProbeBot drives input via Input.action_press in scenarios, so this
	# handler runs even in scenario mode — that's intentional.
	if _ended:
		return
	if event.is_action_pressed("possess_toggle"):
		_cycle_possession()
	elif event.is_action_pressed("build_toggle") and Game.mode != Game.Mode.POSSESSING:
		Game.toggle_build()
	elif event.is_action_pressed("build_cancel") and Game.mode == Game.Mode.BUILDING:
		Game.set_mode(Game.Mode.LAIR, null)
	elif event.is_action_pressed("quick_save"):
		var ok := SaveSystem.save_to(QUICKSAVE_PATH)
		print("[lair] quicksave → %s : %s" % [QUICKSAVE_PATH, "OK" if ok else "FAILED"])
	elif event.is_action_pressed("quick_load"):
		var ok := SaveSystem.load_from(QUICKSAVE_PATH)
		print("[lair] quickload ← %s : %s" % [QUICKSAVE_PATH, "OK" if ok else "FAILED"])

# Tab cycles: NONE → champion[0] → champion[1] → … → champion[N-1] → NONE → ...
# Skips dead/freed champions automatically.
func _cycle_possession() -> void:
	var alive: Array[Champion] = []
	for c in _champions:
		if is_instance_valid(c) and c.is_alive():
			alive.append(c)
	if alive.is_empty():
		return

	if Game.mode != Game.Mode.POSSESSING:
		Game.set_mode(Game.Mode.POSSESSING, alive[0])
		return

	var idx := alive.find(Game.possessed)
	if idx == -1:
		# Currently possessing something not in the alive list — start over.
		Game.set_mode(Game.Mode.POSSESSING, alive[0])
		return
	if idx == alive.size() - 1:
		# Last champion → release.
		Game.set_mode(Game.Mode.LAIR, null)
	else:
		Game.set_mode(Game.Mode.POSSESSING, alive[idx + 1])

func _on_champion_died(_o: Orc) -> void:
	if _ended:
		return
	# If the dying champion was being possessed, drop possession so the cycle
	# can pick another one.
	if Game.possessed != null and not is_instance_valid(Game.possessed):
		Game.set_mode(Game.Mode.LAIR, null)
	elif Game.possessed != null and Game.possessed is Champion and not Game.possessed.is_alive():
		Game.set_mode(Game.Mode.LAIR, null)
	# Game over when ALL champions are dead.
	for c in _champions:
		if is_instance_valid(c) and c.is_alive():
			return
	_ended = true
	Game.end_game(false)

func _on_raider_died(_o: Orc) -> void:
	# Connect freshly-spawned wave raiders so we can also notice their deaths.
	# (Could also be done via group; this is direct.)
	pass

func _on_wave_started(wave_idx: int, total: int) -> void:
	# Connect this wave's raiders to ourselves for any per-death hooks.
	for r in raiders_root.get_children():
		if r is Raider and not r.died.is_connected(_on_raider_died):
			r.died.connect(_on_raider_died)
	print("[lair] wave %d/%d started" % [wave_idx + 1, total])

func _on_all_waves_cleared() -> void:
	if _ended:
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

	if (auto_possess or bool(data.get("auto_possess", false))) and not _champions.is_empty():
		# Possess the first champion immediately (the bot can also do this via inputs).
		Game.toggle_possession(_champions[0])
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
