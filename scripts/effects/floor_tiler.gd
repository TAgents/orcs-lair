extends Node3D

# Spawns Kenney floor.glb instances across the lair floor at runtime so the
# visual breaks up into tiled stone instead of a flat brown box. Skipped
# headlessly (no rendering context — same GLB-init constraint as orcs).
# Also hides the underlying flat floor mesh so the tiles dominate; the
# StaticBody3D collision shape stays so physics is unchanged.

@export var floor_glb: String = "res://assets/kenney_mini-dungeon/floor.glb"
@export var half_extent: int = 12  # lair floor occupies [-12, +12]
@export var hide_solid_floor_path: NodePath = ^"../Floor/MeshInstance3D"

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not ResourceLoader.exists(floor_glb):
		return
	var scene: PackedScene = load(floor_glb)
	if scene == null:
		return
	for x in range(-half_extent, half_extent):
		for z in range(-half_extent, half_extent):
			var tile: Node3D = scene.instantiate() as Node3D
			tile.position = Vector3(float(x) + 0.5, 0.0, float(z) + 0.5)
			add_child(tile)
	var solid: Node = get_node_or_null(hide_solid_floor_path)
	if solid is MeshInstance3D:
		(solid as MeshInstance3D).visible = false
