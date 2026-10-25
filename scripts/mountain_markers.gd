extends Control
## Mountain markers (P1). Lives in the Mountain's HUD. Draws a dot above every
## hiker in their jacket colour, so the Mountain can spot them from high up.

const HIKER := preload("res://scripts/hiker.gd")
const HEIGHT := 2.4   # metres above the hiker's feet


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for hiker in get_tree().get_nodes_in_group("hikers"):
		var state: String = hiker.state
		if state == "extracted":
			continue
		var hiker_pos: Vector3 = hiker.global_position
		var world_pos := hiker_pos + Vector3.UP * HEIGHT
		# Skip anything behind or level with the camera
		var depth := -(cam.global_transform.affine_inverse() * world_pos).z
		if depth < 0.05:
			continue
		var pos := cam.unproject_position(world_pos)
		var color: Color = HIKER.JACKET_COLORS[hiker.jacket_index % HIKER.JACKET_COLORS.size()]

		if state == "eliminated":
			draw_circle(pos, 6.0, Color(0, 0, 0, 0.6))
			draw_circle(pos, 4.0, Color(0.55, 0.55, 0.55))
			continue
		if state == "unconscious":
			# Pulsing red ring: this hiker is down
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
			draw_circle(pos, 13.0 + pulse * 5.0, Color(1.0, 0.25, 0.2, 0.5))
		draw_circle(pos, 10.0, Color(0, 0, 0, 0.6))
		draw_circle(pos, 8.0, color)
