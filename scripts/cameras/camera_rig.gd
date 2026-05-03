extends Node3D

@export var third_person_distance: float = 4.5
@export var third_person_height: float = 2.2
@export var transition_time: float = 0.4

@onready var camera: Camera3D = $Camera3D

const LAIR_CAM_POS := Vector3(0.0, 18.0, 10.0)
const LAIR_CAM_ROT := Vector3(-1.30899, 0.0, 0.0) # deg_to_rad(-75)
# World-map view: high overhead between lair (z≈0) and city centre (z≈80),
# pitched ~−65° so both areas are framed.
const WORLD_CAM_POS := Vector3(0.0, 55.0, 80.0)
const WORLD_CAM_ROT := Vector3(-1.13446, 0.0, 0.0) # deg_to_rad(-65)

var _tween: Tween = null
var _follow_active: bool = false

func _ready() -> void:
	# Stays responsive during build-mode tree pause — otherwise the
	# camera tween into LAIR view would freeze mid-flight.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mode_changed.connect(_on_mode_changed)
	_apply_lair_view(true)

func _process(_delta: float) -> void:
	if _follow_active and Game.possessed != null and is_instance_valid(Game.possessed):
		_smooth_follow()

func _on_mode_changed(new_mode: int) -> void:
	if new_mode == Game.Mode.POSSESSING:
		_follow_active = true
	elif new_mode == Game.Mode.WORLD_MAP:
		_follow_active = false
		_move_camera(WORLD_CAM_POS, WORLD_CAM_ROT, false)
	else:
		_follow_active = false
		_apply_lair_view(false)

func _apply_lair_view(instant: bool) -> void:
	_move_camera(LAIR_CAM_POS, LAIR_CAM_ROT, instant)

func _smooth_follow() -> void:
	var target: Node3D = Game.possessed
	var back: Vector3 = -target.transform.basis.z
	var desired: Vector3 = target.global_position - back * third_person_distance + Vector3.UP * third_person_height
	var look_at_pt: Vector3 = target.global_position + Vector3.UP * 1.0
	# Slower follow → less feedback into camera-relative WASD input. Combined
	# with the slower body rotation in champion.gd, the character feels more
	# planted and predictable.
	camera.global_position = camera.global_position.lerp(desired, 0.08)
	camera.look_at(look_at_pt, Vector3.UP)

func _move_camera(pos: Vector3, rot: Vector3, instant: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if instant:
		camera.position = pos
		camera.rotation = rot
		return
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(camera, "position", pos, transition_time).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(camera, "rotation", rot, transition_time).set_trans(Tween.TRANS_SINE)
