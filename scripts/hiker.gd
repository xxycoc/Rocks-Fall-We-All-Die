extends CharacterBody3D
## Hiker (P1). Friday-night version: movement, camera, networking hooks.
## Stamina, slide, death and rescue get added on Saturday.

@export var walk_speed := 5.0
@export var jump_velocity := 5.0   # about 1.3 m high
@export var jump_cost := 2.0       # stamina per jump
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

## Carry (drag with a rope)
@export var carry_drain_per_second := 2.0 / 3.0   # 2 stamina every 3 s
@export var carry_speed_multiplier := 0.6

@export var rope_length := 2.5
@export var rope_stiffness := 20.0     # how hard a tight rope pulls

@export var body_friction := 6.0       # how quickly a sliding body stops
@export var body_slope_slide := 1.0    # how much steep slopes pull bodies downhill

## Animation names, exactly as they appear in the .glb
@export var anim_idle := "Idle"
@export var anim_walk := "Walk"
@export var anim_crawl := "Crawl"
@export var anim_dead := "Dead"

## The animation everyone should see. Set by the owner, synced to others.
@export var anim_state := "Idle"
var anim_player: AnimationPlayer = null
var _body_visual: Node3D = null   # the imported model, tilted to fit slopes when lying down

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

var carrying: Node3D = null    # who I'm dragging
var carried_by: Node3D = null  # who's dragging me (known on every machine)

@export var rest_delay := 1.0   # seconds of standing still before regen starts

## Looks
const JACKET_COLORS := [Color("F2C14E"), Color("6FB7FF"), Color("FF8FB1"), Color("9BE07A")]
## The face texture is a 2x2 grid; each face is a shift of the texture
const FACE_OFFSETS := {
	"normal": Vector3(0.0, 0.0, 0.0),
	"unconscious": Vector3(0.0, 0.5, 0.0),
	"dead": Vector3(0.5, 0.0, 0.0),
	"happy": Vector3(0.5, 0.5, 0.0),
}
@export var face_material_name := "Material"   # the face's material name in the .glb

## Synced: when it changes on any machine, the jacket recolours.
@export var jacket_index := 0:
	set(value):
		jacket_index = value
		_apply_jacket()

var _jacket_mat: StandardMaterial3D = null
var _face_mat: StandardMaterial3D = null

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

@onready var rope_point: Marker3D = $Model/RopePoint
@onready var rope: MeshInstance3D = $Rope
@onready var drag_point: Marker3D = $Model/DragPoint

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
	# Find the model's animations and make the looping ones loop
	anim_player = model.find_child("AnimationPlayer", true, false)
	if anim_player:
		for anim_name in [anim_idle, anim_walk, anim_crawl]:
			if anim_player.has_animation(anim_name):
				anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		_body_visual = anim_player.get_parent()
	_setup_looks()

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
			_update_unconscious_body(delta)
			if knockout_time_left <= 0.0:
				eliminate()
		return
		
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if not is_dummy and Input.is_action_just_pressed("jump") and is_on_floor() \
			and not is_crawling and carrying == null and spend_stamina(jump_cost):
		velocity.y = jump_velocity

	var input := Vector2.ZERO
	if not is_dummy:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# Move relative to where the camera faces, flattened onto the ground.
	var cam_basis := camera_pivot.global_basis
	var forward := Vector3(-cam_basis.z.x, 0, -cam_basis.z.z).normalized()
	var right := Vector3(cam_basis.x.x, 0, cam_basis.x.z).normalized()
	var direction := (right * input.x + forward * -input.y).limit_length(1.0)

	_update_rescue(delta)
	_update_carry()
	if not is_dummy and Input.is_action_just_pressed("carry"):
		_toggle_carry()
	
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
		if carrying != null:
			speed *= carry_speed_multiplier
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
	_drop()
	state = "unconscious"
	knockout_time_left = knockout_time
	_slide_time_left = 0.0
	velocity = Vector3.ZERO
	GameManager.report_state.rpc_id(1, name.to_int(), "unconscious")


## Also called by the kill zone (step 2).
func eliminate() -> void:
	_drop()
	if state == "eliminated":
		return
	state = "eliminated"
	GameManager.report_state.rpc_id(1, name.to_int(), "eliminated")

