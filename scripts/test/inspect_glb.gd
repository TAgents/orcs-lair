@tool
extends SceneTree

# One-shot GLB inspector. List nodes + animations for the Kenney models so we
# know what AnimationPlayer tracks (if any) we can hook up. Run with:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path orcs-lair --script scripts/test/inspect_glb.gd

const PATHS: Array = [
	"res://assets/kenney_mini-dungeon/character-orc.glb",
	"res://assets/kenney_mini-dungeon/character-human.glb",
]

func _initialize() -> void:
	for path in PATHS:
		print("=== ", path)
		if not ResourceLoader.exists(path):
			print("  (missing)")
			continue
		var scene: PackedScene = load(path)
		var root: Node = scene.instantiate()
		_walk(root, 0)
		root.queue_free()
	quit()

func _walk(n: Node, depth: int) -> void:
	var pad: String = "  ".repeat(depth)
	print("%s%s : %s" % [pad, n.name, n.get_class()])
	if n is AnimationPlayer:
		for a in n.get_animation_list():
			print("%s  anim: %s" % [pad, a])
	for c in n.get_children():
		_walk(c, depth + 1)
