extends Node3D
class_name TreasureChest

# A raidable lootable. When a champion's body enters the trigger Area3D
# the chest credits Economy.gold and pushes its item drops into the
# global Inventory autoload, then marks itself looted (one-shot) and
# hides its visual. Designed to be placed inside city buildings.
#
# Headless-safe: visual swap is skipped under DisplayServer == "headless"
# but the trigger logic still fires, so scenarios can verify loot flow
# without rendering.

signal looted(chest: TreasureChest, gold: int, items: Array)

@export var gold_value: int = 30
@export var items: Array[String] = []
@export var visual_glb: String = "res://assets/kenney_mini-dungeon/chest.glb"
@export var visual_scale: float = 1.4

var _looted: bool = false

@onready var trigger: Area3D = $Trigger
@onready var visual: MeshInstance3D = $Visual

func _ready() -> void:
	add_to_group("treasure_chests")
	trigger.body_entered.connect(_on_body_entered)
	# Swap in the Kenney chest visual when there's a render context, mirroring
	# Orc._swap_in_visual_model. Placeholder cube stays in headless / on miss.
	if DisplayServer.get_name() == "headless":
		return
	if not ResourceLoader.exists(visual_glb):
		return
	var scene: PackedScene = load(visual_glb)
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return
	visual.visible = false
	add_child(instance)
	(instance as Node3D).scale = Vector3(visual_scale, visual_scale, visual_scale)

func _on_body_entered(body: Node) -> void:
	if _looted:
		return
	if body == null or not (body is Champion):
		return
	_looted = true
	if gold_value > 0:
		Economy.add_gold(float(gold_value))
	for item_id in items:
		if item_id != "":
			Inventory.add(String(item_id))
	looted.emit(self, gold_value, items.duplicate())
	visible = false
	# Disable the trigger so subsequent overlaps don't re-fire any
	# lingering frame-late signals. Godot blocks direct mutation of
	# Area3D.monitoring inside body_entered — defer one tick.
	trigger.set_deferred("monitoring", false)
