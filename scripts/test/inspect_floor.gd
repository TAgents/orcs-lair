@tool
extends SceneTree

func _initialize() -> void:
	var paths: Array = [
		"res://assets/kenney_mini-dungeon/floor.glb",
		"res://assets/kenney_mini-dungeon/wall.glb",
	]
	for p in paths:
		print("=== ", p)
		var scene: PackedScene = load(p)
		var n: Node = scene.instantiate()
		_walk(n, 0)
		# Print AABB of the first MeshInstance3D
		var mi: MeshInstance3D = _find_mi(n)
		if mi != null:
			print("  AABB: ", mi.mesh.get_aabb())
		n.queue_free()
	quit()

func _walk(n: Node, depth: int) -> void:
	print("  ".repeat(depth), n.name, " : ", n.get_class())
	for c in n.get_children():
		_walk(c, depth + 1)

func _find_mi(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r: MeshInstance3D = _find_mi(c)
		if r != null:
			return r
	return null
