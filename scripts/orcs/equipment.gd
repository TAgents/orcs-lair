extends Resource
class_name Equipment

# Champion gear. Three slots; +damage and/or +max_hp.
# Catalog is hard-coded for now — a JSON registry can replace it later
# without changing the equip/unequip API.

enum Slot { WEAPON, ARMOR, TRINKET }

@export var item_id: String = ""
@export var display_name: String = ""
@export var slot: int = Slot.WEAPON
@export var damage_bonus: float = 0.0
@export var max_hp_bonus: float = 0.0

static func from_id(id: String) -> Equipment:
	match id:
		"rusty_axe":
			return _make("rusty_axe", "Rusty Axe", Slot.WEAPON, 5.0, 0.0)
		"iron_axe":
			return _make("iron_axe", "Iron Axe", Slot.WEAPON, 12.0, 0.0)
		"leather_jerkin":
			return _make("leather_jerkin", "Leather Jerkin", Slot.ARMOR, 0.0, 15.0)
		"iron_plate":
			return _make("iron_plate", "Iron Plate", Slot.ARMOR, 0.0, 35.0)
		"warrior_charm":
			return _make("warrior_charm", "Warrior's Charm", Slot.TRINKET, 3.0, 5.0)
	return null

static func _make(id: String, n: String, s: int, dmg: float, hp: float) -> Equipment:
	var e := Equipment.new()
	e.item_id = id
	e.display_name = n
	e.slot = s
	e.damage_bonus = dmg
	e.max_hp_bonus = hp
	return e
