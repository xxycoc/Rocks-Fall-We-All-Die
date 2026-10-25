extends TextureRect
## Landslide warning (P1). Lives in the hiker's HUD. Pops up and pulses whenever
## a landslide appears under main.tscn's Obstacles node, then fades out.

@export var show_time := 3.0   # covers the 2 s siren plus a moment after
var _time_left := 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var obstacles := get_tree().current_scene.get_node_or_null("Obstacles")
	if obstacles:
		obstacles.child_entered_tree.connect(_on_obstacle_added)


func _on_obstacle_added(node: Node) -> void:
	# The Mountain's landslide scene was just spawned on this machine
	if "landslide" in node.scene_file_path.to_lower() or "landslide" in String(node.name).to_lower():
		_time_left = show_time


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		visible = false
		return
	_time_left -= delta
	visible = true
	# Pulse from the centre, and fade out over the last half second
	pivot_offset = size / 2.0
	var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() / 90.0)
	scale = Vector2(pulse, pulse)
	modulate.a = clampf(_time_left / 0.5, 0.0, 1.0)
