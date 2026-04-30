extends Orc
class_name Champion

@export var dodge_speed: float = 12.0
@export var dodge_duration: float = 0.3
@export var attack_cooldown: float = 0.5
@export var attack_range: float = 2.2
@export var cleave_cooldown: float = 1.5
@export var cleave_damage_mult: float = 1.5
@export var cleave_size: Vector3 = Vector3(3.5, 1.4, 2.5)
@export var charge_cooldown: float = 3.0
@export var charge_speed: float = 14.0
@export var charge_duration: float = 0.4
@export var charge_damage_mult: float = 1.2

@onready var hitbox: Area3D = $Hitbox
@onready var hitbox_shape: CollisionShape3D = $Hitbox/CollisionShape3D

# RPG progression. XP threshold per level: 50 × current level.
# Level-up grants +20 max_hp, +2 base damage, and a full heal.
@export var level: int = 1
@export var xp: int = 0
const XP_PER_LEVEL_BASE: int = 50
const LEVEL_UP_HP_BONUS: int = 20
const LEVEL_UP_DAMAGE_BONUS: int = 2

signal xp_gained(new_xp: int, threshold: int)
signal leveled_up(new_level: int)

var _cleave_timer: float = 0.0
var _normal_hitbox_size: Vector3 = Vector3.ZERO
var _cleave_active: bool = false
var _charge_timer: float = 0.0
var _charge_remaining: float = 0.0
var _charge_dir: Vector3 = Vector3.ZERO
var _charge_active: bool = false
var _charge_already_hit: Dictionary = {}

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
	# .tscn shapes are shared between scene instances by default; duplicate so
	# cleave's temporary resize on one champion doesn't bleed into the other.
	hitbox_shape.shape = hitbox_shape.shape.duplicate()
	if hitbox_shape.shape is BoxShape3D:
		_normal_hitbox_size = (hitbox_shape.shape as BoxShape3D).size
	_swap_in_visual_model("res://assets/kenney_mini-dungeon/character-orc.glb")

func _physics_process(delta: float) -> void:
	if not is_alive():
		return

	_attack_timer = max(0.0, _attack_timer - delta)
	_cleave_timer = max(0.0, _cleave_timer - delta)
	_charge_timer = max(0.0, _charge_timer - delta)
	if _charge_remaining > 0.0:
		_charge_remaining -= delta
		set_vulnerable(false)
		velocity.x = _charge_dir.x * charge_speed
		velocity.z = _charge_dir.z * charge_speed
		_check_charge_hits()
		apply_gravity(delta)
		move_and_slide()
		if _charge_remaining <= 0.0:
			_charge_active = false
			_charge_already_hit.clear()
			set_vulnerable(true)
			hitbox.monitoring = false
		return
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

	# Charge can also be triggered with no movement input — uses current facing.

	if Input.is_action_just_pressed("skill_cleave") and _cleave_timer <= 0.0 and _attack_timer <= 0.0:
		_cleave()

	if Input.is_action_just_pressed("skill_charge") and _charge_timer <= 0.0:
		_start_charge()

func _ai_step() -> void:
	# Simple AI: hunt nearest raider when one exists, idle otherwise.
	if _ai_target == null or not is_instance_valid(_ai_target) or not _ai_target.is_alive():
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

# Cleave: wider hitbox + 1.5x damage, costs the regular attack cooldown plus
# a longer cleave cooldown. Hits every non-faction Orc in the expanded box,
# not just the first.
func _cleave() -> void:
	_attack_timer = attack_cooldown
	_cleave_timer = cleave_cooldown
	_cleave_active = true
	var box: BoxShape3D = hitbox_shape.shape as BoxShape3D
	if box != null:
		box.size = cleave_size
	hitbox.monitoring = true
	# Snap-check anything already overlapping. body_entered fires for the rest
	# during the active window — _cleave_active routes both paths through the
	# multiplier.
	for body in hitbox.get_overlapping_bodies():
		_on_hitbox_body_entered(body)
	await get_tree().create_timer(0.20).timeout
	hitbox.monitoring = false
	_cleave_active = false
	if box != null and _normal_hitbox_size != Vector3.ZERO:
		box.size = _normal_hitbox_size

