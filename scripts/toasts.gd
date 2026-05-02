extends Node

# Toasts autoload — global signal hub for transient notifications.
# Anyone can fire a toast via:
#   Toasts.show("Worker1 became a Smith", Color(1, 0.8, 0.3))
# HUD subscribes to toast_requested and renders the queue.

signal toast_requested(text: String, color: Color)

const COLOR_INFO: Color = Color(1, 0.95, 0.7, 1)
const COLOR_GOOD: Color = Color(0.55, 1, 0.55, 1)
const COLOR_WARN: Color = Color(1, 0.7, 0.3, 1)
const COLOR_DANGER: Color = Color(1, 0.4, 0.4, 1)

func show(text: String, color: Color = COLOR_INFO) -> void:
	toast_requested.emit(text, color)
