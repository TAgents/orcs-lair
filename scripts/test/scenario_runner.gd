extends Node
class_name ScenarioRunner

# Loads a scenario JSON, applies it to the lair, drives a ProbeBot, and emits
# a results JSON when the scenario completes (game_over, timeout, or input
# sequence end).

const RAIDER_SCENE: PackedScene = preload("res://scenes/raiders/raider.tscn")
const ATTACK_HIT_PRINT_PREFIX := "[hit] "

var scenario: Dictionary = {}
var output_path: String = ""
var max_duration_s: float = 60.0

var _t: float = 0.0
var _ended: bool = false
var _victory: bool = false
var _hits_landed: int = 0
var _hits_taken: int = 0
var _dodges_used: int = 0
var _raiders_killed: int = 0
var _bot: ProbeBot = null
var _lair: Node3D = null
var _champion: Node = null
var _initial_raider_count: int = 0

func setup(scenario_data: Dictionary, out_path: String, lair_node: Node3D) -> void:
	scenario = scenario_data
	output_path = out_path
	_lair = lair_node
	max_duration_s = float(scenario.get("max_duration_s", 60.0))

	_apply_seed()
	_apply_champion_overrides()
	_replace_raiders()
	_attach_bot()
	_wire_signals()

func _apply_seed() -> void:
	if scenario.has("seed"):
		var s: int = int(scenario["seed"])
		seed(s)
		print("[runner] seed=", s)

func _apply_champion_overrides() -> void:
	_champion = _lair.get_node_or_null("Champion")
	if _champion == null:
		push_error("[runner] no Champion node in lair")
		return
	var ov: Dictionary = scenario.get("champion", {})
	if ov.has("max_hp"):
		_champion.max_hp = float(ov["max_hp"])
		_champion.hp = _champion.max_hp
	if ov.has("damage"):
		_champion.damage = float(ov["damage"])
	if ov.has("move_speed"):
		_champion.move_speed = float(ov["move_speed"])
	if ov.has("position"):
		var p: Array = ov["position"]
		_champion.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))

func _replace_raiders() -> void:
	var raiders_root: Node3D = _lair.get_node_or_null("Raiders")
	if raiders_root == null:
		push_error("[runner] no Raiders node in lair")
		return
	for child in raiders_root.get_children():
		child.queue_free()

	var spec: Array = scenario.get("raiders", [])
	_initial_raider_count = spec.size()
	for i in spec.size():
		var r_data: Dictionary = spec[i]
		var r: Node = RAIDER_SCENE.instantiate()
		r.name = "Raider_%d" % i
		raiders_root.add_child(r)
		var pos: Array = r_data.get("position", [0, 0, 16])
		r.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if r_data.has("max_hp"):
			r.max_hp = float(r_data["max_hp"])
			r.hp = r.max_hp
		if r_data.has("damage"):
			r.damage = float(r_data["damage"])
		if r_data.has("move_speed"):
			r.move_speed = float(r_data["move_speed"])

func _attach_bot() -> void:
	_bot = ProbeBot.new()
	_bot.name = "ProbeBot"
	_bot.load_sequence(scenario.get("inputs", []))
	_lair.add_child(_bot)

func _wire_signals() -> void:
	# Runner owns scenario end-detection (independent of interactive Game.end_game).
	if _champion != null:
		_champion.damaged.connect(_on_champion_damaged)
		_champion.died.connect(_on_champion_died)
	for r in _lair.get_node("Raiders").get_children():
		if r.has_signal("died"):
			r.died.connect(_on_raider_died)
		if r.has_signal("damaged"):
			r.damaged.connect(_on_raider_damaged)
	# Empty raiders list ⇒ no death event will fire. Don't end early; let
	# the timeout drive resolution (e.g. bot_smoketest).

func _physics_process(delta: float) -> void:
	if _ended:
		return
	_t += delta
	if _t >= max_duration_s:
		_finish(false, "timeout")

func _on_champion_died(_o) -> void:
	_victory = false
	_finish(false, "champion_dead")

func _on_raider_died(_o) -> void:
	_raiders_killed += 1
	if _initial_raider_count > 0 and _raiders_killed >= _initial_raider_count:
		_victory = true
		_finish(true, "all_raiders_dead")

func _on_raider_damaged(_o, _amount: float) -> void:
	_hits_landed += 1

func _on_champion_damaged(_o, _amount: float) -> void:
	_hits_taken += 1

