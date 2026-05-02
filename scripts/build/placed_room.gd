extends Node3D
class_name PlacedRoom

# A placed room in the world. Tracks the room type, footprint, and a single
# assigned worker (capacity 1 for now). Workers self-assign on placement;
# UI-driven reassignment is a future PR.
#
# Per-tick effects (Phase 2 economy slice):
#   TREASURY  : +TREASURY_GOLD_PER_SEC per assigned worker, accumulated to
#               Economy.gold via fractional add (so 1g/s shows up cleanly
#               even at 60Hz physics ticks).
# Other room types are placeholders until Phase 4 progression lands.

const TREASURY_GOLD_PER_SEC: float = 1.0
const TRAINING_DAMAGE_BONUS: float = 10.0
const SLEEPING_HP_PER_SEC: float = 4.0
const SLEEPING_HEAL_RADIUS: float = 4.5
const MINE_ORE_PER_SEC: float = 0.5
const KITCHEN_FOOD_PER_SEC: float = 0.5
const LIBRARY_RESEARCH_PER_SEC: float = 0.3
# Per-room class match: when the assigned worker has the matching class,
# room output / craft speed is multiplied by this. Trainer/Banker/Miner/
# Smith/Cook are awarded by Worker._advance_class_progress.
const CLASS_BONUS_MULT: float = 1.5
const CLASS_FOR_ROOM_TYPE: Dictionary = {
	Room.Type.TRAINING: "Trainer",
	Room.Type.TREASURY: "Banker",
	Room.Type.MINE: "Miner",
	Room.Type.FORGE: "Smith",
	Room.Type.KITCHEN: "Cook",
	Room.Type.LIBRARY: "Scholar",
}
const FORGE_CRAFT_TIME: float = 6.0
const FORGE_ORE_COST: int = 1
# Round-robin output. Forge alternates rusty_axe / leather_jerkin so a
# single Forge stocks Inventory with both tier-0 weapon and armor over
# time without needing extra config.
const FORGE_OUTPUTS: Array[String] = ["rusty_axe", "leather_jerkin"]

@export var room_type: int = 0
@export var footprint: Vector2i = Vector2i(2, 2)
@export var grid_origin: Vector2i = Vector2i.ZERO

var _assigned_worker: Node = null
var _placed_at_msec: int = 0
var _forge_progress: float = 0.0
var _forge_outputs_made: int = 0
var _status_label: Label3D = null

signal worker_assigned(worker: Node)
signal worker_unassigned(worker: Node)

func _ready() -> void:
	add_to_group("placed_rooms")
	_placed_at_msec = Time.get_ticks_msec()
	_setup_status_label()

# Status billboard floats above the room and updates each frame to show
# what's running, who's working it, and how full the bar is. Skipped in
# headless (no rendering, no need).
func _setup_status_label() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_status_label = Label3D.new()
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.no_depth_test = true
	_status_label.fixed_size = true
	_status_label.pixel_size = 0.005
	_status_label.font_size = 32
	_status_label.outline_size = 6
	_status_label.outline_modulate = Color(0, 0, 0, 1)
	_status_label.modulate = Color(1, 0.95, 0.7, 1)
	_status_label.position = Vector3(0, 1.6, 0)
	add_child(_status_label)
	_refresh_status_label()

func _refresh_status_label() -> void:
	if _status_label == null:
		return
	var head: String = Room.make(room_type).display_name
	var w: Node = get_assigned_worker()
	if w == null:
		_status_label.text = head + "\n(unassigned)"
		return
	var wname: String = String(w.name)
	var wclass: String = String(w.worker_class) if "worker_class" in w else ""
	var class_marker: String = ""
	var expected: String = String(CLASS_FOR_ROOM_TYPE.get(room_type, ""))
	if wclass != "":
		class_marker = " ★" if wclass == expected else ""
		wname = "%s (%s%s)" % [wname, wclass, class_marker]
	# State: WORKING shows production rate or progress bar; otherwise "incoming".
	if not (w is Worker and w.is_working()):
		_status_label.text = "%s\n%s · incoming" % [head, wname]
		return
	var rate_line: String = ""
	var mult: float = _class_multiplier()
	match room_type:
		Room.Type.TREASURY:
			rate_line = "%.2f g/s" % (TREASURY_GOLD_PER_SEC * mult)
		Room.Type.MINE:
			rate_line = "%.2f ore/s" % (MINE_ORE_PER_SEC * mult)
		Room.Type.KITCHEN:
			rate_line = "%.2f food/s" % (KITCHEN_FOOD_PER_SEC * mult)
		Room.Type.LIBRARY:
			rate_line = "%.2f res/s" % (LIBRARY_RESEARCH_PER_SEC * mult)
		Room.Type.FORGE:
			var pct: int = int(round((_forge_progress / FORGE_CRAFT_TIME) * 100.0))
			var bar_len: int = 8
			var filled: int = clamp(int(round(float(pct) * 0.01 * float(bar_len))), 0, bar_len)
			var bar: String = "▮".repeat(filled) + "▯".repeat(bar_len - filled)
			rate_line = "%s %d%%" % [bar, pct]
		Room.Type.TRAINING:
			rate_line = "+%.0f dmg" % TRAINING_DAMAGE_BONUS
		Room.Type.SLEEPING:
			rate_line = "%.0f hp/s" % SLEEPING_HP_PER_SEC
	_status_label.text = "%s\n%s · %s" % [head, wname, rate_line]

