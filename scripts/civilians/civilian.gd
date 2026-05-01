extends Orc
class_name Civilian

# City civilian. Faction "human" — but explicitly NOT in "champions" or
# "workers" groups (which raiders target) and NOT in "raiders" (which
# champions target). Result: pure ambient bystander, ignored by combat
# AI on both sides. They wander locally inside the city. Visually they
# reuse the Kenney character-human GLB (same model as raiders) but the
# faction string keeps them friendly to everything.

enum State { WANDER, PAUSE }

@export var wander_radius: float = 5.0
@export var wander_pause_min: float = 1.5
@export var wander_pause_max: float = 4.0

var _home: Vector3
var _wander_target: Vector3
var _wait: float = 0.0
var _state: int = State.WANDER

func _ready() -> void:
	faction = "human"
	add_to_group("civilians")
	_home = global_position
	_wander_target = _home
	_pick_new_wander_target()
	_swap_in_visual_model("res://assets/kenney_mini-dungeon/character-human.glb", 1.8)

func _physics_process(delta: float) -> void:
	if not is_alive():
		return
	match _state:
		State.WANDER:
			_step_wander(delta)
		State.PAUSE:
			velocity.x = 0.0
			velocity.z = 0.0
	apply_gravity(delta)
	move_and_slide()
	update_locomotion_anim()

func _step_wander(_delta: float) -> void:
	if _wait > 0.0:
		_wait -= get_physics_process_delta_time()
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var to_t: Vector3 = _wander_target - global_position
	to_t.y = 0.0
	if to_t.length() < 0.3:
		_wait = randf_range(wander_pause_min, wander_pause_max)
		_pick_new_wander_target()
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var dir: Vector3 = to_t.normalized()
		velocity.x = dir.x * move_speed * 0.5
		velocity.z = dir.z * move_speed * 0.5

func _pick_new_wander_target() -> void:
	var offset := Vector3(randf_range(-wander_radius, wander_radius), 0.0, randf_range(-wander_radius, wander_radius))
	_wander_target = _home + offset
