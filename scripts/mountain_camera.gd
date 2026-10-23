class_name MountainCamera
extends Camera3D
## Angled top-down camera for the Mountain player.
## Pan: WASD (move_* actions) or hold the middle mouse button and drag.
## Zoom: mouse wheel. The camera looks at `focus` from `distance` away.

@export var pitch_degrees := -60.0
@export var pan_speed := 0.8  # per second, scaled by distance so zoomed-out panning stays fast
@export var zoom_step := 1.12
@export var min_distance := 20.0
@export var max_distance := 140.0
## Map bounds on the ground plane (x, z) that `focus` is clamped to.
@export var bounds_min := Vector2(-20.0, -113.0)
@export var bounds_max := Vector2(20.0, 0.0)
## Height the camera looks at; mid-slope keeps the whole mountain framed.
@export var focus_height := 21.0

var focus := Vector3(0.0, 21.0, -40.0)
var distance := 130.0
var _dragging := false


func _ready() -> void:
	rotation_degrees = Vector3(pitch_degrees, 0.0, 0.0)
	focus.y = focus_height
	_apply()


func _process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if dir != Vector2.ZERO:
		focus += Vector3(dir.x, 0.0, dir.y) * pan_speed * distance * delta
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_MIDDLE:
				_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance /= zoom_step
					_apply()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance *= zoom_step
					_apply()
	elif event is InputEventMouseMotion and _dragging:
		var motion := (event as InputEventMouseMotion).relative
		# Rough "ground follows the cursor" factor for this FOV.
		var factor := distance * 1.2 / get_viewport().get_visible_rect().size.y
		focus -= Vector3(motion.x, 0.0, motion.y) * factor
		_apply()


func _apply() -> void:
	focus.x = clampf(focus.x, bounds_min.x, bounds_max.x)
	focus.z = clampf(focus.z, bounds_min.y, bounds_max.y)
	distance = clampf(distance, min_distance, max_distance)
	# basis.z points backwards from the view direction.
	position = focus + basis.z * distance
