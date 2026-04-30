extends Node
class_name WaveDirector

# Drives multi-wave raid progression. Wave 0 = whatever raiders the lair
# already has at start (defined in lair.tscn). Waves 1..N spawn after a
# grace period once the previous wave is wiped.
#
# Activated by lair.gd in interactive mode only — scenarios bypass this
# (their raiders are pre-baked in scenario JSON).

const RAIDER_SCENE: PackedScene = preload("res://scenes/raiders/raider.tscn")

@export var grace_period_s: float = 6.0
# Each wave defined as a list of spawn entries:
#   [{"position": [x, y, z], "max_hp": float, "damage": float, "move_speed": float}, ...]
# Wave 0 is implicit (the raiders already in lair.tscn).
@export var extra_waves: Array = [
	# Wave 1 — 4 raiders, slightly tougher
	[
		{"position": [-3, 0, 8], "max_hp": 30, "damage": 9, "move_speed": 4.0},
		{"position": [-1, 0, 8], "max_hp": 30, "damage": 9, "move_speed": 4.0},
		{"position": [ 1, 0, 8], "max_hp": 30, "damage": 9, "move_speed": 4.0},
		{"position": [ 3, 0, 8], "max_hp": 30, "damage": 9, "move_speed": 4.0},
	],
	# Wave 2 — 5 raiders, faster and tankier
	[
		{"position": [-4, 0, 9], "max_hp": 40, "damage": 11, "move_speed": 4.5},
		{"position": [-2, 0, 9], "max_hp": 40, "damage": 11, "move_speed": 4.5},
		{"position": [ 0, 0, 9], "max_hp": 40, "damage": 11, "move_speed": 4.5},
		{"position": [ 2, 0, 9], "max_hp": 40, "damage": 11, "move_speed": 4.5},
		{"position": [ 4, 0, 9], "max_hp": 40, "damage": 11, "move_speed": 4.5},
	],
]

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
	return extra_waves.size() + 1

func current_wave() -> int:
	return _current_wave

func _process(delta: float) -> void:
	if _state == State.IN_WAVE:
		if _all_raiders_dead():
			wave_cleared.emit(_current_wave)
			if _current_wave >= extra_waves.size():
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
	var wave_data: Array = extra_waves[_current_wave - 1]
	for r_data in wave_data:
		var r: Node = RAIDER_SCENE.instantiate()
		r.name = "WaveRaider_%d_%d" % [_current_wave, _raiders_root.get_child_count()]
		_raiders_root.add_child(r)
		var pos: Array = r_data.get("position", [0, 0, 9])
		r.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if r_data.has("max_hp"):
			r.max_hp = float(r_data["max_hp"])
			r.hp = r.max_hp
		if r_data.has("damage"):
			r.damage = float(r_data["damage"])
		if r_data.has("move_speed"):
			r.move_speed = float(r_data["move_speed"])
	_state = State.IN_WAVE
	wave_started.emit(_current_wave, total_waves())
