class_name MountainCamera
extends Camera3D
## Angled top-down camera for the Mountain player.
## Pan: WASD (move_* actions) or hold the middle mouse button and drag.
## Rotate: hold the right mouse button and drag, or Q / E.
## Zoom: mouse wheel. The camera looks at `focus` from `distance` away.

@export var pitch_degrees := -60.0
@export var min_pitch_degrees := -85.0
@export var max_pitch_degrees := -10.0
@export var orbit_sensitivity := 0.3  # degrees per pixel dragged
@export var orbit_key_speed := 90.0  # degrees per second with Q / E
@export var pan_speed := 0.8  # per second, scaled by distance so zoomed-out panning stays fast
@export var zoom_step := 1.12
@export var min_distance := 20.0
@export var max_distance := 140.0
## Map bounds on the ground plane (x, z) that `focus` is clamped to.
## Replaced by the Trail's extent (plus `bounds_margin`) when the level has a Trail.
@export var bounds_min := Vector2(-20.0, -113.0)
@export var bounds_max := Vector2(20.0, 0.0)
@export var bounds_margin := 20.0
## Height the camera looks at; mid-slope keeps the whole mountain framed.
@export var focus_height := 21.0
## Starting view: this far up the trail (0 = bottom, 1 = peak), from `start_distance`,
## so the hikers at the trailhead are big enough to see.
@export var start_trail_fraction := 0.1
@export var start_distance := 55.0

var focus := Vector3(0.0, 21.0, -40.0)
var distance := 130.0
var yaw_degrees := 0.0
## True once the current right-button press has rotated the view, so the
## controller can tell a drag from a right-click (which cancels the ability).
var orbited := false
var _dragging := false
var _orbiting := false


func _ready() -> void:
	focus.y = focus_height
	var trail := Trail.find(get_tree())
	if trail:
		var points := trail.curve.get_baked_points()
		var area := AABB(trail.to_global(points[0]), Vector3.ZERO)
		for p in points:
			area = area.expand(trail.to_global(p))
		bounds_min = Vector2(area.position.x, area.position.z) - Vector2.ONE * bounds_margin
		bounds_max = Vector2(area.end.x, area.end.z) + Vector2.ONE * bounds_margin
		focus = trail.point_at(trail.length() * start_trail_fraction)
		distance = start_distance
	_apply()


func _process(delta: float) -> void:
	var turn := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	if turn != 0.0:
		yaw_degrees += turn * orbit_key_speed * delta
		_apply()
	var dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if dir != Vector2.ZERO:
		focus += _ground(dir) * pan_speed * distance * delta
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_MIDDLE:
				_dragging = mb.pressed
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
				if mb.pressed:
					orbited = false
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance /= zoom_step
					_apply()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance *= zoom_step
					_apply()
	elif event is InputEventMouseMotion and _orbiting:
		var motion := (event as InputEventMouseMotion).relative
		yaw_degrees -= motion.x * orbit_sensitivity
		pitch_degrees -= motion.y * orbit_sensitivity
		if motion.length() > 1.0:
			orbited = true
		_apply()
	elif event is InputEventMouseMotion and _dragging:
		var motion := (event as InputEventMouseMotion).relative
		# Rough "ground follows the cursor" factor for this FOV.
		var factor := distance * 1.2 / get_viewport().get_visible_rect().size.y
		focus -= _ground(motion) * factor
		_apply()


## Turns a screen-space direction (x right, y down) into a ground direction
## for the current yaw, so panning follows the view after rotating.
func _ground(screen: Vector2) -> Vector3:
	return Vector3(screen.x, 0.0, screen.y).rotated(Vector3.UP, deg_to_rad(yaw_degrees))


func _apply() -> void:
	focus.x = clampf(focus.x, bounds_min.x, bounds_max.x)
	focus.z = clampf(focus.z, bounds_min.y, bounds_max.y)
	distance = clampf(distance, min_distance, max_distance)
	pitch_degrees = clampf(pitch_degrees, min_pitch_degrees, max_pitch_degrees)
	rotation_degrees = Vector3(pitch_degrees, yaw_degrees, 0.0)
	# basis.z points backwards from the view direction.
	position = focus + basis.z * distance