func _on_hitbox_body_entered(body: Node) -> void:
	if body == self:
		return
	if body is Orc and body.faction != faction:
		var was_alive: bool = body.is_alive()
		if _charge_active:
			# Charge tracks per-body to avoid multi-hit on same enemy.
			if _charge_already_hit.has(body):
				return
			_charge_already_hit[body] = true
			body.take_damage(effective_damage() * charge_damage_mult, self)
		else:
			var dmg: float = effective_damage() * (cleave_damage_mult if _cleave_active else 1.0)
			body.take_damage(dmg, self)
		if was_alive and not body.is_alive():
			gain_xp(int(body.max_hp))

# Charge: dash forward (in input direction or current facing) at charge_speed
# for charge_duration seconds. Invulnerable, hits each enemy along the path
# at most once for charge_damage_mult × effective_damage. Cooldown gates.
func _start_charge() -> void:
	_charge_timer = charge_cooldown
	_charge_remaining = charge_duration
	_charge_active = true
	_charge_already_hit.clear()
	_charge_dir = _current_facing_or_input()
	hitbox.monitoring = true

func _current_facing_or_input() -> Vector3:
	# Prefer the player's current move-input vector; fall back to body facing.
	if Game.mode == Game.Mode.POSSESSING and Game.possessed == self:
		var raw := Vector2(
			Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"),
		)
		if raw.length() > 0.05:
			var cam: Camera3D = get_viewport().get_camera_3d()
			if cam != null:
				var fwd: Vector3 = -cam.global_transform.basis.z
				fwd.y = 0.0
				fwd = fwd.normalized()
				var right: Vector3 = cam.global_transform.basis.x
				right.y = 0.0
				right = right.normalized()
				return (right * raw.x + fwd * (-raw.y)).normalized()
	# Fallback: orc's local forward (-Z) in world space.
	var fb: Vector3 = -global_transform.basis.z
	fb.y = 0.0
	if fb.length() < 0.01:
		fb = Vector3.FORWARD
	return fb.normalized()

func _check_charge_hits() -> void:
	# Hitbox.body_entered fires once per enter; bodies already inside when
	# monitoring was just enabled don't fire it. Snap-check each frame.
	for body in hitbox.get_overlapping_bodies():
		_on_hitbox_body_entered(body)

# Per-swing damage = base damage + every active Training room's bonus.
# Active means a worker is in the room and WORKING. Walking the group is
# cheap because rooms count is small.
func effective_damage() -> float:
	var bonus: float = 0.0
	for room in get_tree().get_nodes_in_group("placed_rooms"):
		if room is PlacedRoom and room.room_type == Room.Type.TRAINING and room.is_active():
			bonus += PlacedRoom.TRAINING_DAMAGE_BONUS
	return damage + bonus

func _on_hitbox_area_entered(_area: Area3D) -> void:
	pass

func _face_velocity() -> void:
	var horiz := Vector2(velocity.x, velocity.z)
	if horiz.length() < 0.05:
		return
	var target_yaw: float = atan2(velocity.x, velocity.z) + PI
	# Lower lerp = slower, more deliberate turning. Higher values felt twitchy
	# in third-person because the camera follow reacts to body rotation,
	# which feeds back into camera-relative input — small directional inputs
	# became over-corrected.
	rotation.y = lerp_angle(rotation.y, target_yaw, 0.10)

func xp_threshold() -> int:
	return XP_PER_LEVEL_BASE * level

# Cooldown getters for HUD readouts. 0 = ready.
func attack_cooldown_remaining() -> float:
	return _attack_timer

func cleave_cooldown_remaining() -> float:
	return _cleave_timer

func charge_cooldown_remaining() -> float:
	return _charge_timer

func gain_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	while xp >= xp_threshold():
		xp -= xp_threshold()
		_level_up()
	xp_gained.emit(xp, xp_threshold())

func _level_up() -> void:
	level += 1
	max_hp += float(LEVEL_UP_HP_BONUS)
	damage += float(LEVEL_UP_DAMAGE_BONUS)
	hp = max_hp  # full heal on level-up
	leveled_up.emit(level)

# Test/debug: reset XP and level back to 1/0. Doesn't undo accumulated
# max_hp / damage from prior level-ups (those are stat changes, not
# progression — load_from re-applies them from the save).
func reset_progression() -> void:
	level = 1
	xp = 0

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
