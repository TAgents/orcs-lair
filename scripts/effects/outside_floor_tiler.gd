extends Node3D

# Lays Kenney floor.glb tiles across a rectangular outside area, optionally
# tinted by an albedo override (so the outside dirt reads visually distinct
# from the warm stone interior). An optional rectangular hole skips tiles
# that would conflict with the StonePath strip running through the same
# region. Headless-guarded so CI scenarios stay deterministic.

@export var floor_glb: String = "res://assets/kenney_mini-dungeon/floor.glb"
@export var x_min: int = -40
@export var x_max: int = 40
@export var z_min: int = 12
@export var z_max: int = 72
@export var y_offset: float = 0.0
# Tint applied as material_override on each tile's MeshInstance3D children.
# Default (1,1,1,1) leaves the GLB material untouched.
@export var albedo_override: Color = Color(1, 1, 1, 1)
# Optional axis-aligned hole — tiles whose centre falls inside are skipped.
# Use it to keep the dirt out of the stone-path strip.
@export var hole_x_min: int = 0
@export var hole_x_max: int = 0
@export var hole_z_min: int = 0
@export var hole_z_max: int = 0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not ResourceLoader.exists(floor_glb):
		return
	var scene: PackedScene = load(floor_glb)
	if scene == null:
		return
	var has_hole: bool = hole_x_max > hole_x_min and hole_z_max > hole_z_min
	var mat: StandardMaterial3D = null
	if albedo_override != Color(1, 1, 1, 1):
		mat = StandardMaterial3D.new()
		mat.albedo_color = albedo_override
		mat.roughness = 0.95
	for x in range(x_min, x_max):
		for z in range(z_min, z_max):
			var cx: float = float(x) + 0.5
			var cz: float = float(z) + 0.5
			if has_hole and cx >= float(hole_x_min) and cx <= float(hole_x_max) and cz >= float(hole_z_min) and cz <= float(hole_z_max):
				continue
			var tile: Node3D = scene.instantiate() as Node3D
			tile.position = Vector3(cx, y_offset, cz)
			add_child(tile)
			if mat != null:
				_apply_material(tile, mat)

func _apply_material(n: Node, mat: StandardMaterial3D) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
	for c in n.get_children():
		_apply_material(c, mat)
