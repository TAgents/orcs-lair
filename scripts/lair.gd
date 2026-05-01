extends Node3D

const ScenarioRunnerCls: GDScript = preload("res://scripts/test/scenario_runner.gd")

@onready var raiders_root: Node3D = $Raiders
@onready var _sun: DirectionalLight3D = $DirectionalLight3D

var _champions: Array[Champion] = []
var _ended: bool = false
var _scenario_mode: bool = false

# Raid state. Tracked between _start_raid() and the subsequent return.
# When _raid_chests_looted == _raid_chests_total AND _raid_guards_dead ==
# _raid_guards_total, _raid_complete_pending_return flips true and the HUD
# prompts the player to press M. M then teleports the champion back to the
# lair interior and switches to LAIR mode.
signal raid_started
signal raid_completed

var _raid_active: bool = false
var _raid_chests_total: int = 0
var _raid_guards_total: int = 0
var _raid_chests_looted: int = 0
var _raid_guards_dead: int = 0
var _raid_complete_pending_return: bool = false

# Persistent (save format v6+). Each successful raid bumps this; subsequent
# raids spawn guards with stats scaled by the count, raising the difficulty
# curve over the course of a campaign.
var raids_completed: int = 0
const RAID_GUARD_HP_PER_RAID: float = 10.0
const RAID_GUARD_DAMAGE_PER_RAID: float = 1.0

func _ready() -> void:
	_collect_champions()
	Clock.time_changed.connect(_on_time_changed)
	_on_time_changed(Clock.time_of_day)

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
	# Restart key works from any state, including post-game-over, so the
	# player can recover from "LAIR FALLEN" without quitting the process.
	if event.is_action_pressed("restart_scene"):
		get_tree().reload_current_scene()
		return
	if _ended:
		return
	if event.is_action_pressed("possess_toggle"):
		_cycle_possession()
	elif event.is_action_pressed("build_toggle") and Game.mode != Game.Mode.POSSESSING:
		Game.toggle_build()
	elif event.is_action_pressed("build_cancel") and Game.mode == Game.Mode.BUILDING:
		Game.set_mode(Game.Mode.LAIR, null)
	elif event.is_action_pressed("world_map_toggle"):
		# When a raid finishes, M pulls the champion back to the lair instead
		# of toggling the world map. Otherwise standard toggle (gated as before).
		if _raid_complete_pending_return:
			_return_from_raid()
		elif Game.mode != Game.Mode.POSSESSING and Game.mode != Game.Mode.BUILDING:
			Game.toggle_world_map()
	elif event.is_action_pressed("world_dest_lair") and Game.mode == Game.Mode.WORLD_MAP:
		Game.set_mode(Game.Mode.LAIR, null)
	elif event.is_action_pressed("world_dest_raid") and Game.mode == Game.Mode.WORLD_MAP:
		_start_raid()
	elif event.is_action_pressed("attr_str"):
		_spend_attr_on_named("str")
	elif event.is_action_pressed("attr_vit"):
		_spend_attr_on_named("vit")
	elif event.is_action_pressed("attr_agi"):
		_spend_attr_on_named("agi")
	elif event.is_action_pressed("quick_save"):
		var ok := SaveSystem.save_to(QUICKSAVE_PATH)
		print("[lair] quicksave → %s : %s" % [QUICKSAVE_PATH, "OK" if ok else "FAILED"])
	elif event.is_action_pressed("quick_load"):
		var ok := SaveSystem.load_from(QUICKSAVE_PATH)
		print("[lair] quickload ← %s : %s" % [QUICKSAVE_PATH, "OK" if ok else "FAILED"])

# Routes attr_str/vit/agi key presses to the first alive Champion (the one
# the HUD tracks). No-op if that champion has zero unspent points.
func _spend_attr_on_named(stat: String) -> void:
	for c in _champions:
		if is_instance_valid(c) and c.is_alive():
			c.spend_attribute_point(stat)
			return

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
	_begin_raid()

# Per-raid bookkeeping. Wires chest loot signals + spawns guards, then
# emits raid_started so HUD/etc. can react.
func _begin_raid() -> void:
	_raid_active = true
	_raid_complete_pending_return = false
	_raid_chests_looted = 0
	_raid_guards_dead = 0
	var chests: Array = get_tree().get_nodes_in_group("treasure_chests")
	_raid_chests_total = chests.size()
	for c in chests:
		# Re-arm + scale gold_value by raids_completed before the raid starts.
		if c.has_method("scale_for_raid"):
			c.scale_for_raid(raids_completed)
		if c.has_signal("looted") and not c.looted.is_connected(_on_raid_chest_looted):
			c.looted.connect(_on_raid_chest_looted)
	_spawn_city_guards()
	raid_started.emit()

