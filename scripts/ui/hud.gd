extends CanvasLayer

@onready var mode_label: Label = $Root/ModeLabel
@onready var hp_bar: ProgressBar = $Root/HPBar
@onready var hp_label: Label = $Root/HPBar/HPLabel
@onready var banner: Label = $Root/Banner
@onready var build_label: Label = $Root/BuildLabel
@onready var gold_label: Label = $Root/GoldLabel
@onready var level_label: Label = $Root/LevelLabel
@onready var skills_label: Label = $Root/SkillsLabel
@onready var wave_label: Label = $Root/WaveLabel
@onready var attr_label: Label = $Root/AttrLabel
@onready var raid_label: Label = $Root/RaidLabel
@onready var day_label: Label = $Root/DayLabel

var _champion: Champion = null
var _build_controller: BuildController = null
var _raid_complete: bool = false
var _lair: Node = null

func _ready() -> void:
	Game.mode_changed.connect(_on_mode_changed)
	Game.game_over.connect(_on_game_over)
	Economy.gold_changed.connect(_on_gold_changed)
	Economy.ore_changed.connect(_on_ore_changed)
	banner.visible = false
	build_label.visible = false
	_refresh_mode()
	_refresh_gold()
	_find_champion()
	_find_build_controller()
	_find_wave_director()
	_find_lair_raid_signals()
	Clock.day_changed.connect(_on_day_changed)
	Clock.time_changed.connect(_on_time_changed)
	_refresh_day()

func _process(_delta: float) -> void:
	# HP / level / XP always reflect the *named* champion (first one — Champion2
	# stays anonymous to the HUD until per-champion portraits land).
	if _champion != null and is_instance_valid(_champion):
		hp_bar.max_value = _champion.max_hp
		hp_bar.value = _champion.hp
		hp_label.text = "%d / %d" % [int(_champion.hp), int(_champion.max_hp)]
		level_label.text = "Lv %d   XP %d/%d" % [_champion.level, _champion.xp, _champion.xp_threshold()]
		# Attribute badge: only visible when there are unspent points to spend.
		var pts: int = int(_champion.attribute_points) if "attribute_points" in _champion else 0
		if pts > 0:
			attr_label.visible = true
			attr_label.text = "ATTR +%d — [U]Str [I]Vit [O]Agi" % pts
		else:
			attr_label.visible = false

	# Skill bar: visible only while possessing, sourced from whichever
	# champion is currently being controlled (so cooldowns reflect what
	# the player just pressed).
	if Game.mode == Game.Mode.POSSESSING and Game.possessed != null and is_instance_valid(Game.possessed) and Game.possessed is Champion:
		skills_label.visible = true
		skills_label.text = _format_skills(Game.possessed)
	else:
		skills_label.visible = false

	# Raid progress badge: visible while a raid is active OR pending return.
	if _lair != null and _lair.has_method("raid_progress"):
		var rp: Dictionary = _lair.raid_progress()
		var active: bool = bool(rp.get("active", false)) or bool(rp.get("pending_return", false))
		if active:
			raid_label.visible = true
			raid_label.text = "RAID — Chests %d/%d · Guards %d/%d" % [
				int(rp.get("chests_looted", 0)),
				int(rp.get("chests_total", 0)),
				int(rp.get("guards_dead", 0)),
				int(rp.get("guards_total", 0)),
			]
		else:
			raid_label.visible = false

func _format_skills(c: Champion) -> String:
	return "%s  %s  %s  %s" % [
		_skill_cell("J Attack", c.attack_cooldown_remaining()),
		_skill_cell("K Cleave", c.cleave_cooldown_remaining()),
		_skill_cell("L Charge", c.charge_cooldown_remaining()),
		_skill_cell("N Roar",   c.roar_cooldown_remaining()),
	]

func _skill_cell(label: String, cd: float) -> String:
	if cd <= 0.001:
		return "[%s ✓]" % label
	return "[%s %.1fs]" % [label, cd]

func _find_champion() -> void:
	var champs := get_tree().get_nodes_in_group("champions")
	if champs.size() > 0 and champs[0] is Champion:
		_champion = champs[0]

