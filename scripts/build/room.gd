extends Resource
class_name Room

# Pure data describing a room type. Visuals come from build_controller's palette.

enum Type { SLEEPING, TRAINING, TREASURY, MINE, FORGE, KITCHEN, LIBRARY }

@export var type: Type = Type.SLEEPING
@export var footprint: Vector2i = Vector2i(2, 2)
@export var color: Color = Color.WHITE
@export var display_name: String = ""
@export var cost: int = 0

static func make(t: Type) -> Room:
	var r := Room.new()
	r.type = t
	match t:
		Type.SLEEPING:
			r.display_name = "Sleeping"
			r.color = Color(0.35, 0.45, 0.85)
			r.cost = 25
		Type.TRAINING:
			r.display_name = "Training"
			r.color = Color(0.85, 0.50, 0.20)
			r.cost = 35
		Type.TREASURY:
			r.display_name = "Treasury"
			r.color = Color(0.85, 0.75, 0.25)
			r.cost = 40
		Type.MINE:
			r.display_name = "Mine"
			r.color = Color(0.35, 0.30, 0.40)
			r.cost = 30
		Type.FORGE:
			r.display_name = "Forge"
			r.color = Color(0.75, 0.30, 0.10)
			r.cost = 50
		Type.KITCHEN:
			r.display_name = "Kitchen"
			r.color = Color(0.95, 0.80, 0.40)
			r.cost = 30
		Type.LIBRARY:
			r.display_name = "Library"
			r.color = Color(0.55, 0.30, 0.85)
			r.cost = 45
	return r