func extract() -> void:
	_drop()
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
	if carrying != null:
		stamina -= carry_drain_per_second * delta
	if is_moving and climb_rate > 0.2:
		# Walking uphill
		stamina -= climb_drain_per_second * delta
	elif not is_moving and is_on_floor() and carrying == null:
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
	# Unconscious = lying on their side. Escaped/eliminated = hidden.
	# The owner decides the animation; every machine plays it
	if is_multiplayer_authority():
		anim_state = _pick_anim()
	_play_anim(anim_state)
	
	# Unconscious and dead bodies lie on the ground. Escaped hikers are hidden.
	model.visible = state != "extracted"
	# Dead or escaped hikers shouldn't block anyone
	$CollisionShape3D.disabled = state == "eliminated" or state == "extracted"
	_fit_body_to_ground()

	# Face matches the state
	if _face_mat:
		var face := "normal"
		match state:
			"unconscious": face = "unconscious"
			"eliminated": face = "dead"
			"extracted": face = "happy"
		_face_mat.uv1_offset = FACE_OFFSETS[face]
		
	# The dragged hiker draws the rope, since every machine knows carried_by
	var dragged := is_instance_valid(carried_by)
	rope.visible = dragged
	if dragged:
		var from: Vector3 = carried_by.rope_point.global_position
		var to := drag_point.global_position
		var dist := from.distance_to(to)
		if dist > 0.05:
			var b := Basis.looking_at(to - from, Vector3.UP)
			b.z *= dist   # stretch the 1 m box to the full length
			rope.global_transform = Transform3D(b, (from + to) / 2.0)

	# Everything below is this player's own HUD
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

	rescue_label.visible = state == "alive" and (_rescue_target != null or carrying != null)
	if rescue_label.visible:
		if carrying != null:
			rescue_label.text = "Dragging a teammate · G to let go"
		elif stamina < rescue_cost:
			rescue_label.text = "G to drag · need %d stamina to rescue" % rescue_cost
		else:
			rescue_label.text = "Hold F to rescue (%.1f / %.1f s) · G to drag" % [_rescue_progress, rescue_hold_time]
			
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

# ---------- Carry ----------

func _toggle_carry() -> void:
	if carrying != null:
		_drop()
		return
	var target := _find_rescue_target()
	if target == null or is_instance_valid(target.carried_by) or stamina <= 0.0:
		return
	carrying = target
	target.set_carried_by.rpc(name)


func _update_carry() -> void:
	if carrying == null:
		return
	if not is_instance_valid(carrying):
		carrying = null
		return
	# Let go if they're revived/eliminated or we're out of stamina
	if carrying.state != "unconscious" or stamina <= 0.0:
		_drop()


func _drop() -> void:
	if carrying == null:
		return
	if is_instance_valid(carrying):
		carrying.set_carried_by.rpc("")
	carrying = null


## Runs on every machine so everyone knows who is dragging whom.
@rpc("any_peer", "call_local", "reliable")
func set_carried_by(carrier_name: String) -> void:
	carried_by = get_parent().get_node_or_null(carrier_name) if carrier_name != "" else null

