extends Node3D
class_name BuildController

# Owns build mode: ghost preview that follows the mouse, click-to-place,
# occupancy tracking. No GridMap — uses simple integer grid math against
# a 1m cell size, snapping rooms by their (top-left) origin cell.

const CELL_SIZE: float = 1.0
const FLOOR_HALF_EXTENT: float = 12.0  # lair floor goes [-12, +12] on x/z
const ROOM_HEIGHT: float = 0.35
# Demolish refund decays with age:
#  - Within DEMOLISH_GRACE_S of placement: GRACE_FRAC (regret window — almost full refund)
#  - After DEMOLISH_LATE_S: LATE_FRAC (committed room, salvage value only)
#  - Linear interp between the two.
# Pre-decay default of 50% punished both quick mistakes and committed builds
# equally, which made placement feel risk-free and demolition feel uniformly
# bad. The decay rewards thoughtful placement: quick undos cost almost nothing,
# but tearing down a productive room takes a real hit.
const DEMOLISH_GRACE_S: float = 2.0
const DEMOLISH_GRACE_FRAC: float = 0.9
const DEMOLISH_LATE_S: float = 10.0
const DEMOLISH_LATE_FRAC: float = 0.25

@onready var ghost: MeshInstance3D = $Ghost

var occupied: Dictionary = {}  # Vector2i -> Node3D (placed room)
var rooms_root: Node3D = null
var current_type: int = Room.Type.TRAINING
var _ghost_mat: StandardMaterial3D = null

signal room_placed(grid_origin: Vector2i, room_type: int)
signal room_demolished(grid_origin: Vector2i, room_type: int, refund: int)
signal type_changed(new_type: int)

func _ready() -> void:
	rooms_root = Node3D.new()
	rooms_root.name = "PlacedRooms"
	add_child(rooms_root)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(1, 1, 1, 0.4)
	ghost.material_override = _ghost_mat
	Game.mode_changed.connect(_on_mode_changed)
	_apply_visual_for_type()
	_set_active(false)

func _on_mode_changed(new_mode: int) -> void:
	_set_active(new_mode == Game.Mode.BUILDING)

func _set_active(active: bool) -> void:
	visible = active
	set_process(active)
	set_process_unhandled_input(active)

func _process(_delta: float) -> void:
	var hit: Variant = _mouse_floor_hit()
	if hit == null:
		ghost.visible = false
		return
	ghost.visible = true
	var grid: Vector2i = _world_to_grid(hit)
	var room: Room = Room.make(current_type)
	ghost.global_position = _grid_to_world_center(grid, room.footprint)
	var placeable: bool = _can_place(grid, room.footprint) and Economy.can_afford(room.cost)
	_ghost_mat.albedo_color = _ghost_color(placeable, room.color)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_select_1"):
		_select_type(Room.Type.SLEEPING)
	elif event.is_action_pressed("build_select_2"):
		_select_type(Room.Type.TRAINING)
	elif event.is_action_pressed("build_select_3"):
		_select_type(Room.Type.TREASURY)
	elif event.is_action_pressed("build_select_4"):
		_select_type(Room.Type.MINE)
	elif event.is_action_pressed("build_select_5"):
		_select_type(Room.Type.KITCHEN)
	elif event.is_action_pressed("build_select_6"):
		_select_type(Room.Type.LIBRARY)
	elif event.is_action_pressed("build_confirm"):
		_try_place()
	elif event.is_action_pressed("build_demolish"):
		_try_demolish()

func _select_type(t: int) -> void:
	if current_type == t:
		return
	current_type = t
	_apply_visual_for_type()
	type_changed.emit(t)

func _apply_visual_for_type() -> void:
	var room: Room = Room.make(current_type)
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(room.footprint.x * CELL_SIZE, ROOM_HEIGHT, room.footprint.y * CELL_SIZE)
	ghost.mesh = box
	# Material is updated each frame to flash valid/invalid; color tinted from room.

func _try_place() -> void:
	var hit: Variant = _mouse_floor_hit()
	if hit == null:
		return
	var grid: Vector2i = _world_to_grid(hit)
	var room: Room = Room.make(current_type)
	if not _can_place(grid, room.footprint):
		return
	if not Economy.spend(room.cost, "place_%s" % room.display_name):
		return
	var node: Node3D = _spawn_room_visual(grid, room)
	rooms_root.add_child(node)
	node.global_position = _grid_to_world_center(grid, room.footprint)
	for dx in room.footprint.x:
		for dz in room.footprint.y:
			occupied[Vector2i(grid.x + dx, grid.y + dz)] = node
	room_placed.emit(grid, current_type)

