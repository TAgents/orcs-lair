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
	# No .wav file — synthesize a placeholder tone so the game ships
	# with audible feedback. Drop a .wav into assets/audio/ to override.
	var synth: AudioStream = _synth(stream_name)
	if synth != null:
		_streams[stream_name] = synth
		return synth
	if not _missing_warned.has(stream_name):
		_missing_warned[stream_name] = true
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

# --- Procedural synth fallback ----------------------------------------------
#
# Generates a short AudioStreamWAV when no .wav file exists for the given
# name. Each known event gets a distinctive tone shape: melee swing is a
# downward sine sweep, hit is a noise burst, loot is a rising chirp, etc.
# These are deliberately rough — drop CC0 .wav files into assets/audio/
# to override.

const _SYNTH_RATE: int = 22050

func _synth(stream_name: String) -> AudioStream:
	var seconds: float = 0.0
	match stream_name:
		"swing":      seconds = 0.18
		"hit":        seconds = 0.12
		"loot":       seconds = 0.20
		"level_up":   seconds = 0.45
		"day_chime":  seconds = 0.55
		"raid_alarm": seconds = 0.40
		"treasure":   seconds = 0.30
		_:
			return null
	var n: int = int(seconds * float(_SYNTH_RATE))
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		var t: float = float(i) / float(_SYNTH_RATE)
		var sample: float = _synth_sample(stream_name, t, seconds)
		var s16: int = clampi(int(clampf(sample, -1.0, 1.0) * 32767.0), -32768, 32767)
		pcm.encode_s16(i * 2, s16)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = _SYNTH_RATE
	stream.stereo = false
	stream.data = pcm
	return stream

func _synth_sample(stream_name: String, t: float, dur: float) -> float:
	var u: float = clampf(t / max(dur, 0.0001), 0.0, 1.0)
	var env_out: float = clampf(1.0 - u, 0.0, 1.0)         # linear release
	var env_attack: float = clampf(t / 0.01, 0.0, 1.0)      # 10 ms attack
	match stream_name:
		"swing":
			# Downward sine sweep — 800 → 200 Hz, fast release.
			var freq: float = lerpf(800.0, 200.0, u)
			return sin(t * TAU * freq) * env_out * 0.45 * env_attack
		"hit":
			# Noise burst with sharp release.
			return (randf() * 2.0 - 1.0) * pow(env_out, 2.5) * 0.55
		"loot":
			# Up-chirp 600 → 1100 Hz.
			var freq2: float = lerpf(600.0, 1100.0, u)
			return sin(t * TAU * freq2) * env_out * 0.40 * env_attack
		"level_up":
			# Three-tone arpeggio C5 / E5 / G5 (~523 / 659 / 784 Hz).
			var step_dur: float = dur / 3.0
			var idx: int = clampi(int(t / step_dur), 0, 2)
			var freqs: Array[float] = [523.0, 659.0, 784.0]
			var local_t: float = fmod(t, step_dur)
			var local_env: float = clampf(1.0 - (local_t / step_dur), 0.0, 1.0)
			return sin(local_t * TAU * freqs[idx]) * local_env * 0.40
		"day_chime":
			# Soft 440 Hz with slow bell envelope.
			var bell: float = pow(env_out, 1.6)
			return sin(t * TAU * 440.0) * bell * 0.35
		"raid_alarm":
			# Sawtooth 220 Hz with 8 Hz tremolo.
			var saw: float = fmod(t * 220.0, 1.0) * 2.0 - 1.0
			var trem: float = 0.5 + 0.5 * sin(t * TAU * 8.0)
			return saw * trem * 0.5 * env_out
		"treasure":
			# Two-octave rising chord — pleasant pickup.
			var f1: float = lerpf(440.0, 880.0, u)
			var f2: float = lerpf(660.0, 1320.0, u)
			return (sin(t * TAU * f1) + sin(t * TAU * f2)) * 0.20 * env_out
	return 0.0