## Unconscious bodies slide with momentum: pulled by the rope,
## slowed by the ground, and dragged down steep slopes.
func _update_unconscious_body(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var on_floor := is_on_floor()

	if on_floor:
		# Ground friction slows the body down (much less on mud)
		horizontal = horizontal.move_toward(Vector3.ZERO, body_friction * friction_multiplier * delta)
		# Steep ground pulls the body downhill
		var downhill := Vector3.DOWN.slide(get_floor_normal())
		horizontal += Vector3(downhill.x, 0.0, downhill.z) * _gravity * body_slope_slide * delta

	if is_instance_valid(carried_by):
		var to_me := global_position - carried_by.global_position
		to_me.y = 0.0
		var stretch := to_me.length() - rope_length
		if stretch > 0.0:
			var dir := to_me.normalized()
			# The tight rope pulls like a spring
			horizontal -= dir * stretch * rope_stiffness * delta
			# And never lets the body move further away
			var away := horizontal.dot(dir)
			if away > 0.0:
				horizontal -= dir * away
		# Turn so the head points toward the carrier
		if to_me.length() > 0.1:
			var target_yaw := atan2(to_me.x, to_me.z)
			model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 8.0 * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = 0.0 if on_floor else velocity.y - _gravity * delta
	move_and_slide()

# ---------- New round ----------

## Sent by the host to everyone. Each owner resets their own hiker,
## and the synchronizer shares the result.
@rpc("any_peer", "call_local", "reliable")
func reset_for_round(spawn_pos: Vector3) -> void:
	carrying = null
	carried_by = null
	if not is_multiplayer_authority():
		return
	state = "alive"
	hp = 100
	stamina = start_stamina
	velocity = Vector3.ZERO
	global_position = spawn_pos
	_last_height = spawn_pos.y
	knockout_time_left = 0.0
	_slide_time_left = 0.0
	_rescue_progress = 0.0
	if not is_dummy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ---------- Animation ----------

## Owner only: which animation fits what the hiker is doing right now.
func _pick_anim() -> String:
	if state == "unconscious" or state == "eliminated":
		return anim_dead
	if state != "alive":
		return anim_idle
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	if moving:
		return anim_crawl if is_crawling else anim_walk
	return anim_idle


## Every machine: play it, with a short blend so switches look smooth.
func _play_anim(anim_name: String) -> void:
	if anim_player == null:
		return
	if not anim_player.has_animation(anim_name):
		anim_name = anim_idle   # fallback while animations are missing
	if anim_player.current_animation != anim_name and anim_player.has_animation(anim_name):
		anim_player.play(anim_name, 0.2)

# ---------- Looks ----------

## Give this hiker its own jacket and face materials, so changing
## one hiker doesn't change all of them.
func _setup_looks() -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat == null:
				continue
			if mat.resource_name == "Color":
				# One shared copy for the jacket AND the hat
				if _jacket_mat == null:
					_jacket_mat = mat.duplicate() as StandardMaterial3D
				mi.set_surface_override_material(i, _jacket_mat)
				_apply_jacket()
			elif mat.resource_name == face_material_name:
				_face_mat = mat.duplicate() as StandardMaterial3D
				mi.set_surface_override_material(i, _face_mat)


func _apply_jacket() -> void:
	if _jacket_mat:
		_jacket_mat.albedo_color = JACKET_COLORS[jacket_index % JACKET_COLORS.size()]

# ---------- Jacket requests (host is the referee) ----------

## A player asks the host for a colour. Runs on the host only.
@rpc("any_peer", "call_local", "reliable")
func request_jacket(index: int) -> void:
	if not multiplayer.is_server():
		return
	for hiker in get_tree().get_nodes_in_group("hikers"):
		if hiker != self and hiker.jacket_index == index:
			return   # taken: say no
	# Update the host's copy straight away, so a second request
	# for the same colour a moment later is refused
	jacket_index = index
	_confirm_jacket.rpc(index)


## The host says yes. The hiker's owner sets it, which syncs to everyone.
@rpc("any_peer", "call_local", "reliable")
func _confirm_jacket(index: int) -> void:
	if is_multiplayer_authority():
		jacket_index = index

# ---------- Lying on slopes ----------

## Tilt a lying body to match the slope under it, so it doesn't sink into the hill.
func _fit_body_to_ground() -> void:
	if _body_visual == null:
		return
	var target := Quaternion.IDENTITY
	var lift := 0.0
	if state == "unconscious" or state == "eliminated":
		# Look straight down under the middle of the body (terrain only, layer 1)
		var middle := (global_position + drag_point.global_position) / 2.0
		var query := PhysicsRayQueryParameters3D.create(
				middle + Vector3.UP * 1.5, middle + Vector3.DOWN * 3.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit:
			# The slope's "up" direction, as seen from inside Model
			var ground_up: Vector3 = model.global_basis.inverse() * hit.normal
			target = Quaternion(Vector3.UP, ground_up.normalized())
		lift = 0.08
	# Ease into the tilt so it doesn't snap
	var t := clampf(10.0 * get_process_delta_time(), 0.0, 1.0)
	_body_visual.quaternion = _body_visual.quaternion.slerp(target, t)
	_body_visual.position.y = lerpf(_body_visual.position.y, lift, t)