func _finish(_v: bool, reason: String) -> void:
	if _ended:
		return
	_ended = true
	if _bot != null:
		_bot.release_all()
	var pass_result: Dictionary = _evaluate()
	var results: Dictionary = _collect_results(pass_result, reason)
	_write_results(results)
	print("[runner] finished reason=%s pass=%s" % [reason, pass_result["pass"]])
	# Quit headless with appropriate exit code so CI/agents can grade.
	var code: int = 0 if pass_result["pass"] else 1
	get_tree().quit(code)

func _evaluate() -> Dictionary:
	var crit: Dictionary = scenario.get("pass_criteria", {})
	var reasons: Array = []
	var ok: bool = true
	if crit.has("champion_alive"):
		var want: bool = bool(crit["champion_alive"])
		var got: bool = _champion != null and is_instance_valid(_champion) and _champion.is_alive()
		if got != want:
			ok = false
			reasons.append("champion_alive want=%s got=%s" % [want, got])
	if crit.has("raiders_killed_eq"):
		var want: int = int(crit["raiders_killed_eq"])
		if _raiders_killed != want:
			ok = false
			reasons.append("raiders_killed_eq want=%d got=%d" % [want, _raiders_killed])
	if crit.has("raiders_killed_gte"):
		var want: int = int(crit["raiders_killed_gte"])
		if _raiders_killed < want:
			ok = false
			reasons.append("raiders_killed_gte want>=%d got=%d" % [want, _raiders_killed])
	if crit.has("max_duration_lte"):
		var want: float = float(crit["max_duration_lte"])
		if _t > want:
			ok = false
			reasons.append("max_duration_lte want<=%.2f got=%.2f" % [want, _t])
	if crit.has("rooms_placed_eq"):
		var want: int = int(crit["rooms_placed_eq"])
		var got: int = _query_rooms_placed()
		if got != want:
			ok = false
			reasons.append("rooms_placed_eq want=%d got=%d" % [want, got])
	if crit.has("workers_assigned_eq"):
		var want: int = int(crit["workers_assigned_eq"])
		var got: int = _query_workers_assigned()
		if got != want:
			ok = false
			reasons.append("workers_assigned_eq want=%d got=%d" % [want, got])
	if crit.has("workers_at_rooms_eq"):
		var want: int = int(crit["workers_at_rooms_eq"])
		var got: int = _query_workers_at_rooms()
		if got != want:
			ok = false
			reasons.append("workers_at_rooms_eq want=%d got=%d" % [want, got])
	return {"pass": ok, "reasons": reasons}

func _query_rooms_placed() -> int:
	var bc: Node = _lair.get_node_or_null("BuildController")
	if bc != null and bc.has_method("placed_count"):
		return int(bc.placed_count())
	return 0

func _query_workers_assigned() -> int:
	var n: int = 0
	for w in _lair.get_tree().get_nodes_in_group("workers"):
		if w.has_method("is_assigned") and w.is_assigned():
			n += 1
	return n

func _query_workers_at_rooms() -> int:
	# Worker is "at" its room if state == WORKING (Worker.State.WORKING == 2).
	var n: int = 0
	for w in _lair.get_tree().get_nodes_in_group("workers"):
		if "_state" in w and w._state == 2:
			n += 1
	return n

func _collect_results(pass_result: Dictionary, reason: String) -> Dictionary:
	var champion_hp: float = 0.0
	var champion_alive := false
	if _champion != null and is_instance_valid(_champion):
		champion_hp = _champion.hp
		champion_alive = _champion.is_alive()
	return {
		"scenario": scenario.get("name", ""),
		"end_reason": reason,
		"duration_s": snappedf(_t, 0.001),
		"victory": _victory,
		"pass": pass_result["pass"],
		"pass_reasons": pass_result["reasons"],
		"champion": {
			"alive": champion_alive,
			"hp_remaining": snappedf(champion_hp, 0.001),
			"hits_taken": _hits_taken,
		},
		"raiders": {
			"initial": _initial_raider_count,
			"killed": _raiders_killed,
			"hits_received": _hits_landed,
		},
		"dodges_used": _dodges_used,
		"rooms_placed": _query_rooms_placed(),
		"workers_assigned": _query_workers_assigned(),
		"workers_at_rooms": _query_workers_at_rooms(),
	}

func _write_results(results: Dictionary) -> void:
	if output_path == "":
		print(JSON.stringify(results, "\t"))
		return
	var f := FileAccess.open(output_path, FileAccess.WRITE)
	if f == null:
		push_error("[runner] could not open output: %s" % output_path)
		print(JSON.stringify(results, "\t"))
		return
	f.store_string(JSON.stringify(results, "\t"))
	f.close()
	print("[runner] wrote ", output_path)
