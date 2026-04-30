extends Node

# Lair-wide economy. Gold accumulates from Treasury rooms with assigned
# workers. Future resources (food, recruits) live here too.

signal gold_changed(new_amount: int)

var gold: int = 0:
	set(value):
		if value == gold:
			return
		gold = value
		gold_changed.emit(gold)

# Internal accumulator so we can add fractional gold per frame and only
# emit the changed signal when the integer value rolls over.
var _gold_accum: float = 0.0

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

func reset() -> void:
	gold = 0
	_gold_accum = 0.0
