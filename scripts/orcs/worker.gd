extends Orc
class_name Worker

@export var wander_radius: float = 4.0
@export var wander_pause_min: float = 1.5
@export var wander_pause_max: float = 4.0

var _home: Vector3
var _target: Vector3
var _wait: float = 0.0

func _ready() -> void:
	faction = "orc"
	add_to_group("orcs")
	add_to_group("workers")
	_home = global_position
	_target = _home
	_pick_new_target()

func _physics_process(delta: float) -> void:
	if not is_alive():
		return
	if _wait > 0.0:
		_wait -= delta
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var to_t: Vector3 = _target - global_position
		to_t.y = 0.0
		if to_t.length() < 0.3:
			_wait = randf_range(wander_pause_min, wander_pause_max)
			_pick_new_target()
			velocity.x = 0.0
			velocity.z = 0.0
		else:
			var dir: Vector3 = to_t.normalized()
			velocity.x = dir.x * move_speed * 0.5
			velocity.z = dir.z * move_speed * 0.5

	apply_gravity(delta)
	move_and_slide()

func _pick_new_target() -> void:
	var offset := Vector3(randf_range(-wander_radius, wander_radius), 0.0, randf_range(-wander_radius, wander_radius))
	_target = _home + offset
