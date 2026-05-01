extends CPUParticles3D
class_name HitSparks

# One-shot spark burst on hit. Auto-frees after the longest particle dies
# so callers don't have to manage it. Skipped headlessly (no rendering).
#
# Spawn from anywhere via:
#   HitSparks.spawn_at(world_pos, some_node_in_tree)

const SCENE_PATH: String = "res://scenes/effects/hit_sparks.tscn"

static func spawn_at(world_pos: Vector3, host: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if host == null or not host.is_inside_tree():
		return
	if not ResourceLoader.exists(SCENE_PATH):
		return
	var scene: PackedScene = load(SCENE_PATH)
	var fx: Node = scene.instantiate()
	if fx == null:
		return
	host.get_tree().current_scene.add_child(fx)
	(fx as Node3D).global_position = world_pos
	(fx as CPUParticles3D).emitting = true

func _ready() -> void:
	one_shot = true
	emitting = true
	var t := Timer.new()
	t.wait_time = lifetime + 0.25
	t.one_shot = true
	t.timeout.connect(queue_free)
	add_child(t)
	t.start()
