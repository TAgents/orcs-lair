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
var _finish_scheduled: bool = false
var _victory: bool = false
# Set by Game.game_over signal — distinct from _victory which is the
# "all_raiders_dead" path. game_over_eq criterion reads this.
var _game_over_state: String = "none"
var _hits_landed: int = 0
var _hits_taken: int = 0
var _dodges_used: int = 0
var _raiders_killed: int = 0
var _bot: ProbeBot = null
var _lair: Node3D = null
var _champion: Node = null
var _initial_raider_count: int = 0

# Screenshot capture. Two opt-in modes (both require running WITHOUT
# --headless so a render context exists):
#   "screenshots": [{"t": 1.5, "path": "/tmp/frames/baseline_start.png"}]
#   "screenshot_every_s": 0.5, "screenshot_dir": "/tmp/frames/baseline"
# Mixing the two is allowed.
var _screenshots_pending: Array = []
var _screenshot_every_s: float = 0.0
var _screenshot_dir: String = ""
var _screenshot_next_t: float = 0.0
var _screenshot_seq: int = 0

func setup(scenario_data: Dictionary, out_path: String, lair_node: Node3D) -> void:
	scenario = scenario_data
	output_path = out_path
	_lair = lair_node
	max_duration_s = float(scenario.get("max_duration_s", 60.0))

	_apply_seed()
	Economy.reset()
	Inventory.clear()
	Clock.reset()
	Research.reset()
	if not Game.game_over.is_connected(_on_game_over):
		Game.game_over.connect(_on_game_over)
	_game_over_state = "none"
	_setup_screenshots()
	_trim_champions()
	_apply_champion_overrides()
	_replace_raiders()
	_attach_bot()
	_wire_signals()

func _trim_champions() -> void:
	# Default: scenarios run with the named "Champion" only. Multi-champion
	# scenarios opt in with `"multi_champion": true` so existing tests stay
	# stable when new champions are added to lair.tscn.
	if bool(scenario.get("multi_champion", false)):
		return
	for c in _lair.get_tree().get_nodes_in_group("champions"):
		if c.name != "Champion":
			c.queue_free()

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
	# Apply hp last so it overrides the max_hp reset above. Lets scenarios
	# spawn the champion already damaged (e.g. for regen tests).
	if ov.has("hp"):
		_champion.hp = float(ov["hp"])

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
		if r_data.has("gold_drop"):
			r.gold_drop = int(r_data["gold_drop"])
		if r_data.has("drop_item_id"):
			r.drop_item_id = String(r_data["drop_item_id"])

func _attach_bot() -> void:
	_bot = ProbeBot.new()
	_bot.name = "ProbeBot"
	_bot.load_sequence(scenario.get("inputs", []))
	_lair.add_child(_bot)

