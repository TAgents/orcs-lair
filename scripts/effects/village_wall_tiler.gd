extends Node3D

# Lays Kenney wall.glb tiles along a list of authored segments to read as a
# distant ruined-village silhouette. Decorative only — no collision is
# added (the OutsideBoundary in the scene handles "you can't leave"). Each
# segment is a PackedVector3Array of two points (start, end). Skipped
# headlessly. Defaults are tuned for "broken stone walls 60–70m south of
# the lair, only 2 layers tall so they read as ruins, not a fortress".

@export var wall_glb: String = "res://assets/kenney_mini-dungeon/wall.glb"
@export var height_layers: int = 2
@export var layer_height: float = 1.1
@export var segments: Array = []  # Array of [Vector3 start, Vector3 end]

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not ResourceLoader.exists(wall_glb):
		return
	var scene: PackedScene = load(wall_glb)
	if scene == null:
		return
	for seg in segments:
		if seg is Array and seg.size() >= 2:
			_tile_segment(scene, seg[0] as Vector3, seg[1] as Vector3)

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
