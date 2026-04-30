extends Node
class_name ProbeBot

# Drives input actions on a scripted timeline.
# Sequence entries: { "t": float, "press"|"release": String_action_name }
# Actions are toggled via Input.action_press/release; physics-stepped, frame-accurate.

var sequence: Array = []
var t: float = 0.0
var idx: int = 0
var _held: Dictionary = {}

signal finished

func load_sequence(seq: Array) -> void:
	# Sort by t to allow scenarios to be authored unordered.
	var copy := seq.duplicate(true)
	copy.sort_custom(func(a, b): return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	sequence = copy
	idx = 0
	t = 0.0

func _physics_process(delta: float) -> void:
	t += delta
	while idx < sequence.size():
		var entry: Dictionary = sequence[idx]
		var when: float = float(entry.get("t", 0.0))
		if when > t:
			break
		_apply(entry)
		idx += 1
	if idx >= sequence.size() and not _held.is_empty():
		# Release anything still held when the script ends.
		for action in _held.keys():
			Input.action_release(action)
		_held.clear()
		finished.emit()

func _apply(entry: Dictionary) -> void:
	if entry.has("press"):
		var a: String = entry["press"]
		if InputMap.has_action(a):
			Input.action_press(a)
			_held[a] = true
	if entry.has("release"):
		var a: String = entry["release"]
		if InputMap.has_action(a):
			Input.action_release(a)
			_held.erase(a)
	if entry.has("call"):
		# Format: "NodePath.method_name" — node path is relative to ProbeBot's parent.
		var spec: String = entry["call"]
		var dot: int = spec.rfind(".")
		if dot > 0:
			var node_path: String = spec.substr(0, dot)
			var method: String = spec.substr(dot + 1)
			var host: Node = get_parent()
			var target: Node = host.get_node_or_null(node_path) if host else null
			if target != null and target.has_method(method):
				var args: Array = entry.get("args", [])
				target.callv(method, args)
			else:
				push_warning("[probe] call missed: %s (target=%s method_ok=%s)" % [spec, target, target != null and target.has_method(method)])
	if entry.has("note"):
		print("[probe] ", entry["note"])

func release_all() -> void:
	for action in _held.keys():
		Input.action_release(action)
	_held.clear()
