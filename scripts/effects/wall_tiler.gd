extends Node3D

# Replaces the visible wall meshes with Kenney wall.glb tiles, stacked
# 4 layers high to clear the 4m wall collision shapes. The StaticBody3D
# collision shapes stay untouched — physics is unchanged. Skipped
# headlessly (same GLB-init constraint as floor/orc model swap).
#
# Wall layout: 4 outer edges with the south side split for the entrance
# gap (matches the existing WallSLeft / WallSRight collisions).

@export var wall_glb: String = "res://assets/kenney_mini-dungeon/wall.glb"
@export var height_layers: int = 4
@export var layer_height: float = 1.1
@export var hide_paths: Array[NodePath] = []

# Segment edges: [start, end] in world XZ, y is ground.
const SEGMENTS: Array = [
	[Vector3(-12, 0, -12), Vector3( 12, 0, -12)],  # North
	[Vector3(-12, 0, -12), Vector3(-12, 0,  12)],  # West
	[Vector3( 12, 0, -12), Vector3( 12, 0,  12)],  # East
	[Vector3(-12, 0,  12), Vector3( -2, 0,  12)],  # South-left (entrance gap)
	[Vector3(  2, 0,  12), Vector3( 12, 0,  12)],  # South-right
]

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not ResourceLoader.exists(wall_glb):
		return
	var scene: PackedScene = load(wall_glb)
	if scene == null:
		return
	for seg in SEGMENTS:
		_tile_segment(scene, seg[0], seg[1])
	for p in hide_paths:
		var n: Node = get_node_or_null(p)
		if n is MeshInstance3D:
			(n as MeshInstance3D).visible = false

func _tile_segment(scene: PackedScene, start: Vector3, end: Vector3) -> void:
	var dir: Vector3 = end - start
	var length: int = int(round(dir.length()))
	if length <= 0:
		return
	var step: Vector3 = dir / float(length)
	for i in range(length):
		var center: Vector3 = start + step * (float(i) + 0.5)
		for layer in range(height_layers):
			var tile: Node3D = scene.instantiate() as Node3D
			tile.position = Vector3(center.x, float(layer) * layer_height, center.z)
			add_child(tile)
