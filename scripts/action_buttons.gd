extends Control
## Action buttons (P1). Lives in the hiker's HUD.
## - Jump and Dash sit in a bar at the bottom right of the screen.
## - Rescue and Drag float over the downed teammate you're next to (or dragging).
## Each button shows its key, name and cost, a cooldown sweep with a countdown,
## and a progress ring while holding Rescue. Greyed out when you can't use it.

const RADIUS := 34.0             # bar buttons
const WORLD_RADIUS := 28.0       # buttons floating over a teammate
const BAR_SPACING := 96.0        # centre-to-centre distance in the bar
const WORLD_SPACING := 124.0
const MARGIN := 28.0             # gap from the screen edges
const HOVER_HEIGHT := 0.4        # metres above the downed body
const ACCENT := Color("F2C14E")
const ACTIVE := Color("5FD4C4")
const DIM := Color(0.45, 0.5, 0.53)
const BG := Color(0.06, 0.1, 0.12, 0.85)

@onready var me = owner   # the hiker this HUD belongs to (untyped so its variables can be read)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if me == null or me.state != "alive":
		return
	var font := get_theme_default_font()

	# Bottom-right bar: Jump and Dash
	var bar := _bar_buttons()
	var y := size.y - MARGIN - RADIUS - 44.0   # leave room for the labels underneath
	var x := size.x - MARGIN - RADIUS - (bar.size() - 1) * BAR_SPACING
	for button in bar:
		_draw_button(Vector2(x, y), button, font, RADIUS)
		x += BAR_SPACING

	# Rescue and Drag, floating over the teammate you're helping
	var target = me.carrying if me.carrying != null else me._rescue_target
	if target == null or not is_instance_valid(target):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var target_pos: Vector3 = target.global_position
	var chest: Vector3 = target.drag_point.global_position
	var world_pos := (target_pos + chest) / 2.0 + Vector3.UP * HOVER_HEIGHT
	var depth := -(cam.global_transform.affine_inverse() * world_pos).z
	if depth < 0.05:
		return   # behind the camera, or level with the lens
	var center := cam.unproject_position(world_pos)
	var helpers := _helper_buttons()
	var hx := center.x - (helpers.size() - 1) * WORLD_SPACING / 2.0
	for button in helpers:
		_draw_button(Vector2(hx, center.y), button, font, WORLD_RADIUS)
		hx += WORLD_SPACING


func _bar_buttons() -> Array:
	var stamina: float = me.stamina
	var on_floor: bool = me.is_on_floor()
	var dragging: bool = me.carrying != null
	return [
		{
			"key": "SPACE", "name": "Jump", "info": "%d stamina" % me.jump_cost,
			"ready": on_floor and not me.is_crawling and not dragging and stamina >= me.jump_cost,
		},
		{
			"key": "E", "name": "Dash", "info": "%d stamina" % me.slide_cost,
			"ready": on_floor and stamina >= me.slide_cost and me._slide_cooldown_left <= 0.0,
			"cooldown": me._slide_cooldown_left, "cooldown_total": me.slide_cooldown,
		},
	]


func _helper_buttons() -> Array:
	var stamina: float = me.stamina
	var has_target: bool = me._rescue_target != null
	var dragging: bool = me.carrying != null
	return [
		{
			"key": "F", "name": "Rescue", "info": "hold · %d stamina" % me.rescue_cost,
			"ready": has_target and stamina >= me.rescue_cost,
			"progress": me._rescue_progress / me.rescue_hold_time,
		},
		{
			"key": "G", "name": "Let go" if dragging else "Drag", "info": "-2 stamina / 3 s",
			"ready": dragging or (has_target and stamina > 0.0),
			"active": dragging,
		},
	]


func _draw_button(c: Vector2, b: Dictionary, font: Font, r: float) -> void:
	var usable: bool = b.get("ready", false)
	var active: bool = b.get("active", false)
	var cooldown: float = b.get("cooldown", 0.0)
	var total: float = b.get("cooldown_total", 0.0)
	var progress: float = b.get("progress", 0.0)
	var accent := ACTIVE if active else ACCENT
	var ring := accent if (usable or active) else DIM

	# Circle and rim
	draw_circle(c, r, BG)
	if active:
		draw_circle(c, r - 4.0, Color(accent, 0.3))
	draw_arc(c, r - 1.5, 0.0, TAU, 48, ring, 3.0, true)

	# Cooldown: a dark sweep that shrinks clockwise, plus the seconds left
	if cooldown > 0.0 and total > 0.0:
		var frac := clampf(cooldown / total, 0.0, 1.0)
		var points := PackedVector2Array([c])
		var steps := 40
		for i in steps + 1:
			var angle := -PI / 2.0 + TAU * frac * float(i) / steps
			points.append(c + Vector2(cos(angle), sin(angle)) * (r - 3.0))
		draw_colored_polygon(points, Color(0, 0, 0, 0.55))

	# Hold progress (Rescue): a ring filling up around the outside
	if progress > 0.0:
		draw_arc(c, r + 6.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(progress, 0.0, 1.0),
				48, ACTIVE, 5.0, true)

	# Centre text: the countdown while cooling down, otherwise the key
	var text_color := Color.WHITE if (usable or active) else DIM
	var scale := r / RADIUS
	if cooldown > 0.0:
		_centered(font, "%.1f" % cooldown, c + Vector2(0, 9 * scale), int(24 * scale), Color.WHITE)
	else:
		var key: String = b.key
		var key_size := int((14 if key.length() > 1 else 26) * scale)
		_centered(font, key, c + Vector2(0, key_size * 0.35), key_size, text_color)

	# Name and cost under the circle
	_centered(font, b.name, c + Vector2(0, r + 20), 16, text_color)
	_centered(font, b.info, c + Vector2(0, r + 37), 12, Color(text_color, 0.75))


func _centered(font: Font, text: String, pos: Vector2, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p := pos - Vector2(w / 2.0, 0)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
