extends Label3D
class_name DamageNumber

# Floating damage label. Spawned over the target on take_damage; tweens
# up + fades over ~1s then self-frees. Skipped in headless. Static
# spawn_at() is the only intended call site.

const SCENE_PATH: String = "res://scenes/effects/damage_number.tscn"
const RISE_HEIGHT: float = 1.4
const LIFETIME: float = 1.0

static func spawn_at(world_pos: Vector3, amount: float, color: Color, host: Node) -> void:
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
	var n3d := fx as Node3D
	n3d.global_position = world_pos
	var lbl := fx as Label3D
	lbl.text = "%d" % int(round(amount))
	lbl.modulate = color

func _ready() -> void:
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "position:y", position.y + RISE_HEIGHT, LIFETIME * 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 0.0, LIFETIME * 0.55).set_delay(LIFETIME * 0.30)
	var timer := Timer.new()
	timer.wait_time = LIFETIME + 0.05
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	add_child(timer)
	timer.start()
