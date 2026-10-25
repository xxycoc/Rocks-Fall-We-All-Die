class_name MountainController
extends Node
## Mountain energy and abilities. Runs on the host only.
## Keys 1/2/3 select an ability, left-click uses it on the terrain, right-click cancels.
## Obstacles are spawned through main.tscn's ObstacleSpawner so every peer gets them.

signal energy_changed(energy: float)
signal ability_selected(index: int)  # -1 = none
signal cooldown_changed(time_left: float)
signal ability_used(index: int, point: Vector3)
signal ability_failed(reason: String)  # shown briefly on the HUD

const MAX_ENERGY := 30.0
const START_ENERGY := 10.0
const REGEN_PER_SEC := 1.0
const COOLDOWN := 3.0
const TERRAIN_MASK := 1
const GHOST_OK := Color(0.2, 1.0, 0.3, 0.5)
const GHOST_NO := Color(1.0, 0.2, 0.2, 0.5)
const ABILITIES: Array[Dictionary] = [
	{"name": "Mudslick", "cost": 2, "color": Color(0.45, 0.3, 0.15)},
	{"name": "Boulder", "cost": 5, "color": Color(0.6, 0.6, 0.65)},
	{"name": "Landslide", "cost": 20, "color": Color(0.9, 0.3, 0.1)},
]

@export var camera: Camera3D

var energy := START_ENERGY
var cooldown_left := 0.0
var selected := -1
var _ghosts: Array[MeshInstance3D] = []
var _was_active := false
var _last_time_left := 0.0


func _ready() -> void:
	# No peer or the offline peer counts as host, so the sandbox works.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		set_process(false)
		set_process_unhandled_input(false)
		return
	if camera == null:
		camera = get_viewport().get_camera_3d()
	_build_ghosts()


func _process(delta: float) -> void:
	var active := round_active()
	# GameManager has no round-start signal. A restart mid-round (Enter) keeps
	# round_running true but refills the timer, so a jump in time_left is a new round too.
	var restarted := active and GameManager.time_left > _last_time_left + 1.0
	_last_time_left = GameManager.time_left
	if active != _was_active or restarted:
		_was_active = active
		# Every round starts from the same energy, however long the lobby took.
		energy = START_ENERGY
		cooldown_left = 0.0
		energy_changed.emit(energy)
		cooldown_changed.emit(cooldown_left)
	if not active:
		_update_ghost()
		return
	if energy < MAX_ENERGY:
		energy = minf(energy + REGEN_PER_SEC * delta, MAX_ENERGY)
		energy_changed.emit(energy)
	if cooldown_left > 0.0:
		cooldown_left = maxf(cooldown_left - delta, 0.0)
		cooldown_changed.emit(cooldown_left)
	_update_ghost()


func _unhandled_input(event: InputEvent) -> void:
	for i in ABILITIES.size():
		if event.is_action_pressed("ability_%d" % (i + 1)):
			select(i)
			return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			select(-1)
		elif mb.button_index == MOUSE_BUTTON_LEFT and selected >= 0:
			var hit := raycast_terrain(mb.position)
			if hit.is_empty():
				ability_failed.emit("Click on the mountain")
			else:
				use_ability(selected, hit.position, hit.normal)
			get_viewport().set_input_as_handled()


func select(index: int) -> void:
	selected = index
	ability_selected.emit(selected)


## Abilities only work while a round runs. The offline sandbox has no rounds, so it is always active.
func round_active() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer or GameManager.round_running


func can_use(cost: int) -> bool:
	return round_active() and cooldown_left <= 0.0 and energy >= cost


func _why_not(cost: int) -> String:
	if not round_active():
		return "Waiting for the round"
	if cooldown_left > 0.0:
		return "Cooling down %.1fs" % cooldown_left
	return "Need %d energy" % cost


func spend(cost: int) -> bool:
	if not can_use(cost):
		return false
	energy -= cost
	cooldown_left = COOLDOWN
	energy_changed.emit(energy)
	cooldown_changed.emit(cooldown_left)
	return true


func use_ability(index: int, point: Vector3, normal := Vector3.UP) -> bool:
	var spawner := _spawner()
	if spawner == null:
		push_warning("No ObstacleSpawner in the current scene.")
		return false
	var ability: Dictionary = ABILITIES[index]
	var trail := Trail.find(get_tree())
	if index == 2 and trail == null:
		push_warning("Landslide needs a Trail in the level.")
		ability_failed.emit("No trail in this level")
		return false
	if not spend(ability.cost):
		ability_failed.emit(_why_not(ability.cost))
		return false
	var data := {"type": index, "pos": point, "normal": normal}
	if index == 2:
		data.offset = trail.offset_of(point)
		data.side = _landslide_side(trail, point, data.offset)
	spawner.spawn(data)
	Sound.play_ui("mountain_place")
	ability_used.emit(index, point)
	return true


## Returns the intersect_ray result dictionary, empty if no terrain was hit.
func raycast_terrain(screen_pos: Vector2) -> Dictionary:
	if camera == null:
		return {}
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to, TERRAIN_MASK)
	return camera.get_world_3d().direct_space_state.intersect_ray(query)


## Which 2/3 of the trail a landslide covers: the half that was clicked.
func _landslide_side(trail: Trail, point: Vector3, offset: float) -> float:
	return -1.0 if trail.t_of(point, offset) < 0.5 else 1.0


func _spawner() -> MultiplayerSpawner:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("ObstacleSpawner") if scene else null


# ---------- Ghost previews (host only, never replicated) ----------

## Sizes match mudslick.tscn, boulder.tscn and landslide.tscn.
func _build_ghosts() -> void:
	var mud := PlaneMesh.new()
	mud.size = Vector2(6, 6)
	var boulder := SphereMesh.new()
	boulder.radius = 1.2
	boulder.height = 2.4
	var landslide := BoxMesh.new()
	landslide.size = Vector3(1, 3, 6)
	for mesh: Mesh in [mud, boulder, landslide]:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var ghost := MeshInstance3D.new()
		ghost.mesh = mesh
		ghost.material_override = mat
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.hide()
		add_child(ghost)
		_ghosts.append(ghost)


func _update_ghost() -> void:
	for ghost in _ghosts:
		ghost.hide()
	if selected < 0 or camera == null:
		return
	var hit := raycast_terrain(get_viewport().get_mouse_position())
	if hit.is_empty():
		return
	var ghost := _ghosts[selected]
	var mat := ghost.material_override as StandardMaterial3D
	mat.albedo_color = GHOST_OK if can_use(ABILITIES[selected].cost) else GHOST_NO
	match selected:
		0:
			ghost.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, hit.normal)), hit.position + hit.normal * 0.06)
		1:
			var pos: Vector3 = hit.position
			var trail := Trail.find(get_tree())
			if trail:  # boulder.gd snaps onto the trail
				var offset := trail.offset_of(pos)
				pos = trail.across(offset, trail.t_of(pos, offset), 1.2)
			ghost.global_position = pos + Vector3.UP * (3.0 + 1.2)  # boulder.gd DROP_HEIGHT + RADIUS
		2:
			var trail := Trail.find(get_tree())
			if trail == null:
				return
			var offset := trail.offset_of(hit.position)
			var band := trail.band(offset, _landslide_side(trail, hit.position, offset), 2.0 / 3.0)
			ghost.global_transform = band.transform.translated(Vector3.UP * 1.5).scaled_local(Vector3(band.width, 1, 1))
	ghost.show()