# --- Grid math ---------------------------------------------------------------

func _world_to_grid(world: Vector3) -> Vector2i:
	# Origin cell is the (top-left) corner of the room in cell coordinates.
	var room: Room = Room.make(current_type)
	var gx: int = int(floor(world.x / CELL_SIZE)) - room.footprint.x / 2
	var gz: int = int(floor(world.z / CELL_SIZE)) - room.footprint.y / 2
	return Vector2i(gx, gz)

func _grid_to_world_center(grid: Vector2i, footprint: Vector2i) -> Vector3:
	var cx: float = (grid.x + footprint.x * 0.5) * CELL_SIZE
	var cz: float = (grid.y + footprint.y * 0.5) * CELL_SIZE
	return Vector3(cx, ROOM_HEIGHT * 0.5, cz)

func _can_place(grid: Vector2i, footprint: Vector2i) -> bool:
	for dx in footprint.x:
		for dz in footprint.y:
			var cell := Vector2i(grid.x + dx, grid.y + dz)
			if not _cell_in_bounds(cell):
				return false
			if occupied.has(cell):
				return false
	return true

func _cell_in_bounds(cell: Vector2i) -> bool:
	var lim: int = int(FLOOR_HALF_EXTENT)
	return cell.x >= -lim and cell.x < lim and cell.y >= -lim and cell.y < lim

# --- Visuals -----------------------------------------------------------------

func _spawn_room_visual(grid: Vector2i, room: Room) -> Node3D:
	var n := PlacedRoom.new()
	n.name = "%s_%d_%d" % [room.display_name, grid.x, grid.y]
	n.room_type = room.type
	n.footprint = room.footprint
	n.grid_origin = grid
	# Caller assigns global_position AFTER adding to the tree.
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(room.footprint.x * CELL_SIZE, ROOM_HEIGHT, room.footprint.y * CELL_SIZE)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = room.color
	mat.roughness = 0.6
	mat.emission_enabled = true
	mat.emission = room.color
	mat.emission_energy_multiplier = 0.25
	mesh.material_override = mat
	n.add_child(mesh)
	_add_room_border(n, room)
	return n

# Raised border around the room perimeter so the placed room reads as a
# room (not a flat floor tile). 4 thin BoxMeshes — no collision, so the
# possessed champion can walk straight through; visually obvious from
# any camera angle. Border colour is the room colour darkened.
const _BORDER_HEIGHT: float = 0.35
const _BORDER_THICKNESS: float = 0.15

func _add_room_border(parent: Node3D, room: Room) -> void:
	var fx: float = room.footprint.x * CELL_SIZE
	var fz: float = room.footprint.y * CELL_SIZE
	var border_color := Color(room.color.r * 0.55, room.color.g * 0.55, room.color.b * 0.55, 1)
	var border_mat := StandardMaterial3D.new()
	border_mat.albedo_color = border_color
	border_mat.roughness = 0.7
	border_mat.emission_enabled = true
	border_mat.emission = room.color
	border_mat.emission_energy_multiplier = 0.5
	# Four edges: N (-Z), S (+Z), W (-X), E (+X). Each is a thin slab
	# centred on the room's local origin (which is the floor tile centre,
	# y = ROOM_HEIGHT * 0.5 above the world floor).
	var slabs: Array = [
		[Vector3(0, _BORDER_HEIGHT * 0.5, -fz * 0.5), Vector3(fx, _BORDER_HEIGHT, _BORDER_THICKNESS)],
		[Vector3(0, _BORDER_HEIGHT * 0.5,  fz * 0.5), Vector3(fx, _BORDER_HEIGHT, _BORDER_THICKNESS)],
		[Vector3(-fx * 0.5, _BORDER_HEIGHT * 0.5, 0), Vector3(_BORDER_THICKNESS, _BORDER_HEIGHT, fz)],
		[Vector3( fx * 0.5, _BORDER_HEIGHT * 0.5, 0), Vector3(_BORDER_THICKNESS, _BORDER_HEIGHT, fz)],
	]
	for s in slabs:
		var bm := BoxMesh.new()
		bm.size = s[1]
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.position = s[0]
		mi.material_override = border_mat
		parent.add_child(mi)

