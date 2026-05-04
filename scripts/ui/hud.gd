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
@onready var toast_root: VBoxContainer = $Root/ToastRoot
@onready var help_overlay: ColorRect = $Root/HelpOverlay
@onready var help_label: Label = $Root/HelpOverlay/HelpLabel
@onready var research_label: Label = $Root/ResearchLabel
@onready var pause_menu: ColorRect = $Root/PauseMenu
@onready var btn_resume: Button = $Root/PauseMenu/ResumeBtn
@onready var btn_restart: Button = $Root/PauseMenu/RestartBtn
@onready var btn_quit: Button = $Root/PauseMenu/QuitBtn
@onready var btn_settings: Button = $Root/PauseMenu/SettingsBtn
@onready var settings_panel: ColorRect = $Root/SettingsPanel
@onready var vol_slider: HSlider = $Root/SettingsPanel/VolSlider
@onready var fullscreen_check: CheckBox = $Root/SettingsPanel/FullscreenCheck
@onready var btn_settings_back: Button = $Root/SettingsPanel/BackBtn

var _champion: Champion = null
var _build_controller: BuildController = null
var _raid_complete: bool = false
var _lair: Node = null
var _wave_director: Node = null
var _wave_idx: int = 0
var _wave_total: int = 0

func _ready() -> void:
	# HUD must keep updating during the build-mode tree pause so the
	# resource bar / build legend / toasts / day label stay live.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mode_changed.connect(_on_mode_changed)
	Game.game_over.connect(_on_game_over)
	Economy.gold_changed.connect(_on_gold_changed)
	Economy.ore_changed.connect(_on_ore_changed)
	Economy.food_changed.connect(_on_food_changed)
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
	# Toast pipeline.
	Toasts.toast_requested.connect(_on_toast_requested)
	# Help overlay (F1). Auto-shows on first launch via user:// flag,
	# then hides until the player presses F1 again.
	help_label.text = _build_help_text()
	if not _help_seen():
		help_overlay.visible = true
		_mark_help_seen()
	# Pause menu wiring.
	btn_resume.pressed.connect(_pause_resume)
	btn_restart.pressed.connect(_pause_restart)
	btn_quit.pressed.connect(_pause_quit)
	btn_settings.pressed.connect(_open_settings)
	btn_settings_back.pressed.connect(_close_settings)
	vol_slider.value_changed.connect(_on_volume_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_load_settings()
	# Hooks that fire the most useful toasts. Keep this set tight — too
	# many is noise. Worker class_earned is wired per-worker on _ready
	# below; new workers spawned later (none today, but future) won't
	# auto-fire toasts unless someone calls Toasts.show.
	if Research != null:
		Research.branch_unlocked.connect(_on_research_branch_unlocked)
		Research.points_changed.connect(_on_research_points_changed)
	_refresh_research_label()
	if Economy != null:
		Economy.food_changed.connect(_on_food_changed_for_toast)
	for w in get_tree().get_nodes_in_group("workers"):
		if w is Worker and not w.class_earned.is_connected(_on_worker_class_earned):
			w.class_earned.connect(_on_worker_class_earned)

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

	# Wave countdown — live during the WAITING_TO_SPAWN grace window.
	_refresh_wave_label()

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
	_wave_director = wd
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
	Toasts.show("RAID — defenders incoming", Toasts.COLOR_WARN)

func _on_day_changed(d: int) -> void:
	_refresh_day()
	Toasts.show("Day %d / %d" % [d, Game.campaign_target_day], Toasts.COLOR_INFO)

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
	day_label.text = "Day %d / %d   %s" % [Clock.day_index, Game.campaign_target_day, phase]

func _on_raid_completed() -> void:
	_raid_complete = true
	_refresh_mode()
	Toasts.show("Raid complete — M to return", Toasts.COLOR_GOOD)

func _on_wave_started(wave_idx: int, total: int) -> void:
	wave_label.visible = true
	_wave_idx = wave_idx
	_wave_total = total
	_refresh_wave_label()

# Polled in _process so the countdown to the next wave updates live
# during the WAITING_TO_SPAWN grace window.
func _refresh_wave_label() -> void:
	if not wave_label.visible:
		return
	var base: String = "Wave %d/%d" % [_wave_idx + 1, _wave_total]
	if _wave_director != null and _wave_director.has_method("seconds_until_next_wave"):
		var s: float = _wave_director.seconds_until_next_wave()
		if s >= 0.0:
			base += " — next in %ds" % int(ceil(s))
	wave_label.text = base

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
	build_label.text = "Selected: %s (%dg)   [1 Sleep %dg · 2 Train %dg · 3 Treas %dg · 4 Mine %dg · 5 Kitchen %dg · 6 Library %dg · 7 Jail %dg · LMB place · RMB demolish]" % [
		room.display_name, room.cost,
		Room.make(Room.Type.SLEEPING).cost,
		Room.make(Room.Type.TRAINING).cost,
		Room.make(Room.Type.TREASURY).cost,
		Room.make(Room.Type.MINE).cost,
		Room.make(Room.Type.KITCHEN).cost,
		Room.make(Room.Type.LIBRARY).cost,
		Room.make(Room.Type.JAIL).cost,
	]

func _on_game_over(victory: bool) -> void:
	banner.visible = true
	var head: String = "LAIR DEFENDED" if victory else "LAIR FALLEN"
	banner.text = "%s\nR to restart" % head

func _on_gold_changed(_amount: int) -> void:
	_refresh_gold()

func _on_ore_changed(_amount: int) -> void:
	_refresh_gold()

func _on_food_changed(_amount: int) -> void:
	_refresh_gold()

func _refresh_gold() -> void:
	gold_label.text = "Gold: %d   Ore: %d   Food: %d" % [Economy.gold, Economy.ore, Economy.food]

# --- Toast pipeline ----------------------------------------------------------

const _TOAST_LIFETIME: float = 3.0

func _on_toast_requested(text: String, color: Color) -> void:
	if toast_root == null:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 6)
	# Insert at top so newest toast is most prominent.
	toast_root.add_child(lbl)
	toast_root.move_child(lbl, 0)
	var tw := create_tween().set_parallel(false)
	tw.tween_interval(_TOAST_LIFETIME * 0.7)
	tw.tween_property(lbl, "modulate:a", 0.0, _TOAST_LIFETIME * 0.3)
	tw.tween_callback(lbl.queue_free)

