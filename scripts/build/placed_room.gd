extends Node3D
class_name PlacedRoom

# A placed room in the world. Tracks the room type, footprint, and a single
# assigned worker (capacity 1 for now). Workers self-assign on placement;
# UI-driven reassignment is a future PR.

@export var room_type: int = 0
@export var footprint: Vector2i = Vector2i(2, 2)
@export var grid_origin: Vector2i = Vector2i.ZERO

var _assigned_worker: Node = null

signal worker_assigned(worker: Node)
signal worker_unassigned(worker: Node)

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
