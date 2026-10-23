class_name MountainController
extends Node
## Mountain energy and abilities. Runs on the host only.
## Keys 1/2/3 select an ability, left-click uses it on the terrain, right-click deselects.

signal energy_changed(energy: float)
signal ability_selected(index: int)  # -1 = none
signal cooldown_changed(time_left: float)
signal ability_used(index: int, point: Vector3)

const MAX_ENERGY := 30.0
const START_ENERGY := 10.0
const REGEN_PER_SEC := 1.0
const COOLDOWN := 3.0
const TERRAIN_MASK := 1
const ABILITIES: Array[Dictionary] = [
	{"name": "Mudslick", "cost": 2, "color": Color(0.45, 0.3, 0.15)},
	{"name": "Boulder", "cost": 5, "color": Color(0.6, 0.6, 0.65)},
	{"name": "Landslide", "cost": 20, "color": Color(0.9, 0.3, 0.1)},
]

@export var camera: Camera3D

var energy := START_ENERGY
var cooldown_left := 0.0
var selected := -1


func _ready() -> void:
	# No peer or the offline peer counts as host, so the sandbox works.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		set_process(false)
		set_process_unhandled_input(false)
		return
	if camera == null:
		camera = get_viewport().get_camera_3d()


func _process(delta: float) -> void:
	if energy < MAX_ENERGY:
		energy = minf(energy + REGEN_PER_SEC * delta, MAX_ENERGY)
		energy_changed.emit(energy)
	if cooldown_left > 0.0:
		cooldown_left = maxf(cooldown_left - delta, 0.0)
		cooldown_changed.emit(cooldown_left)


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
			if not hit.is_empty():
				use_ability(selected, hit.position)
			get_viewport().set_input_as_handled()


func select(index: int) -> void:
	selected = index
	ability_selected.emit(selected)


func can_use(cost: int) -> bool:
	return cooldown_left <= 0.0 and energy >= cost


func spend(cost: int) -> bool:
	if not can_use(cost):
		return false
	energy -= cost
	cooldown_left = COOLDOWN
	energy_changed.emit(energy)
	cooldown_changed.emit(cooldown_left)
	return true


func use_ability(index: int, point: Vector3) -> bool:
	var ability: Dictionary = ABILITIES[index]
	if not spend(ability.cost):
		return false
	_spawn_debug_cube(point, ability.color)
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


# Placeholder until the real obstacles arrive on Saturday.
func _spawn_debug_cube(point: Vector3, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	var mesh := BoxMesh.new()
	mesh.material = mat
	var cube := MeshInstance3D.new()
	cube.mesh = mesh
	_spawn_parent().add_child(cube)
	cube.global_position = point


func _spawn_parent() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return get_tree().root
	var obstacles := scene.get_node_or_null("Obstacles")
	return obstacles if obstacles else scene
