extends Orc
class_name Champion

@export var dodge_speed: float = 12.0
@export var dodge_duration: float = 0.3
@export var attack_cooldown: float = 0.5
@export var attack_range: float = 2.2

@onready var hitbox: Area3D = $Hitbox

var _attack_timer: float = 0.0
var _dodge_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _ai_target: Node3D = null

func _ready() -> void:
	faction = "orc"
	add_to_group("champions")
	add_to_group("orcs")
	hitbox.monitoring = false
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	hitbox.area_entered.connect(_on_hitbox_area_entered)

func _physics_process(delta: float) -> void:
	if not is_alive():
		return

	_attack_timer = max(0.0, _attack_timer - delta)
	if _dodge_timer > 0.0:
		_dodge_timer -= delta
		set_vulnerable(false)
		velocity.x = _dodge_dir.x * dodge_speed
		velocity.z = _dodge_dir.z * dodge_speed
	else:
		set_vulnerable(true)
		if Game.mode == Game.Mode.POSSESSING and Game.possessed == self:
			_player_input()
		else:
			_ai_step()

	apply_gravity(delta)
	move_and_slide()
	_face_velocity()

func _player_input() -> void:
	var raw := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"),
	)
	if raw.length() > 1.0:
		raw = raw.normalized()

	# Camera-relative movement: forward = camera's flat forward, right = camera's right.
	var move_dir := Vector3.ZERO
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		var fwd: Vector3 = -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right: Vector3 = cam.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		move_dir = right * raw.x + fwd * (-raw.y)
	else:
		move_dir = Vector3(raw.x, 0.0, raw.y)

	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed

	if Input.is_action_just_pressed("dodge") and move_dir.length() > 0.05:
		_dodge_dir = move_dir.normalized()
		_dodge_timer = dodge_duration

	if Input.is_action_just_pressed("attack") and _attack_timer <= 0.0:
		_swing()

func _ai_step() -> void:
	# Simple AI: hunt nearest raider when one exists, idle otherwise.
	if _ai_target == null or not is_instance_valid(_ai_target):
		_ai_target = _nearest("raiders")
	if _ai_target == null:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var to_target: Vector3 = _ai_target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() <= attack_range:
		velocity.x = 0.0
		velocity.z = 0.0
		if _attack_timer <= 0.0:
			_swing()
	else:
		var dir: Vector3 = to_target.normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed

func _swing() -> void:
	_attack_timer = attack_cooldown
	hitbox.monitoring = true
	# Snap-check anything already overlapping at swing start.
	for body in hitbox.get_overlapping_bodies():
		_on_hitbox_body_entered(body)
	await get_tree().create_timer(0.12).timeout
	hitbox.monitoring = false

func _on_hitbox_body_entered(body: Node) -> void:
	if body == self:
		return
	if body is Orc and body.faction != faction:
		body.take_damage(damage, self)

func _on_hitbox_area_entered(_area: Area3D) -> void:
	pass

func _face_velocity() -> void:
	var horiz := Vector2(velocity.x, velocity.z)
	if horiz.length() < 0.05:
		return
	var target_yaw: float = atan2(velocity.x, velocity.z) + PI
	rotation.y = lerp_angle(rotation.y, target_yaw, 0.25)

func _nearest(group: String) -> Node3D:
	var best: Node3D = null
	var best_d: float = INF
	for n in get_tree().get_nodes_in_group(group):
		if n is Node3D and n.has_method("is_alive") and n.is_alive():
			var d: float = global_position.distance_squared_to(n.global_position)
			if d < best_d:
				best_d = d
				best = n
	return best