func _on_research_branch_unlocked(branch: String) -> void:
	Toasts.show("Unlocked %s branch" % branch.capitalize(), Toasts.COLOR_GOOD)
	_refresh_research_label()

func _on_research_points_changed(_amount: int) -> void:
	_refresh_research_label()

func _refresh_research_label() -> void:
	if research_label == null:
		return
	var any_unlocked: bool = Research.unlocked.size() > 0
	if Research.points < Research.UNLOCK_COST and not any_unlocked:
		research_label.visible = false
		return
	research_label.visible = true
	var b: String = "✓" if Research.unlocked.has("berserker") else "[F2]"
	var t: String = "✓" if Research.unlocked.has("tactician") else "[F3]"
	var s: String = "✓" if Research.unlocked.has("survivor") else "[F4]"
	research_label.text = "RES %d/%d  %s Bers  %s Tact  %s Surv" % [
		Research.points, Research.UNLOCK_COST, b, t, s,
	]

func _on_worker_class_earned(w: Worker, new_class: String) -> void:
	Toasts.show("%s became a %s" % [String(w.name), new_class], Toasts.COLOR_GOOD)

# Fires once when food crosses below the warning threshold, then re-arms
# only after food climbs back above it. Avoids spam at every tick.
const _FOOD_WARN_AT: int = 10
var _food_warned: bool = false

func _on_food_changed_for_toast(amount: int) -> void:
	if amount <= _FOOD_WARN_AT and not _food_warned:
		_food_warned = true
		Toasts.show("Food critical: %d" % amount, Toasts.COLOR_DANGER)
	elif amount > _FOOD_WARN_AT:
		_food_warned = false

