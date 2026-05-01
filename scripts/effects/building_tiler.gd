extends Node3D

# Builds rectangular wall.glb shells (one per "building" entry) with an
# optional doorway gap on a chosen side. Decorative — no collision is
# generated; OutsideBoundary handles the world bounds.
#
# Each building entry is a Dictionary:
#   {
#     "pos":  Vector3,  # NW (north-west) corner of the building, ground-level
#     "w":    int,      # width in tiles  (X span)
#     "d":    int,      # depth in tiles  (Z span)
#     "door": String,   # "N" | "E" | "S" | "W"
#     "door_w": int,    # door width in tiles (default 2)
#   }
#
# Skipped headlessly (same GLB-init constraint as the other tilers).

@export var wall_glb: String = "res://assets/kenney_mini-dungeon/wall.glb"
@export var height_layers: int = 3
@export var layer_height: float = 1.1
@export var buildings: Array = []

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not ResourceLoader.exists(wall_glb):
		return
	var scene: PackedScene = load(wall_glb)
	if scene == null:
		return
	for b in buildings:
		if b is Dictionary:
			_build_one(scene, b as Dictionary)

func _build_one(scene: PackedScene, b: Dictionary) -> void:
	var origin: Vector3 = b.get("pos", Vector3.ZERO)
	var w: int = int(b.get("w", 4))
	var d: int = int(b.get("d", 4))
	var door_side: String = String(b.get("door", "S"))
	var door_w: int = int(b.get("door_w", 2))
	# Run the four walls. step is the per-tile offset along the wall direction.
	# Side N runs along +X at z=origin.z; S along +X at z=origin.z+d;
	# W runs along +Z at x=origin.x; E along +Z at x=origin.x+w.
	_run(scene, origin,                            Vector3(1, 0, 0), w, "N", door_side, door_w)
	_run(scene, origin + Vector3(0, 0, d),         Vector3(1, 0, 0), w, "S", door_side, door_w)
	_run(scene, origin,                            Vector3(0, 0, 1), d, "W", door_side, door_w)
	_run(scene, origin + Vector3(w, 0, 0),         Vector3(0, 0, 1), d, "E", door_side, door_w)

func _run(scene: PackedScene, start: Vector3, step: Vector3, length: int,
		side: String, door_side: String, door_w: int) -> void:
	if length <= 0:
		return
	var has_door: bool = (side == door_side)
	var door_lo: int = (length - door_w) / 2
	var door_hi: int = door_lo + door_w
	for i in range(length):
		if has_door and i >= door_lo and i < door_hi:
			continue
		for layer in range(height_layers):
			var tile: Node3D = scene.instantiate() as Node3D
			tile.position = start + step * (float(i) + 0.5) + Vector3(0.0, float(layer) * layer_height, 0.0)
			add_child(tile)
