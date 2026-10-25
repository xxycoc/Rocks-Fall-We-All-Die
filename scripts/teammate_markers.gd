extends Control
## Teammate markers (P1). Lives in the hiker's HUD. Shows where every teammate is,
## even through fog, and how long a downed teammate has left. Off-screen teammates
## are pinned to the edge of the screen, in their direction.

const HIKER := preload("res://scripts/hiker.gd")
const EDGE := 40.0        # how far from the screen edge off-screen markers sit
const FONT_SIZE := 15

const HEAD_HEIGHT := 2.6   # metres above the feet for a standing hiker
const DOWN_HEIGHT := 1.2   # metres above a lying body

@onready var me: Node3D = owner   # the hiker this HUD belongs to


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or me == null:
		return
	var font := get_theme_default_font()
	var screen_size := get_viewport_rect().size
	var center := screen_size / 2.0
	var safe := Rect2(Vector2(EDGE, EDGE), screen_size - Vector2(EDGE, EDGE) * 2.0)
	for hiker in get_tree().get_nodes_in_group("hikers"):
		if hiker == me or hiker.state == "eliminated" or hiker.state == "extracted":
			continue
		var down: bool = hiker.state == "unconscious"
		var hiker_pos: Vector3 = hiker.global_position
		# Float above the head, or above the middle of a lying body
		var world_pos := hiker_pos + Vector3.UP * HEAD_HEIGHT
		if down:
			var body_middle: Vector3 = (hiker_pos + hiker.drag_point.global_position) / 2.0
			world_pos = body_middle + Vector3.UP * DOWN_HEIGHT
		# How far in front of the camera the point is (negative = behind)
		var depth := -(cam.global_transform.affine_inverse() * world_pos).z
		if absf(depth) < 0.05:
			continue   # exactly level with the lens: can't be placed on screen, skip this frame
		var behind := depth < 0.0
		var pos := cam.unproject_position(world_pos)
		var on_screen := not behind and safe.has_point(pos)
		if on_screen:
			pos.y -= 10.0   # float a few pixels higher so it never touches the head
		else:
			# Pin to the screen edge, in the teammate's direction
			var dir := pos - center
			if behind:
				# Behind the camera: point to the bottom of the screen, on the correct side
				dir = Vector2(center.x - pos.x, screen_size.y)
			if dir.length() < 0.01:
				dir = Vector2.DOWN
			dir = dir.normalized()
			var half := center - Vector2(EDGE, EDGE)
			var reach := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
			pos = center + dir * reach

		var color: Color = HIKER.JACKET_COLORS[hiker.jacket_index % HIKER.JACKET_COLORS.size()]
		var dist := me.global_position.distance_to(hiker_pos)
		if down:
			# Pulsing red ring so a downed teammate stands out
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
			draw_circle(pos, 14.0 + pulse * 6.0, Color(1.0, 0.25, 0.2, 0.5))
		draw_circle(pos, 11.0, Color(0, 0, 0, 0.6))
		draw_circle(pos, 9.0, color)

		var label := "%d m" % dist
		if down:
			label = "HELP  %ds  ·  %d m" % [ceili(hiker.get_knockout_left()), dist]
		var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var text_pos := pos + Vector2(-text_w / 2.0, -18.0)
		# Keep the label on screen near the edges
		text_pos.x = clampf(text_pos.x, 4.0, screen_size.x - text_w - 4.0)
		text_pos.y = maxf(text_pos.y, FONT_SIZE + 4.0)
		var text_color := Color(1.0, 0.5, 0.45) if down else Color.WHITE
		draw_string_outline(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, Color.BLACK)
		draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, text_color)
