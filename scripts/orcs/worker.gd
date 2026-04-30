extends Orc
class_name Worker

enum State { WANDER, GOING_TO_ROOM, WORKING }

@export var wander_radius: float = 4.0
@export var wander_pause_min: float = 1.5
@export var wander_pause_max: float = 4.0
@export var arrival_radius: float = 0.6

var _home: Vector3
var _wander_target: Vector3
var _wait: float = 0.0
var _state: int = State.WANDER
var assigned_room: Node3D = null

signal assigned(room: Node3D)
signal arrived_at_room(room: Node3D)

func _ready() -> void:
	faction = "orc"
	add_to_group("orcs")
	add_to_group("workers")
	_home = global_position
	_wander_target = _home
	_pick_new_wander_target()
	_subscribe_to_build_controller()
	_swap_in_visual_model("res://assets/kenney_mini-dungeon/character-orc.glb")

func assign_to(room: Node3D) -> void:
	if assigned_room != null and is_instance_valid(assigned_room):
		# Tell old room we left it (so it can accept another worker if relevant).
		if assigned_room.has_method("set_assigned_worker"):
			assigned_room.set_assigned_worker(null)
	assigned_room = room
	if room.has_method("set_assigned_worker"):
		room.set_assigned_worker(self)
	_state = State.GOING_TO_ROOM
	assigned.emit(room)

func is_assigned() -> bool:
	return assigned_room != null and is_instance_valid(assigned_room)

func is_working() -> bool:
	return _state == State.WORKING

func _physics_process(delta: float) -> void:
	if not is_alive():
		return
	# If our assigned room got demolished while we were going to / working at
	# it, fall back to wander so we're available for the next room.
	if (_state == State.GOING_TO_ROOM or _state == State.WORKING) and not is_assigned():
		_state = State.WANDER
		_pick_new_wander_target()
	match _state:
		State.WANDER:
			_step_wander(delta)
		State.GOING_TO_ROOM:
			_step_going_to_room()
		State.WORKING:
			velocity.x = 0.0
			velocity.z = 0.0
	apply_gravity(delta)
	move_and_slide()

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

func _step_going_to_room() -> void:
	if not is_assigned():
		_state = State.WANDER
		return
	var target: Vector3 = assigned_room.global_position
	var to_t: Vector3 = target - global_position
	to_t.y = 0.0
	if to_t.length() <= arrival_radius:
		velocity.x = 0.0
		velocity.z = 0.0
		_state = State.WORKING
		_home = global_position
		arrived_at_room.emit(assigned_room)
		return
	var dir: Vector3 = to_t.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed

func _pick_new_wander_target() -> void:
	var offset := Vector3(randf_range(-wander_radius, wander_radius), 0.0, randf_range(-wander_radius, wander_radius))
	_wander_target = _home + offset

# --- Auto-assignment from BuildController.room_placed ----------------------

func _subscribe_to_build_controller() -> void:
	# Walk up to find a sibling/cousin BuildController (sibling of lair root,
	# but parent of placed rooms). Workers live under lair root too.
	var lair: Node = get_tree().root.get_node_or_null("Lair")
	if lair == null:
		return
	var bc: Node = lair.get_node_or_null("BuildController")
	if bc != null and bc.has_signal("room_placed"):
		bc.room_placed.connect(_on_room_placed)

func _on_room_placed(grid: Vector2i, _room_type: int) -> void:
	# First-come-first-served: any idle worker grabs the new room.
	if is_assigned():
		return
	var lair: Node = get_tree().root.get_node_or_null("Lair")
	if lair == null:
		return
	var bc: Node = lair.get_node_or_null("BuildController")
	if bc == null:
		return
	# Find the room node by grid key in BuildController.occupied.
	if not bc.occupied.has(grid):
		return
	var room: Node3D = bc.occupied[grid]
	if room == null or not is_instance_valid(room):
		return
	# If another worker already grabbed it (via set_assigned_worker), skip.
	if room.has_method("get_assigned_worker") and room.get_assigned_worker() != null:
		return
	assign_to(room)
