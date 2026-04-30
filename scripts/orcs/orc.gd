extends CharacterBody3D
class_name Orc

@export var max_hp: float = 30.0
@export var move_speed: float = 4.0
@export var damage: float = 10.0
@export var faction: String = "orc"

@onready var hp: float = max_hp

signal died(orc: Orc)
signal damaged(orc: Orc, amount: float)

const GRAVITY: float = 20.0
var _vulnerable: bool = true

func take_damage(amount: float, _source: Node = null) -> void:
	if not _vulnerable or hp <= 0.0:
		return
	hp = max(0.0, hp - amount)
	damaged.emit(self, amount)
	if hp <= 0.0:
		_die()

func _die() -> void:
	died.emit(self)
	set_physics_process(false)
	$CollisionShape3D.disabled = true
	# Visual: tip over and fade. Keep it cheap.
	var mesh: Node3D = get_node_or_null("Mesh")
	if mesh:
		var tween := create_tween()
		tween.tween_property(mesh, "rotation:x", deg_to_rad(-85.0), 0.3)
	await get_tree().create_timer(2.0).timeout
	queue_free()

func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

func set_vulnerable(v: bool) -> void:
	_vulnerable = v

func is_alive() -> bool:
	return hp > 0.0
