extends Node3D
class_name PlacedRoom

# A placed room in the world. Tracks the room type, footprint, and a single
# assigned worker (capacity 1 for now). Workers self-assign on placement;
# UI-driven reassignment is a future PR.
#
# Per-tick effects (Phase 2 economy slice):
#   TREASURY  : +TREASURY_GOLD_PER_SEC per assigned worker, accumulated to
#               Economy.gold via fractional add (so 1g/s shows up cleanly
#               even at 60Hz physics ticks).
# Other room types are placeholders until Phase 4 progression lands.

const TREASURY_GOLD_PER_SEC: float = 1.0
const TRAINING_DAMAGE_BONUS: float = 10.0
const SLEEPING_HP_PER_SEC: float = 4.0
const SLEEPING_HEAL_RADIUS: float = 4.5

@export var room_type: int = 0
@export var footprint: Vector2i = Vector2i(2, 2)
@export var grid_origin: Vector2i = Vector2i.ZERO

var _assigned_worker: Node = null

signal worker_assigned(worker: Node)
signal worker_unassigned(worker: Node)

func _ready() -> void:
	add_to_group("placed_rooms")

func is_active() -> bool:
	# Active = has an assigned worker who's actually at the room (WORKING).
	if not has_assigned_worker():
		return false
	var w: Node = get_assigned_worker()
	return w is Worker and w.is_working()

func set_assigned_worker(w: Node) -> void:
	if _assigned_worker == w:
		return
	if _assigned_worker != null:
		worker_unassigned.emit(_assigned_worker)
	_assigned_worker = w
	if w != null:
		worker_assigned.emit(w)

func get_assigned_worker() -> Node:
	if _assigned_worker != null and not is_instance_valid(_assigned_worker):
		_assigned_worker = null
	return _assigned_worker

func has_assigned_worker() -> bool:
	return get_assigned_worker() != null

# --- Per-frame effects -------------------------------------------------------

func _process(delta: float) -> void:
	if not is_active():
		return
	if room_type == Room.Type.TREASURY:
		Economy.add_gold(TREASURY_GOLD_PER_SEC * delta)
	elif room_type == Room.Type.SLEEPING:
		_regen_nearby(delta)

func _regen_nearby(delta: float) -> void:
	var amount: float = SLEEPING_HP_PER_SEC * delta
	var center: Vector3 = global_position
	for o in get_tree().get_nodes_in_group("orcs"):
		if o is Orc and o.is_alive():
			var dx: float = o.global_position.x - center.x
			var dz: float = o.global_position.z - center.z
			if dx * dx + dz * dz <= SLEEPING_HEAL_RADIUS * SLEEPING_HEAL_RADIUS:
				o.heal(amount)
