extends Node

# Lair-wide economy. Gold accumulates from Treasury rooms with assigned
# workers, deducted by room placements. Future resources (food, recruits)
# live here too.

const STARTING_GOLD: int = 100
const STARTING_ORE: int = 0

signal gold_changed(new_amount: int)
signal ore_changed(new_amount: int)
signal spend_blocked(needed: int, have: int, reason: String)

var gold: int = STARTING_GOLD:
	set(value):
		if value == gold:
			return
		gold = value
		gold_changed.emit(gold)

var ore: int = STARTING_ORE:
	set(value):
		if value == ore:
			return
		ore = value
		ore_changed.emit(ore)

# Internal accumulators so fractional gold/ore per frame only emit the
# changed signal when the integer value rolls over.
var _gold_accum: float = 0.0
var _ore_accum: float = 0.0

func add_gold(amount: float) -> void:
	if amount == 0.0:
		return
	_gold_accum += amount
	if _gold_accum >= 1.0:
		var whole := int(_gold_accum)
		_gold_accum -= float(whole)
		gold = gold + whole
	elif _gold_accum <= -1.0:
		var whole := int(_gold_accum)
		_gold_accum -= float(whole)
		gold = gold + whole

func add_ore(amount: float) -> void:
	if amount == 0.0:
		return
	_ore_accum += amount
	if _ore_accum >= 1.0:
		var whole := int(_ore_accum)
		_ore_accum -= float(whole)
		ore = ore + whole
	elif _ore_accum <= -1.0:
		var whole := int(_ore_accum)
		_ore_accum -= float(whole)
		ore = ore + whole

func reset() -> void:
	gold = STARTING_GOLD
	_gold_accum = 0.0
	ore = STARTING_ORE
	_ore_accum = 0.0

func can_afford(amount: int) -> bool:
	return gold >= amount

func spend(amount: int, reason: String = "") -> bool:
	if amount < 0:
		return false
	if amount > gold:
		spend_blocked.emit(amount, gold, reason)
		return false
	gold = gold - amount
	return true
