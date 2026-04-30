extends Node

# Lair-wide inventory of un-equipped gear. Items are stored as item_ids
# (strings matching Equipment.from_id keys); duplicates are kept so the
# player can hold multiple of the same drop.
#
# UI for browsing/equipping is a future PR — for now drops just pile up
# here and Champion.equip_from_inventory pulls one out by id.

signal item_added(item_id: String)
signal item_removed(item_id: String)

var _items: Array = []

func add(item_id: String) -> void:
	if item_id == "":
		return
	_items.append(item_id)
	item_added.emit(item_id)

func remove(item_id: String) -> bool:
	var idx: int = _items.find(item_id)
	if idx < 0:
		return false
	_items.remove_at(idx)
	item_removed.emit(item_id)
	return true

func has_item(item_id: String) -> bool:
	return _items.has(item_id)

func count() -> int:
	return _items.size()

func count_of(item_id: String) -> int:
	var n: int = 0
	for it in _items:
		if it == item_id:
			n += 1
	return n

func items() -> Array:
	return _items.duplicate()

func clear() -> void:
	_items.clear()