# --- Help overlay (F1) -------------------------------------------------------

const _HELP_FLAG_PATH: String = "user://help_seen.flag"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help_toggle"):
		help_overlay.visible = not help_overlay.visible
	elif event.is_action_pressed("pause_menu") and Game.mode != Game.Mode.BUILDING:
		# Esc in BUILD is reserved for build_cancel (handled by lair.gd);
		# elsewhere it toggles the pause menu. Open closes BUT also
		# unpauses the tree.
		_toggle_pause_menu()

func _toggle_pause_menu() -> void:
	pause_menu.visible = not pause_menu.visible
	get_tree().paused = pause_menu.visible

func _pause_resume() -> void:
	pause_menu.visible = false
	get_tree().paused = false

func _pause_restart() -> void:
	pause_menu.visible = false
	get_tree().paused = false
	get_tree().reload_current_scene()

func _pause_quit() -> void:
	get_tree().quit()

# --- Settings panel ----------------------------------------------------------

const _SETTINGS_PATH: String = "user://settings.json"

func _open_settings() -> void:
	pause_menu.visible = false
	settings_panel.visible = true

func _close_settings() -> void:
	settings_panel.visible = false
	pause_menu.visible = true

func _on_volume_changed(value: float) -> void:
	_apply_volume(value)
	_save_settings()

func _on_fullscreen_toggled(on: bool) -> void:
	_apply_fullscreen(on)
	_save_settings()

func _apply_volume(linear: float) -> void:
	# Linear 0..1 → dB (silence at 0). AudioServer's Master bus is what
	# every AudioStreamPlayer eventually routes through.
	var db: float = -80.0 if linear <= 0.001 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)

func _apply_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)

func _save_settings() -> void:
	var data: Dictionary = {
		"master_volume": vol_slider.value,
		"fullscreen": fullscreen_check.button_pressed,
	}
	var f := FileAccess.open(_SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()

func _load_settings() -> void:
	if not FileAccess.file_exists(_SETTINGS_PATH):
		_apply_volume(vol_slider.value)
		return
	var f := FileAccess.open(_SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed as Dictionary
	vol_slider.value = float(d.get("master_volume", 1.0))
	fullscreen_check.button_pressed = bool(d.get("fullscreen", false))
	_apply_volume(vol_slider.value)
	_apply_fullscreen(fullscreen_check.button_pressed)

func _help_seen() -> bool:
	return FileAccess.file_exists(_HELP_FLAG_PATH)

func _mark_help_seen() -> void:
	var f := FileAccess.open(_HELP_FLAG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("1")
		f.close()

func _build_help_text() -> String:
	return "ORCS' LAIR — KEY MAP   (F1 to close)\n\n" + \
		"LAIR (god view)\n" + \
		"   Tab          possess / cycle champions\n" + \
		"   B            enter Build mode\n" + \
		"   M            world map\n" + \
		"   F5 / F9      quicksave / quickload\n" + \
		"   R            restart scene\n\n" + \
		"BUILD mode\n" + \
		"   1 Sleep · 2 Train · 3 Treas · 4 Mine · 5 Kitchen · 6 Library · 7 Jail\n" + \
		"   LMB place · RMB demolish · Esc / B exit\n\n" + \
		"POSSESSION (third-person)\n" + \
		"   WASD         move (camera-relative)\n" + \
		"   J            attack         K  cleave (AOE)\n" + \
		"   L            charge         N  roar  (wide AOE)\n" + \
		"   Space        dodge (i-frames)\n" + \
		"   Tab          release\n\n" + \
		"WORLD MAP\n" + \
		"   1 Defend Lair · 2 Raid City · M exit\n\n" + \
		"PROGRESSION\n" + \
		"   U / I / O    spend STR / VIT / AGI attribute point\n\n" + \
		"GOAL: survive 30 days. Build a Kitchen by ~day 5 or your\n" + \
		"workers will desert from hunger."
