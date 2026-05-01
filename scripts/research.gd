extends Node

# Research autoload — Direction A skill-tree gate. Library workers feed
# `points` at PER_SEC; spending UNLOCK_COST points on a branch applies a
# permanent buff to all current Champions and locks the branch in.
#
# The three branches are mutually independent (you can unlock all three
# given enough points). On save, we persist the unlocked list and the
# raw points; champion stats are saved with the branch effects already
# baked in, so load doesn't re-apply (matches the attribute-point
# pattern from PR #40).

const UNLOCK_COST: int = 50
const BRANCHES: Array[String] = ["berserker", "tactician", "survivor"]

signal points_changed(new_amount: int)
signal branch_unlocked(branch: String)

var points: int = 0:
	set(value):
		if value == points:
			return
		points = value
		points_changed.emit(points)

var unlocked: Array[String] = []
var _accum: float = 0.0

func add_points(amount: float) -> void:
	if amount == 0.0:
		return
	_accum += amount
	if _accum >= 1.0:
		var whole := int(_accum)
		_accum -= float(whole)
		points = points + whole

func can_unlock(branch: String) -> bool:
	return points >= UNLOCK_COST and not unlocked.has(branch) and BRANCHES.has(branch)

func unlock(branch: String) -> bool:
	if not can_unlock(branch):
		return false
	points -= UNLOCK_COST
	unlocked.append(branch)
	branch_unlocked.emit(branch)
	_apply_branch(branch)
	return true

# Save/load helper: restore state without firing _apply_branch (saved
# Champion stats already include the buffs).
func restore(saved_points: int, saved_unlocked: Array) -> void:
	points = saved_points
	unlocked.clear()
	for b in saved_unlocked:
		unlocked.append(String(b))
	_accum = 0.0

func reset() -> void:
	points = 0
	unlocked.clear()
	_accum = 0.0

func _apply_branch(branch: String) -> void:
	var lair: Node = get_tree().root.get_node_or_null("Lair") if get_tree() != null else null
	if lair == null:
		return
	for c in lair.get_tree().get_nodes_in_group("champions"):
		if not (c is Champion):
			continue
		match branch:
			"berserker":
				c.damage *= 1.2
			"tactician":
				c.attack_cooldown *= 0.8
				c.cleave_cooldown *= 0.8
				c.charge_cooldown *= 0.8
				c.roar_cooldown *= 0.8
			"survivor":
				var bonus: float = c.max_hp * 0.3
				c.max_hp += bonus
				c.hp += bonus
