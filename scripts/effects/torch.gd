extends OmniLight3D

# Wall torch: smaller, faster flicker than the central firepit. Tunable
# via @export so different scenes can change the feel without code edits.

@export var base_energy: float = 1.8
@export var swell_amplitude: float = 0.35
@export var swell_speed: float = 2.4
@export var jitter_amplitude: float = 0.4
@export var jitter_hz: float = 16.0

var _t: float = 0.0
var _next_jitter: float = 0.0
var _jitter_target: float = 0.0
var _phase: float = 0.0

func _ready() -> void:
	# Random phase offset so all torches don't pulse in sync.
	_phase = randf() * TAU
	light_energy = base_energy

func _process(delta: float) -> void:
	_t += delta
	var swell: float = sin(_t * swell_speed + _phase) * swell_amplitude
	if _t >= _next_jitter:
		_jitter_target = randf_range(-jitter_amplitude, jitter_amplitude)
		_next_jitter = _t + 1.0 / jitter_hz
	light_energy = max(0.3, base_energy + swell + _jitter_target)
