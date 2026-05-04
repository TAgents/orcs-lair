extends CharacterBody3D
class_name Orc

@export var max_hp: float = 30.0
@export var move_speed: float = 4.0
@export var damage: float = 10.0
@export var faction: String = "orc"
# Out-of-combat regen. 0 = disabled (default). Heals regen_rate hp/sec
# while alive, hp < max_hp, and at least REGEN_OOC_DELAY seconds have
# passed since the last take_damage. Champion / Worker opt in via .tscn.
@export var regen_rate: float = 0.0
const REGEN_OOC_DELAY: float = 3.0

@onready var hp: float = max_hp

signal died(orc: Orc)
signal damaged(orc: Orc, amount: float)

const GRAVITY: float = 20.0
var _vulnerable: bool = true
# Wall-clock timestamp of the last take_damage hit. Initialised far in the
# past so a freshly-spawned damaged unit can immediately start regenerating.
var _last_damage_msec: int = -1000000
var _hp_label: Label3D = null

# AnimationPlayer of the swapped-in GLB model (Kenney Mini Dungeon ships
# rigged characters with idle/walk/sprint/attack-melee-*/die/interact-*).
# Null when running --headless (no model loaded).
var _anim_player: AnimationPlayer = null

func take_damage(amount: float, _source: Node = null) -> void:
	if not _vulnerable or hp <= 0.0:
		return
	_last_damage_msec = Time.get_ticks_msec()
	var actual: float = min(amount, hp)
	hp = max(0.0, hp - amount)
	damaged.emit(self, amount)
	HitSparks.spawn_at(global_position + Vector3(0.0, 1.0, 0.0), self)
	# Yellow when a raider takes damage (player success), red when a
	# friendly orc/civilian/champion gets hit (player threat).
	var dmg_color: Color = Color(1, 0.9, 0.4) if faction == "raider" else Color(1, 0.4, 0.3)
	DamageNumber.spawn_at(global_position + Vector3(0.0, 1.7, 0.0), actual, dmg_color, self)
	_refresh_hp_label()
	if hp <= 0.0:
		_die()

func heal(amount: float) -> void:
	if hp <= 0.0 or amount <= 0.0:
		return
	hp = min(max_hp, hp + amount)
	_refresh_hp_label()

# Floating HP label — billboard, visible only when damaged. Created lazily
# on first take_damage so unscathed orcs stay visually clean. Skipped in
# headless via the existing DisplayServer guard pattern.
func _refresh_hp_label() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if hp >= max_hp - 0.01:
		if _hp_label != null:
			_hp_label.visible = false
		return
	if _hp_label == null:
		_hp_label = Label3D.new()
		_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_hp_label.no_depth_test = true
		_hp_label.fixed_size = true
		_hp_label.pixel_size = 0.004
		_hp_label.font_size = 32
		_hp_label.outline_size = 6
		_hp_label.outline_modulate = Color(0, 0, 0, 1)
		_hp_label.position = Vector3(0, 2.0, 0)
		add_child(_hp_label)
	_hp_label.visible = true
	# Color tint by faction — raiders (player wins) yellow, friendlies red.
	var col: Color = Color(1, 0.9, 0.4) if faction == "raider" else Color(0.6, 1, 0.6)
	if hp < max_hp * 0.3:
		col = Color(1, 0.3, 0.3)  # critical
	_hp_label.modulate = col
	_hp_label.text = "%d / %d" % [int(round(hp)), int(round(max_hp))]

# Out-of-combat regen pump. Subclasses keep their own _physics_process
# overrides; _process is unused there, so this base implementation runs
# unmodified for every Orc subclass with regen_rate > 0 set in its scene.
func _process(delta: float) -> void:
	if regen_rate <= 0.0 or hp <= 0.0 or hp >= max_hp:
		return
	var since_msec: int = Time.get_ticks_msec() - _last_damage_msec
	if since_msec < int(REGEN_OOC_DELAY * 1000.0):
		return
	heal(regen_rate * delta)

# Test/scenario helper: jump to a world position. Three floats so it can be
# called from probe_bot via JSON-encoded args (no Vector3 in JSON).
func teleport(x: float, y: float, z: float) -> void:
	global_position = Vector3(x, y, z)
	velocity = Vector3.ZERO

func _die() -> void:
	died.emit(self)
	set_physics_process(false)
	$CollisionShape3D.disabled = true
	# Prefer the Kenney 'die' animation when present; fall back to a tip-over
	# tween for headless and any model that lacks the animation.
	if _anim_player != null and _anim_player.has_animation("die"):
		_anim_player.play("die")
	else:
		var mesh: Node3D = get_node_or_null("Mesh")
		if mesh:
			var tween := create_tween()
			tween.tween_property(mesh, "rotation:x", deg_to_rad(-85.0), 0.3)
	await get_tree().create_timer(2.0).timeout
	queue_free()

# Play `name` if it exists and isn't already current. force=true restarts.
func play_anim(anim_name: String, force: bool = false) -> void:
	if _anim_player == null:
		return
	if not _anim_player.has_animation(anim_name):
		return
	if force or _anim_player.current_animation != anim_name:
		_anim_player.play(anim_name)

# Called from subclasses each physics tick after move_and_slide. Picks
# walk/idle by velocity unless an attack/sprint anim is already playing.
func update_locomotion_anim() -> void:
	if _anim_player == null:
		return
	var cur: String = _anim_player.current_animation
	# Don't interrupt one-shot anims (attack/death) — let them play out.
	if cur in ["attack-melee-left", "attack-melee-right", "die"]:
		return
	var horiz: float = Vector2(velocity.x, velocity.z).length()
	if horiz > 0.5:
		play_anim("walk")
	else:
		play_anim("idle")

func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

func set_vulnerable(v: bool) -> void:
	_vulnerable = v

func is_alive() -> bool:
	return hp > 0.0

# --- Visual model swap (runtime, interactive only) -----------------------------
#
# We can't reference GLB scenes from .tscn files because Godot --headless hangs
# at scene-load when GLB textures need GPU initialization. Workaround: load the
# GLB at runtime and replace the placeholder capsule "Mesh" child. Skipped only
# when there's no rendering context (--headless / "headless" DisplayServer) so
# CI stays deterministic AND interactive scenarios get the real models.

func _swap_in_visual_model(model_path: String, scale: float = 2.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not ResourceLoader.exists(model_path):
		return
	var scene: PackedScene = load(model_path)
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return
	var existing_mesh: Node = get_node_or_null("Mesh")
	var existing_dir: Node = get_node_or_null("DirIndicator")
	if existing_mesh:
		existing_mesh.queue_free()
	if existing_dir:
		existing_dir.queue_free()
	instance.name = "Mesh"
	add_child(instance)
	var node3d := instance as Node3D
	node3d.scale = Vector3(scale, scale, scale)
	# Kenney GLBs export with +Z as the model's visual forward, but Godot's
	# CharacterBody convention (and our hitbox at local -Z) treats -Z as
	# forward. Rotate the visual 180° so the character's face matches its
	# movement / hitbox direction.
	node3d.rotation.y = PI
	# Cache the imported AnimationPlayer (Kenney models put it under the GLB root).
	_anim_player = instance.get_node_or_null("AnimationPlayer")
	if _anim_player != null:
		_anim_player.play("idle")
