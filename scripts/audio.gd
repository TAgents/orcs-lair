extends Node

# Audio autoload — Phase 6 polish scaffolding.
#
# play(name) loads res://assets/audio/{name}.wav (or .ogg) the first time
# and plays via a small AudioStreamPlayer pool. Missing files are a no-op
# and only warn once per name (so the game runs silently until CC0 SFX
# files are dropped into the assets dir).
#
# Hooks live in `_ready` — anyone emitting a known signal triggers the
# matching sound name without explicit play() calls.

const POOL_SIZE: int = 8
const AUDIO_DIRS: Array[String] = ["res://assets/audio/"]
const EXTS: Array[String] = [".wav", ".ogg"]

var _streams: Dictionary = {}
var _missing_warned: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_wire_signals()

func play(stream_name: String, volume_db: float = 0.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var stream: AudioStream = _resolve(stream_name)
	if stream == null:
		return
	var p: AudioStreamPlayer = _free_player()
	if p == null:
		return
	p.stream = stream
	p.volume_db = volume_db
	p.play()

func _resolve(stream_name: String) -> AudioStream:
	if _streams.has(stream_name):
		return _streams[stream_name]
	for dir in AUDIO_DIRS:
		for ext in EXTS:
			var path: String = dir + stream_name + ext
			if ResourceLoader.exists(path):
				var s: AudioStream = load(path)
				_streams[stream_name] = s
				return s
	if not _missing_warned.has(stream_name):
		_missing_warned[stream_name] = true
		# print so it surfaces in stdout but doesn't spam.
		print("[audio] missing stream: %s (drop a .wav into assets/audio/)" % stream_name)
	_streams[stream_name] = null
	return null

func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	# All busy — steal the oldest (front of pool).
	return _players[0]

# --- Signal wiring -----------------------------------------------------------

func _wire_signals() -> void:
	if Inventory != null:
		Inventory.item_added.connect(_on_item_added)
	if Research != null:
		Research.branch_unlocked.connect(_on_research_unlocked)
	if Clock != null:
		Clock.day_changed.connect(_on_day_changed)
	# Per-actor hooks (Orc.damaged, Champion swings, etc.) need a node
	# tree to walk; do that on the next idle frame so autoloads above us
	# in the order are settled.
	call_deferred("_wire_actor_signals")

func _wire_actor_signals() -> void:
	# Orc.damaged → "hit"; champion swing keys → "swing".
	var tree := get_tree()
	if tree == null:
		return
	for o in tree.get_nodes_in_group("orcs"):
		if o is Orc and not o.damaged.is_connected(_on_orc_damaged):
			o.damaged.connect(_on_orc_damaged)
	for r in tree.get_nodes_in_group("raiders"):
		if r is Raider and not r.damaged.is_connected(_on_orc_damaged):
			r.damaged.connect(_on_orc_damaged)
	for ch in tree.get_nodes_in_group("treasure_chests"):
		if ch.has_signal("looted") and not ch.looted.is_connected(_on_chest_looted):
			ch.looted.connect(_on_chest_looted)
	var lair: Node = tree.root.get_node_or_null("Lair")
	if lair != null and lair.has_signal("raid_started") and not lair.raid_started.is_connected(_on_raid_started):
		lair.raid_started.connect(_on_raid_started)

func _on_orc_damaged(_o: Orc, _amount: float) -> void:
	play("hit")

func _on_item_added(_item_id: String) -> void:
	play("loot")

func _on_research_unlocked(_branch: String) -> void:
	play("level_up")

func _on_day_changed(_d: int) -> void:
	play("day_chime", -6.0)

func _on_chest_looted(_chest: Node, _gold: int, _items: Array) -> void:
	play("treasure")

func _on_raid_started() -> void:
	play("raid_alarm")
