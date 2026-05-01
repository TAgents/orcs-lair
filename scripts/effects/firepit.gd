extends OmniLight3D

# Soft flicker for the lair firepit. Low-frequency sin (slow swell) plus
# small fast random jitter (sparks) keeps the light feeling alive without
# being jarring. Read once: base_energy in _ready and modulate around it.

@export var base_energy: float = 4.0
@export var swell_amplitude: float = 0.6
@export var swell_speed: float = 1.6
@export var jitter_amplitude: float = 0.25
@export var jitter_hz: float = 12.0

var _t: float = 0.0
var _next_jitter: float = 0.0
var _jitter_target: float = 0.0

func _ready() -> void:
	light_energy = base_energy

func _process(delta: float) -> void:
	_t += delta
	var swell: float = sin(_t * swell_speed) * swell_amplitude
	if _t >= _next_jitter:
		_jitter_target = randf_range(-jitter_amplitude, jitter_amplitude)
		_next_jitter = _t + 1.0 / jitter_hz
	light_energy = max(0.5, base_energy + swell + _jitter_target)
