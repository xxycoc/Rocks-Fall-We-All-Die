extends CharacterBody3D
## Hiker (P1). Friday-night version: movement, camera, networking hooks.
## Stamina, slide, death and rescue get added on Saturday.

@export var walk_speed := 5.0
## Slopes (strongest when moving straight up or down a steep slope)
@export var uphill_slow := 0.4      # up to 40% slower uphill
@export var downhill_boost := 0.5   # up to 50% faster downhill

@export var acceleration := 20.0
@export var mouse_sensitivity := 0.003
## How hard mud pushes you downhill.
@export var mud_slide_force := 12.0

## Stamina
@export var max_stamina := 50.0
@export var start_stamina := 30.0
@export var climb_drain_per_second := 1.0 / 3.0   # 1 stamina every 3 s
@export var rest_regen_per_second := 2.0
@export var crawl_threshold := 10.0
@export var crawl_speed := 1.5

## Slide-Dodge
@export var slide_cost := 3.0
@export var slide_speed := 12.0
@export var slide_duration := 0.4
@export var slide_cooldown := 2.0

## Knockout
@export var knockout_time := 20.0

## Rescue
@export var rescue_range := 2.0
@export var rescue_hold_time := 2.0
@export var rescue_cost := 20.0
@export var revive_hp := 50

## CONTRACT.md: mud sets this to 0.05 on enter and 1.0 on exit.
var friction_multiplier := 1.0
## Synced to everyone by the MultiplayerSynchronizer.
@export var hp := 100
var is_dummy := false

var stamina := 0.0
var is_crawling := false
var _last_height := 0.0
var _still_time := 0.0

var _slide_time_left := 0.0
var _slide_cooldown_left := 0.0
var _slide_direction := Vector3.ZERO

## "alive", "unconscious" or "eliminated". Exported so it can be synced.
@export var state := "alive"
var knockout_time_left := 0.0
var _rescue_target: Node3D = null
var _rescue_progress := 0.0

@export var rest_delay := 1.0   # seconds of standing still before regen starts

@onready var model: Node3D = $Model
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

@onready var hud: CanvasLayer = $HUD
@onready var hp_bar: ProgressBar = %HPBar
@onready var hp_label: Label = %HPLabel
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var stamina_label: Label = %StaminaLabel

@onready var rescue_label: Label = %RescueLabel

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
	hud.visible = is_mine
	set_process_unhandled_input(is_mine)
	if is_mine:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	stamina = start_stamina
	_last_height = global_position.y

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
		
	if state != "alive":
		if state == "unconscious":
			knockout_time_left -= delta
			if knockout_time_left <= 0.0:
				eliminate()
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

	_update_rescue(delta)
	if _rescue_progress > 0.0:
		direction = Vector3.ZERO   # stand still while rescuing

	_slide_cooldown_left = max(_slide_cooldown_left - delta, 0.0)
	if not is_dummy and Input.is_action_just_pressed("slide"):
		_try_slide(direction)

	if _slide_time_left > 0.0:
		# Mid-slide: shoot along the slide direction, ignore input
		_slide_time_left -= delta
		velocity.x = _slide_direction.x * slide_speed
		velocity.z = _slide_direction.z * slide_speed
	else:
		var speed := crawl_speed if is_crawling else walk_speed
		speed *= _slope_multiplier(direction)
		var target := direction * speed
		var accel := acceleration * friction_multiplier
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)

	# Squash the model while sliding so it looks like a dive
	model.scale.y = 0.6 if _slide_time_left > 0.0 else 1.0
	# On mud, the slope pulls you downhill.
	if friction_multiplier < 1.0 and is_on_floor():
		var downhill := Vector3.DOWN.slide(get_floor_normal()).normalized()
		velocity += downhill * mud_slide_force * (1.0 - friction_multiplier) * delta

	move_and_slide()
	_update_stamina(delta, direction.length() > 0.1 or _slide_time_left > 0.0)
	
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
	if not is_multiplayer_authority() or state != "alive":
		return
	hp = max(hp - amount, 0)
	print(multiplayer.get_unique_id(), ": hiker ", name, " took ", amount, ", hp now ", hp)
	if hp == 0:
		_die()


func _die() -> void:
	state = "unconscious"
	knockout_time_left = knockout_time
	_slide_time_left = 0.0
	velocity = Vector3.ZERO
	GameManager.report_state.rpc_id(1, name.to_int(), "unconscious")


## Also called by the kill zone (step 2).
func eliminate() -> void:
	if state == "eliminated":
		return
	state = "eliminated"
	GameManager.report_state.rpc_id(1, name.to_int(), "eliminated")

func extract() -> void:
	if state != "alive":
		return
	state = "extracted"
	GameManager.report_state.rpc_id(1, name.to_int(), "extracted")

# ---------- Stamina ----------