func _ghost_color(valid: bool, base: Color) -> Color:
	if valid:
		return Color(base.r, base.g, base.b, 0.55)
	return Color(0.85, 0.15, 0.15, 0.55)

# --- Mouse → floor raycast ---------------------------------------------------

func _mouse_floor_hit() -> Variant:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = cam.project_ray_origin(mouse_pos)
	var dir: Vector3 = cam.project_ray_normal(mouse_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t: float = -origin.y / dir.y
	if t < 0.0:
		return null
	return origin + dir * t

# --- Public API for tests / external callers ---------------------------------

func place_at_xy(x: int, z: int, room_type: int = -1, pay_cost: bool = true) -> bool:
	return place_at_grid(Vector2i(x, z), room_type, pay_cost)

func place_at_grid(grid: Vector2i, room_type: int = -1, pay_cost: bool = true) -> bool:
	var prev := current_type
	if room_type >= 0:
		current_type = room_type
	var room := Room.make(current_type)
	var ok := _can_place(grid, room.footprint) and (not pay_cost or Economy.can_afford(room.cost))
	if ok:
		if pay_cost:
			Economy.spend(room.cost, "place_%s" % room.display_name)
		var node := _spawn_room_visual(grid, room)
		rooms_root.add_child(node)
		node.global_position = _grid_to_world_center(grid, room.footprint)
		for dx in room.footprint.x:
			for dz in room.footprint.y:
				occupied[Vector2i(grid.x + dx, grid.y + dz)] = node
		room_placed.emit(grid, current_type)
	current_type = prev
	return ok

func _try_demolish() -> void:
	var hit: Variant = _mouse_floor_hit()
	if hit == null:
		return
	var cell := Vector2i(int(floor(hit.x / CELL_SIZE)), int(floor(hit.z / CELL_SIZE)))
	if not occupied.has(cell):
		return
	var room_node: Node3D = occupied[cell]
	demolish_room_node(room_node)

# Public API for tests / external callers (RMB and scripted scenarios).
func demolish_at_xy(x: int, z: int) -> bool:
	var cell := Vector2i(x, z)
	if not occupied.has(cell):
		return false
	demolish_room_node(occupied[cell])
	return true

func demolish_room_node(room_node: Node3D) -> void:
	if room_node == null or not is_instance_valid(room_node):
		return
	var room_type: int = room_node.room_type if "room_type" in room_node else 0
	var grid_origin: Vector2i = room_node.grid_origin if "grid_origin" in room_node else Vector2i.ZERO
	var age: float = room_node.age_seconds() if room_node.has_method("age_seconds") else INF
	var refund: int = int(Room.make(room_type).cost * _refund_fraction(age))
	# Remove every cell that points to this node.
	var to_remove: Array = []
	for k in occupied:
		if occupied[k] == room_node:
			to_remove.append(k)
	for k in to_remove:
		occupied.erase(k)
	room_node.queue_free()
	if refund > 0:
		Economy.gold = Economy.gold + refund
	room_demolished.emit(grid_origin, room_type, refund)

func _refund_fraction(age_s: float) -> float:
	if age_s <= DEMOLISH_GRACE_S:
		return DEMOLISH_GRACE_FRAC
	if age_s >= DEMOLISH_LATE_S:
		return DEMOLISH_LATE_FRAC
	var t: float = (age_s - DEMOLISH_GRACE_S) / (DEMOLISH_LATE_S - DEMOLISH_GRACE_S)
	return lerp(DEMOLISH_GRACE_FRAC, DEMOLISH_LATE_FRAC, t)

func placed_count() -> int:
	# One placed room may occupy multiple cells; dedupe by node.
	var seen := {}
	for v in occupied.values():
		seen[v] = true
	return seen.size()

func clear_all() -> void:
	# Free every placed room and forget all occupancy. Workers stay assigned
	# to the now-freed nodes only until their next AI step (assigned_room
	# will fail is_instance_valid → state machine returns to WANDER on its
	# own).
	for child in rooms_root.get_children():
		child.queue_free()
	occupied.clear()
