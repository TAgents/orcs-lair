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

# Per-item upgrade ladder. Lookup by item_id → array of tier ids.
# Index with min(raid_count, ladder.size() - 1). Unknown ids pass through.
# Tuned so an early-game rusty_axe / leather_jerkin gets replaced by
# iron-tier gear by the third raid; iron-tier and trinkets don't upgrade.
const _UPGRADE_LADDER: Dictionary = {
	"rusty_axe":      ["rusty_axe", "iron_axe", "iron_axe"],
	"leather_jerkin": ["leather_jerkin", "leather_jerkin", "iron_plate"],
	"iron_axe":       ["iron_axe"],
	"iron_plate":     ["iron_plate"],
	"warrior_charm":  ["warrior_charm"],
}

static func upgrade(item_id: String, raid_count: int) -> String:
	if not _UPGRADE_LADDER.has(item_id):
		return item_id
	var ladder: Array = _UPGRADE_LADDER[item_id]
	if ladder.is_empty():
		return item_id
	var idx: int = clamp(raid_count, 0, ladder.size() - 1)
	return String(ladder[idx])

static func _make(id: String, n: String, s: int, dmg: float, hp: float) -> Equipment:
	var e := Equipment.new()
	e.item_id = id
	e.display_name = n
	e.slot = s
	e.damage_bonus = dmg
	e.max_hp_bonus = hp
	return e
