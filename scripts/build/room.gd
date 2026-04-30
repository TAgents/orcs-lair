extends Resource
class_name Room

# Pure data describing a room type. Visuals come from build_controller's palette.

enum Type { SLEEPING, TRAINING, TREASURY }

@export var type: Type = Type.SLEEPING
@export var footprint: Vector2i = Vector2i(2, 2)
@export var color: Color = Color.WHITE
@export var display_name: String = ""

static func make(t: Type) -> Room:
	var r := Room.new()
	r.type = t
	match t:
		Type.SLEEPING:
			r.display_name = "Sleeping"
			r.color = Color(0.35, 0.45, 0.85)
		Type.TRAINING:
			r.display_name = "Training"
			r.color = Color(0.85, 0.50, 0.20)
		Type.TREASURY:
			r.display_name = "Treasury"
			r.color = Color(0.85, 0.75, 0.25)
	return r
