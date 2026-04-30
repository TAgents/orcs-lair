extends Node3D
class_name BuildController

# Owns build mode: ghost preview that follows the mouse, click-to-place,
# occupancy tracking. No GridMap — uses simple integer grid math against
# a 1m cell size, snapping rooms by their (top-left) origin cell.

const CELL_SIZE: float = 1.0
const FLOOR_HALF_EXTENT: float = 12.0  # lair floor goes [-12, +12] on x/z
const ROOM_HEIGHT: float = 0.35

@onready var ghost: MeshInstance3D = $Ghost

var occupied: Dictionary = {}  # Vector2i -> Node3D (placed room)
var rooms_root: Node3D = null
var current_type: int = Room.Type.TRAINING
var _ghost_mat: StandardMaterial3D = null

signal room_placed(grid_origin: Vector2i, room_type: int)
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
	_ghost_mat.albedo_color = _ghost_color(_can_place(grid, room.footprint), room.color)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_select_1"):
		_select_type(Room.Type.SLEEPING)
	elif event.is_action_pressed("build_select_2"):
		_select_type(Room.Type.TRAINING)
	elif event.is_action_pressed("build_select_3"):
		_select_type(Room.Type.TREASURY)
	elif event.is_action_pressed("build_confirm"):
		_try_place()

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
	var n := Node3D.new()
	n.name = "%s_%d_%d" % [room.display_name, grid.x, grid.y]
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
	return n

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

func place_at_xy(x: int, z: int, room_type: int = -1) -> bool:
	return place_at_grid(Vector2i(x, z), room_type)

func place_at_grid(grid: Vector2i, room_type: int = -1) -> bool:
	var prev := current_type
	if room_type >= 0:
		current_type = room_type
	var room := Room.make(current_type)
	var ok := _can_place(grid, room.footprint)
	if ok:
		var node := _spawn_room_visual(grid, room)
		rooms_root.add_child(node)
		node.global_position = _grid_to_world_center(grid, room.footprint)
		for dx in room.footprint.x:
			for dz in room.footprint.y:
				occupied[Vector2i(grid.x + dx, grid.y + dz)] = node
		room_placed.emit(grid, current_type)
	current_type = prev
	return ok

func placed_count() -> int:
	# One placed room may occupy multiple cells; dedupe by node.
	var seen := {}
	for v in occupied.values():
		seen[v] = true
	return seen.size()
