extends Node

# Game-clock autoload. Drives the day/night cycle every Direction-A system
# hangs off of: room production (per in-game hour), food consumption (per
# day), research accrual, raid gating to night, multi-day campaign timer.
#
# DAY_LENGTH_S defaults to 360s (6 real-time minutes per in-game day).
# time_of_day is normalised [0.0, 1.0): 0.0 = midnight, 0.25 = sunrise,
# 0.5 = noon, 0.75 = sunset.

const DAY_LENGTH_S: float = 360.0

signal day_changed(new_day: int)
signal time_changed(time_of_day: float)

var day_index: int = 1
var time_of_day: float = 0.25  # start at sunrise

func _process(delta: float) -> void:
	var step: float = delta / DAY_LENGTH_S
	time_of_day += step
	while time_of_day >= 1.0:
		time_of_day -= 1.0
		day_index += 1
		day_changed.emit(day_index)
	time_changed.emit(time_of_day)

# True when sun is below the horizon (dusk → dawn). Useful for raid gating.
func is_night() -> bool:
	return time_of_day < 0.25 or time_of_day >= 0.75

# Test/save helpers.
func reset(d: int = 1, t: float = 0.25) -> void:
	day_index = d
	time_of_day = clamp(t, 0.0, 0.999)
	day_changed.emit(day_index)
	time_changed.emit(time_of_day)

# Advance time by N in-game hours (24 hours per day) — for scenarios that
# want to fast-forward without sleeping in real time.
func advance_hours(hours: float) -> void:
	var step: float = hours / 24.0
	time_of_day += step
	while time_of_day >= 1.0:
		time_of_day -= 1.0
		day_index += 1
		day_changed.emit(day_index)
	time_changed.emit(time_of_day)