func age_seconds() -> float:
	return float(Time.get_ticks_msec() - _placed_at_msec) / 1000.0

func is_active() -> bool:
	# Active = has an assigned worker who's actually at the room (WORKING).
	if not has_assigned_worker():
		return false
	var w: Node = get_assigned_worker()
	return w is Worker and w.is_working()

func set_assigned_worker(w: Node) -> void:
	if _assigned_worker == w:
		return
	if _assigned_worker != null:
		worker_unassigned.emit(_assigned_worker)
	_assigned_worker = w
	if w != null:
		worker_assigned.emit(w)

func get_assigned_worker() -> Node:
	if _assigned_worker != null and not is_instance_valid(_assigned_worker):
		_assigned_worker = null
	return _assigned_worker

func has_assigned_worker() -> bool:
	return get_assigned_worker() != null

# --- Per-frame effects -------------------------------------------------------

func _process(delta: float) -> void:
	# Status label refreshes every frame so production rate / forge bar /
	# class star track changes live. Cheap — single Label3D per room.
	_refresh_status_label()
	if not is_active():
		return
	var mult: float = _class_multiplier()
	if room_type == Room.Type.TREASURY:
		Economy.add_gold(TREASURY_GOLD_PER_SEC * delta * mult)
	elif room_type == Room.Type.SLEEPING:
		_regen_nearby(delta)
	elif room_type == Room.Type.MINE:
		Economy.add_ore(MINE_ORE_PER_SEC * delta * mult)
	elif room_type == Room.Type.FORGE:
		_step_forge(delta * mult)
	elif room_type == Room.Type.KITCHEN:
		Economy.add_food(KITCHEN_FOOD_PER_SEC * delta * mult)
	elif room_type == Room.Type.LIBRARY:
		Research.add_points(LIBRARY_RESEARCH_PER_SEC * delta * mult)

# 1.5× when the assigned worker's class matches this room's type, 1.0
# otherwise. Sleeping rooms have no class bonus (no class is awarded for
# resting), so they always return 1.0. Training's bonus applies via
# Champion.effective_damage as a flat add — that path is unaffected.
func _class_multiplier() -> float:
	if not CLASS_FOR_ROOM_TYPE.has(room_type):
		return 1.0
	var w: Node = get_assigned_worker()
	if w == null or not "worker_class" in w:
		return 1.0
	if w.worker_class != CLASS_FOR_ROOM_TYPE[room_type]:
		return 1.0
	return CLASS_BONUS_MULT

func _step_forge(delta: float) -> void:
	# Smith only progresses when the lair has ore to feed in. When progress
	# fills the bar, consume one ore unit and push an item into Inventory,
	# alternating weapon/armor so a solo Forge eventually produces both.
	if Economy.ore < FORGE_ORE_COST:
		_forge_progress = 0.0
		return
	_forge_progress += delta
	if _forge_progress < FORGE_CRAFT_TIME:
		return
	_forge_progress -= FORGE_CRAFT_TIME
	Economy.ore = Economy.ore - FORGE_ORE_COST
	var idx: int = _forge_outputs_made % FORGE_OUTPUTS.size()
	Inventory.add(FORGE_OUTPUTS[idx])
	_forge_outputs_made += 1

func _regen_nearby(delta: float) -> void:
	var amount: float = SLEEPING_HP_PER_SEC * delta
	var center: Vector3 = global_position
	for o in get_tree().get_nodes_in_group("orcs"):
		if o is Orc and o.is_alive():
			var dx: float = o.global_position.x - center.x
			var dz: float = o.global_position.z - center.z
			if dx * dx + dz * dz <= SLEEPING_HEAL_RADIUS * SLEEPING_HEAL_RADIUS:
				o.heal(amount)
