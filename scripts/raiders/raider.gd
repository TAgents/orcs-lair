extends Orc
class_name Raider

@export var attack_cooldown: float = 0.7
@export var attack_range: float = 2.0
# Gold dropped to Economy on death. Wave_director and scenarios can override
# per-raider for tougher waves; the lair.tscn defaults stay modest so early
# waves don't flood gold.
@export var gold_drop: int = 10
# Item dropped to Inventory on death. Empty string = no drop. Boss waves
# and scenario raiders set this; lair.tscn defaults stay empty so only
# special encounters reward gear.
@export var drop_item_id: String = ""

@onready var hitbox: Area3D = $Hitbox

var _target: Node3D = null
var _attack_timer: float = 0.0

func _ready() -> void:
	faction = "raider"
	add_to_group("raiders")
	hitbox.monitoring = false
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	_swap_in_visual_model("res://assets/kenney_mini-dungeon/character-human.glb", 2.0)

func _physics_process(delta: float) -> void:
	if not is_alive():
		return
	_attack_timer = max(0.0, _attack_timer - delta)

	if _target == null or not is_instance_valid(_target) or not _target.is_alive():
		_target = _nearest_orc()

	if _target == null:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var to_t: Vector3 = _target.global_position - global_position
		to_t.y = 0.0
		if to_t.length() <= attack_range:
			velocity.x = 0.0
			velocity.z = 0.0
			if _attack_timer <= 0.0:
				_swing()
		else:
			var dir: Vector3 = to_t.normalized()
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed

	apply_gravity(delta)
	move_and_slide()
	_face_velocity()
	update_locomotion_anim()

func _swing() -> void:
	_attack_timer = attack_cooldown
	play_anim("attack-melee-right", true)
	hitbox.monitoring = true
	for body in hitbox.get_overlapping_bodies():
		_on_hitbox_body_entered(body)
	await get_tree().create_timer(0.15).timeout
	hitbox.monitoring = false

func _die() -> void:
	if gold_drop > 0:
		Economy.add_gold(float(gold_drop))
	if drop_item_id != "":
		Inventory.add(drop_item_id)
	super._die()

func _on_hitbox_body_entered(body: Node) -> void:
	if body == self:
		return
	if body is Orc and body.faction != faction:
		body.take_damage(damage, self)

func _face_velocity() -> void:
	var horiz := Vector2(velocity.x, velocity.z)
	if horiz.length() < 0.05:
		return
	var target_yaw: float = atan2(velocity.x, velocity.z) + PI
	rotation.y = lerp_angle(rotation.y, target_yaw, 0.25)

func _nearest_orc() -> Node3D:
	var best: Node3D = null
	var best_d: float = INF
	# Prefer champions (more dangerous), fall back to workers.
	var groups := ["champions", "workers"]
	for g in groups:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and n.has_method("is_alive") and n.is_alive():
				var d: float = global_position.distance_squared_to(n.global_position)
				if d < best_d:
					best_d = d
					best = n
		if best != null:
			return best
	return null
