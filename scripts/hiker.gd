extends CharacterBody3D
## Hiker (P1). Friday-night version: movement, camera, networking hooks.
## Stamina, slide, death and rescue get added on Saturday.

@export var walk_speed := 5.0
@export var acceleration := 20.0
@export var mouse_sensitivity := 0.003
## How hard mud pushes you downhill.
@export var mud_slide_force := 12.0

## CONTRACT.md: mud sets this to 0.05 on enter and 1.0 on exit.
var friction_multiplier := 1.0
## Synced to everyone by the MultiplayerSynchronizer.
@export var hp := 100
var is_dummy := false

@onready var model: Node3D = $Model
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _enter_tree() -> void:
	# Runs on every peer before _ready, so authority is set before syncing starts.
	var id := name.to_int()
	is_dummy = id < 0
	set_multiplayer_authority(1 if is_dummy else id)

	add_to_group("hikers")   # CONTRACT.md
	collision_layer = 2       # CONTRACT.md: hikers on layer 2
	collision_mask = 1        # collide with terrain (add obstacle layers later)


func _ready() -> void:
	var is_mine := is_multiplayer_authority() and not is_dummy
	camera.current = is_mine
	set_process_unhandled_input(is_mine)
	if is_mine:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		spring_arm.rotation.x = clamp(
			spring_arm.rotation.x - event.relative.y * mouse_sensitivity, -1.2, 0.3)
	elif event.is_action_pressed("ui_cancel"):
		# Esc frees the mouse, handy with several test windows open.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	# Only the owner moves this hiker; everyone else just receives its position.
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	var input := Vector2.ZERO
	if not is_dummy:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# Move relative to where the camera faces, flattened onto the ground.
	var cam_basis := camera_pivot.global_basis
	var forward := Vector3(-cam_basis.z.x, 0, -cam_basis.z.z).normalized()
	var right := Vector3(cam_basis.x.x, 0, cam_basis.x.z).normalized()
	var direction := (right * input.x + forward * -input.y).limit_length(1.0)

	# Low friction = slow to change speed, so you keep sliding.
	var target := direction * walk_speed
	var accel := acceleration * friction_multiplier
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)

	# On mud, the slope pulls you downhill.
	if friction_multiplier < 1.0 and is_on_floor():
		var downhill := Vector3.DOWN.slide(get_floor_normal()).normalized()
		velocity += downhill * mud_slide_force * (1.0 - friction_multiplier) * delta

	move_and_slide()

	# Turn the model to face where you're walking.
	if direction.length() > 0.1:
		var target_yaw := atan2(-direction.x, -direction.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 10.0 * delta)


# ---------- CONTRACT.md: damage ----------

## The Mountain calls hiker.take_damage.rpc(amount) from the host.
## It arrives on every peer, but only the owner changes HP; the
## synchronizer then shares the new HP with everyone.
@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int) -> void:
	if not is_multiplayer_authority() or hp <= 0:
		return
	hp = max(hp - amount, 0)
	print(multiplayer.get_unique_id(), ": hiker ", name, " took ", amount, ", hp now ", hp)
	if hp == 0:
		_die()


func _die() -> void:
	# Placeholder until Saturday (buried mound, 20 s timer, rescue).
	GameManager.report_state.rpc_id(1, name.to_int(), "buried")
