class_name HUDTheme
extends RefCounted

# Builds a Theme resource at runtime that gives the HUD a cozy-sim
# fantasy feel without external textures. StyleBoxFlat-based so it scales
# cleanly to any resolution and stays in sync with the engine's tint
# adjustments. Applied to the HUD's root Control in hud.gd._ready —
# theme cascades automatically to every descendant.
#
# Palette (warm-dark fantasy tavern):
#   parchment text   — Color(1.00, 0.92, 0.78)
#   gold accent      — Color(0.95, 0.78, 0.35)
#   ember warning    — Color(0.95, 0.45, 0.20)
#   dark wood bg     — Color(0.13, 0.09, 0.07)
#   iron frame       — Color(0.32, 0.24, 0.16)
#
# Aim is "this looks designed" not "this looks crafted" — programmatic
# style boxes give us 80% of the look at 5% of the asset cost. Drop a
# theme.tres + custom font later if we want the last 20%.

const PARCHMENT: Color = Color(1.00, 0.92, 0.78, 1)
const PARCHMENT_DIM: Color = Color(0.78, 0.72, 0.60, 1)
const GOLD: Color = Color(0.95, 0.78, 0.35, 1)
const EMBER: Color = Color(0.95, 0.45, 0.20, 1)
const WOOD_BG: Color = Color(0.13, 0.09, 0.07, 0.92)
const WOOD_BG_OPAQUE: Color = Color(0.13, 0.09, 0.07, 1)
const IRON_FRAME: Color = Color(0.32, 0.24, 0.16, 1)

static func build() -> Theme:
	var t := Theme.new()
	_style_buttons(t)
	_style_labels(t)
	_style_panels(t)
	_style_progress(t)
	_style_slider(t)
	_style_checkbox(t)
	return t

static func _style_buttons(t: Theme) -> void:
	t.set_stylebox("normal", "Button", _btn_style(WOOD_BG_OPAQUE, IRON_FRAME))
	var hover := WOOD_BG_OPAQUE.lerp(IRON_FRAME, 0.35)
	t.set_stylebox("hover", "Button", _btn_style(hover, GOLD))
	t.set_stylebox("pressed", "Button", _btn_style(Color(0.08, 0.05, 0.03, 1), IRON_FRAME))
	t.set_stylebox("focus", "Button", _btn_style(WOOD_BG_OPAQUE, GOLD))
	t.set_stylebox("disabled", "Button", _btn_style(Color(0.10, 0.08, 0.07, 0.7), IRON_FRAME.darkened(0.4)))
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", PARCHMENT_DIM)
	t.set_color("font_disabled_color", "Button", PARCHMENT_DIM.darkened(0.4))
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 1))
	t.set_constant("outline_size", "Button", 2)

static func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.border_color = border
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 4
	return s

static func _style_labels(t: Theme) -> void:
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 1))
	t.set_constant("outline_size", "Label", 4)

static func _style_panels(t: Theme) -> void:
	# ColorRect doesn't take a stylebox, but Panel does — used for any future
	# ColorRect→Panel migration. Today's HUD uses ColorRect overlays for
	# pause / settings; we leave those as-is and let labels + buttons inside
	# carry the new style.
	var s := StyleBoxFlat.new()
	s.bg_color = WOOD_BG
	s.border_width_left = 3
	s.border_width_right = 3
	s.border_width_top = 3
	s.border_width_bottom = 3
	s.border_color = GOLD
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	t.set_stylebox("panel", "Panel", s)
	t.set_stylebox("panel", "PanelContainer", s)

static func _style_progress(t: Theme) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.04, 0.03, 0.9)
	bg.border_width_left = 1
	bg.border_width_right = 1
	bg.border_width_top = 1
	bg.border_width_bottom = 1
	bg.border_color = IRON_FRAME
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_left = 4
	bg.corner_radius_bottom_right = 4
	t.set_stylebox("background", "ProgressBar", bg)
	var fill := StyleBoxFlat.new()
	# Warm hp gradient — saturated red on the left fading to ember on the
	# right would need a shader; flat ember reads almost as well at this
	# scale and is one allocation.
	fill.bg_color = Color(0.85, 0.32, 0.22, 1)
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3
	t.set_stylebox("fill", "ProgressBar", fill)

static func _style_slider(t: Theme) -> void:
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(0.06, 0.04, 0.03, 0.9)
	groove.border_width_top = 1
	groove.border_width_bottom = 1
	groove.border_color = IRON_FRAME
	groove.corner_radius_top_left = 3
	groove.corner_radius_top_right = 3
	groove.corner_radius_bottom_left = 3
	groove.corner_radius_bottom_right = 3
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("slider", "VSlider", groove)
	var grab := StyleBoxFlat.new()
	grab.bg_color = GOLD
	grab.corner_radius_top_left = 8
	grab.corner_radius_top_right = 8
	grab.corner_radius_bottom_left = 8
	grab.corner_radius_bottom_right = 8
	# 16x16 grabber — Godot picks size from texture, but with stylebox
	# we hint via content_margin on the area style; default works fine.
	t.set_stylebox("grabber_area", "HSlider", grab)

static func _style_checkbox(t: Theme) -> void:
	t.set_color("font_color", "CheckBox", PARCHMENT)
	t.set_color("font_hover_color", "CheckBox", GOLD)
	t.set_color("font_outline_color", "CheckBox", Color(0, 0, 0, 1))
	t.set_constant("outline_size", "CheckBox", 2)