# Spawns 3 raiders inside the city as defenders. They reuse Raider's AI —
# pick nearest non-raider orc and chase — so the possessed champion gets
# resistance during a raid. Ramped down stats vs lair.tscn raiders so the
# raid feels like a skirmish, not a massacre.
func _spawn_city_guards() -> void:
	var raiders_root: Node3D = get_node_or_null("Raiders")
	if raiders_root == null:
		return
	_raid_guards_total = _CITY_GUARD_POSITIONS.size()
	# Scale guard stats by completed-raid count. The fresh raid is N=
	# raids_completed (not yet incremented), so wave 0 → base stats,
	# wave 1 → +10 hp +1 dmg, wave 2 → +20 hp +2 dmg, etc.
	var hp_bonus: float = float(raids_completed) * RAID_GUARD_HP_PER_RAID
	var dmg_bonus: float = float(raids_completed) * RAID_GUARD_DAMAGE_PER_RAID
	for i in _CITY_GUARD_POSITIONS.size():
		var pos: Vector3 = _CITY_GUARD_POSITIONS[i]
		var guard: Node = _CITY_GUARD_SCENE.instantiate()
		guard.name = "CityGuard_%d" % i
		raiders_root.add_child(guard)
		guard.global_position = pos
		(guard as Raider).max_hp = 30.0 + hp_bonus
		(guard as Raider).hp = (guard as Raider).max_hp
		(guard as Raider).damage = 6.0 + dmg_bonus
		(guard as Raider).move_speed = 3.6
		(guard as Raider).gold_drop = 8 + raids_completed
		guard.add_to_group("city_guards")
		guard.died.connect(_on_raid_guard_died)

func _on_raid_chest_looted(_chest: Node, _gold: int, _items: Array) -> void:
	if not _raid_active:
		return
	_raid_chests_looted += 1
	_check_raid_complete()

func _on_raid_guard_died(_orc: Node) -> void:
	if not _raid_active:
		return
	_raid_guards_dead += 1
	_check_raid_complete()

# Public read for HUD / scenarios. Snapshot of the current raid bookkeeping.
func raid_progress() -> Dictionary:
	return {
		"active": _raid_active,
		"chests_looted": _raid_chests_looted,
		"chests_total": _raid_chests_total,
		"guards_dead": _raid_guards_dead,
		"guards_total": _raid_guards_total,
		"pending_return": _raid_complete_pending_return,
	}

func _check_raid_complete() -> void:
	if not _raid_active:
		return
	if _raid_chests_looted < _raid_chests_total:
		return
	if _raid_guards_dead < _raid_guards_total:
		return
	_raid_active = false
	_raid_complete_pending_return = true
	raids_completed += 1
	raid_completed.emit()

# Press-M handler when raid finished: drop champion back inside the lair
# at the firepit and switch to LAIR mode (auto-unpossesses).
func _return_from_raid() -> void:
	_raid_complete_pending_return = false
	var champion: Champion = null
	for c in _champions:
		if is_instance_valid(c) and c.is_alive():
			champion = c
			break
	if champion != null:
		champion.teleport(0.0, 0.85, 0.0)
		champion.rotation.y = 0.0
	Game.set_mode(Game.Mode.LAIR, null)
	# Auto-quicksave on return so raid progress (gold, looted gear,
	# raids_completed) survives a crash or accidental window close.
	var ok: bool = SaveSystem.save_to(QUICKSAVE_PATH)
	print("[lair] auto-saved on raid return : %s" % ("OK" if ok else "FAILED"))

# Test-only hatch: instantly satisfy the raid-complete conditions and
# free any living city guards so the AI champion has no targets to chase
# post-return. Scenarios use this to verify the post-completion state
# without scripting full combat. Called via /root/Lair.complete_raid_for_test.
func complete_raid_for_test() -> void:
	if not _raid_active:
		return
	for g in get_tree().get_nodes_in_group("city_guards"):
		if is_instance_valid(g):
			g.queue_free()
	_raid_chests_looted = _raid_chests_total
	_raid_guards_dead = _raid_guards_total
	_check_raid_complete()

# Day/night cycle: rotates the lair's DirectionalLight3D around the world X
# axis so the sun's apparent altitude tracks Clock.time_of_day. Day-zero
# pitch was -65° (the original "low warm sun"); we sweep ±90° on either
# side so noon is straight down and midnight is straight up.
func _on_time_changed(time_of_day: float) -> void:
	if _sun == null:
		return
	# time_of_day 0=midnight, 0.25=sunrise, 0.5=noon, 0.75=sunset.
	# Map to sun pitch: midnight = +90° (sun behind world), noon = -90°
	# (straight down). Use sin curve so dawn/dusk pass smoothly.
	var pitch: float = -sin(time_of_day * TAU - PI * 0.5) * deg_to_rad(75.0) - deg_to_rad(15.0)
	_sun.rotation.x = pitch
	# Cool the light at night, warm it at day.
	var night_t: float = 0.0 if not Clock.is_night() else 1.0
	_sun.light_energy = lerp(0.55, 0.18, night_t)

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
