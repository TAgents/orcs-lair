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
		# WaveDirector starts in State.INACTIVE — it's a no-op until start()
		# is called, so it's safe to leave alive in scenario mode. Future
		# scenarios that want to exercise wave progression can drive it
		# directly via probe_bot.
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
	elif event.is_action_pressed("world_map_toggle") and Game.mode != Game.Mode.POSSESSING and Game.mode != Game.Mode.BUILDING:
		Game.toggle_world_map()
	elif event.is_action_pressed("world_dest_lair") and Game.mode == Game.Mode.WORLD_MAP:
		Game.set_mode(Game.Mode.LAIR, null)
	elif event.is_action_pressed("world_dest_raid") and Game.mode == Game.Mode.WORLD_MAP:
		_start_raid()
	elif event.is_action_pressed("quick_save"):
		var ok := SaveSystem.save_to(QUICKSAVE_PATH)
		print("[lair] quicksave → %s : %s" % [QUICKSAVE_PATH, "OK" if ok else "FAILED"])
	elif event.is_action_pressed("quick_load"):
		var ok := SaveSystem.load_from(QUICKSAVE_PATH)
		print("[lair] quickload ← %s : %s" % [QUICKSAVE_PATH, "OK" if ok else "FAILED"])

# World-map "Raid City": teleport the first alive champion just outside the
# lair's south entrance (top of the city path), facing south, and switch to
# POSSESSING so the player drives in real-time. Public so probe_bot can call
# it directly from scenarios that don't want to script the M-then-2 chain.
func start_raid() -> void:
	_start_raid()

const _CITY_GUARD_SCENE: PackedScene = preload("res://scenes/raiders/raider.tscn")
const _CITY_GUARD_POSITIONS: Array[Vector3] = [
	Vector3(-8, 0, 76),  # plaza north-west
	Vector3( 8, 0, 76),  # plaza north-east
	Vector3( 0, 0, 92),  # plaza south
]

func _start_raid() -> void:
	var champion: Champion = null
	for c in _champions:
		if is_instance_valid(c) and c.is_alive():
			champion = c
			break
	if champion == null:
		return
	champion.teleport(0.0, 0.85, 14.0)
	# Face the city (camera will end up north of champion looking south).
	champion.rotation.y = PI
	Game.set_mode(Game.Mode.POSSESSING, champion)
	_spawn_city_guards()

# Spawns 3 raiders inside the city as defenders. They reuse Raider's AI —
# pick nearest non-raider orc and chase — so the possessed champion gets
# resistance during a raid. Ramped down stats vs lair.tscn raiders so the
# raid feels like a skirmish, not a massacre.
func _spawn_city_guards() -> void:
	var raiders_root: Node3D = get_node_or_null("Raiders")
	if raiders_root == null:
		return
	for i in _CITY_GUARD_POSITIONS.size():
		var pos: Vector3 = _CITY_GUARD_POSITIONS[i]
		var guard: Node = _CITY_GUARD_SCENE.instantiate()
		guard.name = "CityGuard_%d" % i
		raiders_root.add_child(guard)
		guard.global_position = pos
		(guard as Raider).max_hp = 30.0
		(guard as Raider).hp = 30.0
		(guard as Raider).damage = 6.0
		(guard as Raider).move_speed = 3.6
		(guard as Raider).gold_drop = 8
		guard.add_to_group("city_guards")

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
