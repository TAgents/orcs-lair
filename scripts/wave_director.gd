extends Node
class_name WaveDirector

# Drives multi-wave raid progression. Wave 0 = whatever raiders the lair
# already has at start (defined in lair.tscn). Waves 1..num_waves spawn
# procedurally — each wave gets more raiders, tougher stats, and bigger
# gold drops; every boss_every-th wave is a single fat boss instead of a
# crowd. compute_wave_spec(N) is pure (no spawning) so a future scenario
# hook can assert on growth without running real-time waves.
#
# Activated by lair.gd in interactive mode only — scenarios bypass this
# (their raiders are pre-baked in scenario JSON). Wave_director freed in
# scenario mode unless the scenario opts in via keep_wave_director:true.

const RAIDER_SCENE: PackedScene = preload("res://scenes/raiders/raider.tscn")

@export var grace_period_s: float = 12.0

# Procedural growth knobs. Tune in the inspector or editor; defaults give
# a 4-wave arc with roughly doubling difficulty by the boss.
@export var num_waves: int = 4
@export var base_raiders_per_wave: int = 4
@export var raider_growth_per_wave: int = 1
@export var base_hp: float = 30.0
@export var hp_growth_per_wave: float = 5.0
@export var base_damage: float = 8.0
@export var damage_growth_per_wave: float = 1.0
@export var base_speed: float = 4.0
@export var speed_growth_per_wave: float = 0.25
@export var base_gold_drop: int = 12
@export var gold_drop_growth: int = 3
# Every Nth wave is a boss wave: 1 raider with 3x HP, 1.5x damage, 3x gold.
@export var boss_every: int = 4
@export var boss_hp_mult: float = 3.0
@export var boss_damage_mult: float = 1.5
@export var boss_gold_mult: int = 3

enum State { INACTIVE, IN_WAVE, WAITING_TO_SPAWN, COMPLETED }

signal wave_started(wave_index: int, total_waves: int)
signal wave_cleared(wave_index: int)
signal all_waves_cleared

var _state: int = State.INACTIVE
var _current_wave: int = 0
var _grace_remaining: float = 0.0
var _raiders_root: Node3D = null

func start() -> void:
	if _state != State.INACTIVE:
		return
	_state = State.IN_WAVE
	_raiders_root = get_node_or_null("/root/Lair/Raiders")
	# Wave 0 is whatever's already there; emit event for HUD setup.
	wave_started.emit(0, total_waves())

func total_waves() -> int:
	# +1 for wave 0 (implicit static raiders).
	return num_waves + 1

func current_wave() -> int:
	return _current_wave

# Returns seconds until the next wave spawns, or -1.0 when not waiting
# (mid-wave / completed / inactive). HUD reads this to render the
# countdown next to the wave counter.
func seconds_until_next_wave() -> float:
	if _state != State.WAITING_TO_SPAWN:
		return -1.0
	return max(0.0, _grace_remaining)

# Pure: returns the raider spec list for wave N (1-indexed) without spawning.
# Each entry: {position, max_hp, damage, move_speed, gold_drop, is_boss}.
func compute_wave_spec(wave_index: int) -> Array:
	if wave_index <= 0 or wave_index > num_waves:
		return []
	var is_boss: bool = boss_every > 0 and (wave_index % boss_every == 0)
	var hp: float = base_hp + hp_growth_per_wave * float(wave_index - 1)
	var dmg: float = base_damage + damage_growth_per_wave * float(wave_index - 1)
	var spd: float = base_speed + speed_growth_per_wave * float(wave_index - 1)
	var gold: int = base_gold_drop + gold_drop_growth * (wave_index - 1)
	if is_boss:
		# Single fat boss spawning OUTSIDE the lair on the wilderness path.
		# It walks north toward the orcs through the entrance gap, giving
		# the player visible warning before contact.
		return [{
			"position": [0, 0, 28],
			"max_hp": hp * boss_hp_mult,
			"damage": dmg * boss_damage_mult,
			"move_speed": spd * 0.85,  # slightly slower — telegraphs the boss
			"gold_drop": gold * boss_gold_mult,
			"is_boss": true,
		}]
	var count: int = base_raiders_per_wave + raider_growth_per_wave * (wave_index - 1)
	var spec: Array = []
	# Spawn line: well outside the lair (z=22..28) on the wilderness, x
	# clustered around the entrance gap (x∈[-3, 3]) so they funnel through
	# without bumping the south walls. Walking distance ~22m → ~5s warning
	# at base_speed=4 before they reach the orcs.
	var z_pos: float = 22.0 + 1.5 * float(wave_index - 1)
	var span: float = float(count - 1)
	for i in count:
		var x: float = lerp(-3.0, 3.0, 0.0 if span == 0.0 else float(i) / span)
		spec.append({
			"position": [x, 0, z_pos],
			"max_hp": hp,
			"damage": dmg,
			"move_speed": spd,
			"gold_drop": gold,
			"is_boss": false,
		})
	return spec

func _process(delta: float) -> void:
	if _state == State.IN_WAVE:
		if _all_raiders_dead():
			wave_cleared.emit(_current_wave)
			if _current_wave >= num_waves:
				_state = State.COMPLETED
				all_waves_cleared.emit()
				return
			_state = State.WAITING_TO_SPAWN
			_grace_remaining = grace_period_s
	elif _state == State.WAITING_TO_SPAWN:
		_grace_remaining -= delta
		if _grace_remaining <= 0.0:
			_spawn_next_wave()

func _all_raiders_dead() -> bool:
	if _raiders_root == null:
		return true
	for r in _raiders_root.get_children():
		if r is Raider and r.is_alive():
			return false
	return true

func _spawn_next_wave() -> void:
	_current_wave += 1
	var wave_data: Array = compute_wave_spec(_current_wave)
	for r_data in wave_data:
		var r: Node = RAIDER_SCENE.instantiate()
		r.name = "WaveRaider_%d_%d" % [_current_wave, _raiders_root.get_child_count()]
		_raiders_root.add_child(r)
		var pos: Array = r_data.get("position", [0, 0, 9])
		r.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		r.max_hp = float(r_data["max_hp"])
		r.hp = r.max_hp
		r.damage = float(r_data["damage"])
		r.move_speed = float(r_data["move_speed"])
		r.gold_drop = int(r_data["gold_drop"])
	_state = State.IN_WAVE
	wave_started.emit(_current_wave, total_waves())