func _setup_screenshots() -> void:
	_screenshots_pending = scenario.get("screenshots", []).duplicate()
	_screenshots_pending.sort_custom(func(a, b): return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	_screenshot_every_s = float(scenario.get("screenshot_every_s", 0.0))
	_screenshot_dir = String(scenario.get("screenshot_dir", ""))
	_screenshot_next_t = 0.0
	_screenshot_seq = 0
	if _screenshot_every_s > 0.0 and _screenshot_dir == "":
		_screenshot_dir = "/tmp/scenario_frames/" + String(scenario.get("name", "unnamed"))
	if (_screenshots_pending.size() > 0 or _screenshot_every_s > 0.0) and _is_headless():
		print("[runner] note: screenshots requested but running --headless; capture disabled")

func _is_headless() -> bool:
	# Headless platform exposes no rendering driver — viewport texture is unusable.
	return DisplayServer.get_name() == "headless"

func _capture_screenshot(path: String) -> void:
	if path == "" or _is_headless():
		return
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		return
	var dir_path: String = path.get_base_dir()
	if dir_path != "":
		DirAccess.make_dir_recursive_absolute(dir_path)
	var err: int = img.save_png(path)
	if err == OK:
		print("[runner] screenshot ", path)
	else:
		push_warning("[runner] screenshot failed (%d) → %s" % [err, path])

func _step_screenshots() -> void:
	while _screenshots_pending.size() > 0 and float(_screenshots_pending[0].get("t", 0.0)) <= _t:
		var entry: Dictionary = _screenshots_pending.pop_front()
		_capture_screenshot(String(entry.get("path", "")))
	if _screenshot_every_s > 0.0 and _t >= _screenshot_next_t:
		var path: String = "%s/frame_%05d.png" % [_screenshot_dir, _screenshot_seq]
		_capture_screenshot(path)
		_screenshot_seq += 1
		_screenshot_next_t = float(_screenshot_seq) * _screenshot_every_s

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
	_step_screenshots()
	if _t >= max_duration_s:
		_finish(false, "timeout")

func _on_champion_died(_o) -> void:
	if _finish_scheduled:
		return
	_victory = false
	_finish_scheduled = true
	_finish.call_deferred(false, "champion_dead")

func _on_raider_died(_o) -> void:
	_raiders_killed += 1
	if _initial_raider_count > 0 and _raiders_killed >= _initial_raider_count and not _finish_scheduled:
		_victory = true
		# Deferred so any further processing within the same frame's signal
		# chain (e.g. champion's post-take_damage kill-credit) completes
		# before we snapshot the result. Without this, multi-kill swings
		# under-report XP because _collect_results runs mid-iteration.
		_finish_scheduled = true
		_finish.call_deferred(true, "all_raiders_dead")

func _on_raider_damaged(_o, _amount: float) -> void:
	_hits_landed += 1

func _on_champion_damaged(_o, _amount: float) -> void:
	_hits_taken += 1

func _on_game_over(victory: bool) -> void:
	_game_over_state = "victory" if victory else "defeat"

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
	if crit.has("gold_gte"):
		var want: int = int(crit["gold_gte"])
		if Economy.gold < want:
			ok = false
			reasons.append("gold_gte want>=%d got=%d" % [want, Economy.gold])
	if crit.has("gold_eq"):
		var want: int = int(crit["gold_eq"])
		if Economy.gold != want:
			ok = false
			reasons.append("gold_eq want=%d got=%d" % [want, Economy.gold])
	if crit.has("champion_z_lt"):
		var want: float = float(crit["champion_z_lt"])
		var got: float = _champion.global_position.z if _champion != null and is_instance_valid(_champion) else INF
		if got >= want:
			ok = false
			reasons.append("champion_z_lt want<%.2f got=%.2f" % [want, got])
	if crit.has("game_over_eq"):
		var want: String = String(crit["game_over_eq"])
		if _game_over_state != want:
			ok = false
			reasons.append("game_over_eq want=%s got=%s" % [want, _game_over_state])
	if crit.has("captives_eq"):
		var want: int = int(crit["captives_eq"])
		var got: int = int(_lair.captives) if _lair != null and "captives" in _lair else 0
		if got != want:
			ok = false
			reasons.append("captives_eq want=%d got=%d" % [want, got])
	if crit.has("research_points_gte"):
		var want: int = int(crit["research_points_gte"])
		if Research.points < want:
			ok = false
			reasons.append("research_points_gte want>=%d got=%d" % [want, Research.points])
	if crit.has("research_unlocked_has"):
		var want: String = String(crit["research_unlocked_has"])
		if not Research.unlocked.has(want):
			ok = false
			reasons.append("research_unlocked_has want=%s unlocked=%s" % [want, str(Research.unlocked)])
	if crit.has("food_eq"):
		var want: int = int(crit["food_eq"])
		if Economy.food != want:
			ok = false
			reasons.append("food_eq want=%d got=%d" % [want, Economy.food])
	if crit.has("workers_alive_eq"):
		var want: int = int(crit["workers_alive_eq"])
		var got: int = 0
		for w in _lair.get_tree().get_nodes_in_group("workers"):
			if w is Worker and w.is_alive():
				got += 1
		if got != want:
			ok = false
			reasons.append("workers_alive_eq want=%d got=%d" % [want, got])
	if crit.has("workers_classed_eq"):
		var want: int = int(crit["workers_classed_eq"])
		var got: int = 0
		for w in _lair.get_tree().get_nodes_in_group("workers"):
			if w is Worker and w.is_alive() and String(w.worker_class) != "":
				got += 1
		if got != want:
			ok = false
			reasons.append("workers_classed_eq want=%d got=%d" % [want, got])
	if crit.has("ore_eq"):
		var want: int = int(crit["ore_eq"])
		if Economy.ore != want:
			ok = false
			reasons.append("ore_eq want=%d got=%d" % [want, Economy.ore])
	if crit.has("ore_gte"):
		var want: int = int(crit["ore_gte"])
		if Economy.ore < want:
			ok = false
			reasons.append("ore_gte want>=%d got=%d" % [want, Economy.ore])
	if crit.has("day_eq"):
		var want: int = int(crit["day_eq"])
		if Clock.day_index != want:
			ok = false
			reasons.append("day_eq want=%d got=%d" % [want, Clock.day_index])
	if crit.has("raid_active_eq"):
		var want: bool = bool(crit["raid_active_eq"])
		var got: bool = false
		if _lair != null and _lair.has_method("raid_progress"):
			var rp: Dictionary = _lair.raid_progress()
			got = bool(rp.get("active", false))
		if got != want:
			ok = false
			reasons.append("raid_active_eq want=%s got=%s" % [want, got])
	if crit.has("raids_completed_eq"):
		var want: int = int(crit["raids_completed_eq"])
		var got: int = int(_lair.raids_completed) if _lair != null and "raids_completed" in _lair else 0
		if got != want:
			ok = false
			reasons.append("raids_completed_eq want=%d got=%d" % [want, got])
	if crit.has("raiders_alive_gte"):
		var want: int = int(crit["raiders_alive_gte"])
		var got: int = _query_raiders_alive()
		if got < want:
			ok = false
			reasons.append("raiders_alive_gte want>=%d got=%d" % [want, got])
	if crit.has("mode_eq"):
		var want: String = String(crit["mode_eq"])
		var got: String = _query_mode_name()
		if got != want:
			ok = false
			reasons.append("mode_eq want=%s got=%s" % [want, got])
	if crit.has("possessed_name_eq"):
		var want: String = String(crit["possessed_name_eq"])
		var got: String = _query_possessed_name()
		if got != want:
			ok = false
			reasons.append("possessed_name_eq want=%s got=%s" % [want, got])
	if crit.has("champion_damage_eq"):
		var want: float = float(crit["champion_damage_eq"])
		var got: float = _query_champion_damage()
		if absf(got - want) > 0.001:
			ok = false
			reasons.append("champion_damage_eq want=%.1f got=%.1f" % [want, got])
	if crit.has("champion_level_eq"):
		var want: int = int(crit["champion_level_eq"])
		var got: int = _query_champion_level()
		if got != want:
			ok = false
			reasons.append("champion_level_eq want=%d got=%d" % [want, got])
	if crit.has("inventory_count_eq"):
		var want: int = int(crit["inventory_count_eq"])
		var got: int = Inventory.count()
		if got != want:
			ok = false
			reasons.append("inventory_count_eq want=%d got=%d" % [want, got])
	if crit.has("inventory_has"):
		var want_id: String = String(crit["inventory_has"])
		if not Inventory.has_item(want_id):
			ok = false
			reasons.append("inventory_has want=%s items=%s" % [want_id, str(Inventory.items())])
	if crit.has("champion_hp_gte"):
		var want: float = float(crit["champion_hp_gte"])
		var got: float = _champion.hp if _champion != null and is_instance_valid(_champion) else 0.0
		if got < want:
			ok = false
			reasons.append("champion_hp_gte want>=%.1f got=%.1f" % [want, got])
	if crit.has("champion_level_gte"):
		var want: int = int(crit["champion_level_gte"])
		var got: int = _query_champion_level()
		if got < want:
			ok = false
			reasons.append("champion_level_gte want>=%d got=%d" % [want, got])
	return {"pass": ok, "reasons": reasons}

func _query_champion_level() -> int:
	if _champion != null and is_instance_valid(_champion) and "level" in _champion:
		return int(_champion.level)
	return 0

func _query_champion_xp() -> int:
	if _champion != null and is_instance_valid(_champion) and "xp" in _champion:
		return int(_champion.xp)
	return 0

func _query_champion_damage() -> float:
	if _champion != null and is_instance_valid(_champion) and _champion.has_method("effective_damage"):
		return float(_champion.effective_damage())
	return 0.0

func _query_raiders_alive() -> int:
	var raiders_root: Node = _lair.get_node_or_null("Raiders")
	if raiders_root == null:
		return 0
	var n: int = 0
	for r in raiders_root.get_children():
		if r is Raider and r.is_alive():
			n += 1
	return n

func _query_mode_name() -> String:
	match Game.mode:
		Game.Mode.LAIR: return "LAIR"
		Game.Mode.POSSESSING: return "POSSESSING"
		Game.Mode.BUILDING: return "BUILDING"
		Game.Mode.WORLD_MAP: return "WORLD_MAP"
	return "UNKNOWN"

func _query_possessed_name() -> String:
	if Game.possessed != null and is_instance_valid(Game.possessed):
		return String(Game.possessed.name)
	return ""

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
	var n: int = 0
	for w in _lair.get_tree().get_nodes_in_group("workers"):
		if w is Worker and w.is_working():
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
		"gold": Economy.gold,
		"possessed": _query_possessed_name(),
		"champion_damage": _query_champion_damage(),
		"champion_level": _query_champion_level(),
		"champion_xp": _query_champion_xp(),
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