func _find_wave_director() -> void:
	var lair: Node = get_parent()
	if lair == null:
		return
	var wd: Node = lair.get_node_or_null("WaveDirector")
	if wd == null:
		return
	wd.wave_started.connect(_on_wave_started)

func _find_lair_raid_signals() -> void:
	_lair = get_parent()
	if _lair == null:
		return
	if _lair.has_signal("raid_started"):
		_lair.raid_started.connect(_on_raid_started)
	if _lair.has_signal("raid_completed"):
		_lair.raid_completed.connect(_on_raid_completed)

func _on_raid_started() -> void:
	_raid_complete = false
	_refresh_mode()

func _on_day_changed(_d: int) -> void:
	_refresh_day()

func _on_time_changed(_t: float) -> void:
	_refresh_day()

func _refresh_day() -> void:
	var t: float = Clock.time_of_day
	var phase: String
	if t < 0.20:
		phase = "🌙 Night"
	elif t < 0.30:
		phase = "☀ Dawn"
	elif t < 0.70:
		phase = "☀ Day"
	elif t < 0.80:
		phase = "☀ Dusk"
	else:
		phase = "🌙 Night"
	day_label.text = "Day %d   %s" % [Clock.day_index, phase]

func _on_raid_completed() -> void:
	_raid_complete = true
	_refresh_mode()

func _on_wave_started(wave_idx: int, total: int) -> void:
	wave_label.visible = true
	wave_label.text = "Wave %d/%d" % [wave_idx + 1, total]

func _find_build_controller() -> void:
	var bc: Node = get_tree().get_first_node_in_group("build_controllers")
	if bc == null:
		# Fallback: walk siblings — BuildController is a sibling of HUD inside Lair.
		var lair: Node = get_parent()
		if lair != null:
			bc = lair.get_node_or_null("BuildController")
	if bc is BuildController:
		_build_controller = bc
		_build_controller.type_changed.connect(_on_build_type_changed)

func _on_mode_changed(_m: int) -> void:
	# Returning to LAIR after a completed raid clears the prompt.
	if Game.mode == Game.Mode.LAIR:
		_raid_complete = false
	_refresh_mode()

func _refresh_mode() -> void:
	match Game.mode:
		Game.Mode.POSSESSING:
			if _raid_complete:
				mode_label.text = "RAID COMPLETE — M to return"
			else:
				mode_label.text = "POSSESSING — Tab to release"
			build_label.visible = false
		Game.Mode.BUILDING:
			mode_label.text = "BUILDING — B/Esc to exit"
			build_label.visible = true
			_refresh_build_label()
		Game.Mode.WORLD_MAP:
			mode_label.text = "WORLD MAP — [1] Defend Lair · [2] Raid City · M to exit"
			build_label.visible = false
		_:
			mode_label.text = "LAIR — Tab to possess · B to build · M for world map"
			build_label.visible = false

func _on_build_type_changed(_t: int) -> void:
	_refresh_build_label()

func _refresh_build_label() -> void:
	if _build_controller == null:
		return
	var room := Room.make(_build_controller.current_type)
	build_label.text = "Selected: %s (%dg)   [1 Sleeping (%dg) · 2 Training (%dg) · 3 Treasury (%dg) · LMB place · RMB demolish (50%% refund)]" % [
		room.display_name, room.cost,
		Room.make(Room.Type.SLEEPING).cost,
		Room.make(Room.Type.TRAINING).cost,
		Room.make(Room.Type.TREASURY).cost,
	]

func _on_game_over(victory: bool) -> void:
	banner.visible = true
	var head: String = "LAIR DEFENDED" if victory else "LAIR FALLEN"
	banner.text = "%s\nR to restart" % head

func _on_gold_changed(_amount: int) -> void:
	_refresh_gold()

func _on_ore_changed(_amount: int) -> void:
	_refresh_gold()

func _refresh_gold() -> void:
	gold_label.text = "Gold: %d   Ore: %d" % [Economy.gold, Economy.ore]