func _update_stamina(delta: float, is_moving: bool) -> void:
	var climb_rate := (global_position.y - _last_height) / delta
	_last_height = global_position.y

	if is_moving:
		_still_time = 0.0
	if is_moving and climb_rate > 0.2:
		# Walking uphill
		stamina -= climb_drain_per_second * delta
	elif not is_moving and is_on_floor():
		_still_time += delta
		if _still_time >= rest_delay:
			stamina += rest_regen_per_second * delta
			
	stamina = clamp(stamina, 0.0, max_stamina)
	is_crawling = stamina <= crawl_threshold


## Other abilities call this. Returns false if there isn't enough stamina.
func spend_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina -= amount
	return true

func _process(_delta: float) -> void:
	# Visuals run on every machine, using the synced state.
	# Unconscious = lying on their side. Eliminated = hidden.
	var knocked_out := state == "unconscious"
	model.rotation.z = PI / 2 if knocked_out else 0.0
	model.position.y = 0.4 if knocked_out else 0.0
	model.visible = state == "alive" or state == "unconscious"
	# Escaped or eliminated hikers shouldn't block anyone
	$CollisionShape3D.disabled = not model.visible

	if not hud.visible:
		return
	hp_bar.value = hp
	stamina_bar.value = stamina
	stamina_label.text = "Stamina  %d / %d%s" % [stamina, max_stamina, "  (crawling)" if is_crawling else ""]
	stamina_bar.modulate = Color(1, 0.4, 0.4) if is_crawling else Color(1, 1, 1)
	match state:
		"unconscious":
			hp_label.text = "UNCONSCIOUS  %d s left" % ceil(knockout_time_left)
		"eliminated":
			hp_label.text = "ELIMINATED"
		"extracted":
			hp_label.text = "ESCAPED! Waiting for the others"
		_:
			hp_label.text = "HP  %d / 100" % hp
			
	rescue_label.visible = state == "alive" and _rescue_target != null
	if rescue_label.visible:
		if stamina < rescue_cost:
			rescue_label.text = "Need %d stamina to rescue" % rescue_cost
		else:
			rescue_label.text = "Hold F to rescue  %.1f / %.1f s" % [_rescue_progress, rescue_hold_time]
# ---------- Slide-Dodge ----------

func _try_slide(direction: Vector3) -> void:
	if _slide_cooldown_left > 0.0 or _slide_time_left > 0.0 or not is_on_floor():
		return
	if not spend_stamina(slide_cost):
		return
	# Slide where you're moving, or where you're facing if standing still
	var dir := direction
	if dir.length() < 0.1:
		dir = -model.global_basis.z
		dir.y = 0.0
	_slide_direction = dir.normalized()
	_slide_time_left = slide_duration
	_slide_cooldown_left = slide_cooldown

# ---------- Rescue ----------

func _update_rescue(delta: float) -> void:
	_rescue_target = null if is_dummy else _find_rescue_target()
	if _rescue_target == null or not Input.is_action_pressed("interact") or stamina < rescue_cost:
		_rescue_progress = 0.0
		return
	_rescue_progress += delta
	if _rescue_progress >= rescue_hold_time:
		_rescue_progress = 0.0
		spend_stamina(rescue_cost)
		_rescue_target.revive.rpc()


## The closest unconscious teammate within range, or null.
func _find_rescue_target() -> Node3D:
	var best: Node3D = null
	var best_dist := rescue_range
	for hiker in get_tree().get_nodes_in_group("hikers"):
		if hiker == self or hiker.state != "unconscious":
			continue
		var dist := global_position.distance_to(hiker.global_position)
		if dist <= best_dist:
			best = hiker
			best_dist = dist
	return best


## Sent to everyone, but only the downed hiker's owner acts on it.
@rpc("any_peer", "call_local", "reliable")
func revive() -> void:
	if not is_multiplayer_authority() or state != "unconscious":
		return
	state = "alive"
	hp = revive_hp
	GameManager.report_state.rpc_id(1, name.to_int(), "alive")

# ---------- Slopes ----------

## 1.0 on flat ground, below 1 going uphill, above 1 going downhill.
func _slope_multiplier(direction: Vector3) -> float:
	if not is_on_floor() or direction.length() < 0.1:
		return 1.0
	var normal := get_floor_normal()
	# On a slope the floor normal leans toward the downhill side.
	var downhill := Vector3(normal.x, 0.0, normal.z)
	var steepness := downhill.length()   # 0 = flat, about 0.7 at 45 degrees
	if steepness < 0.01:
		return 1.0
	# +1 = heading straight downhill, -1 = straight uphill, 0 = across
	var along := direction.normalized().dot(downhill.normalized()) * steepness
	if along > 0.0:
		return 1.0 + along * downhill_boost
	return 1.0 + along * uphill_slow
