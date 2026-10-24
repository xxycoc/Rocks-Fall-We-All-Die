extends Node3D
## Landslide (P2). A 2 s warning, then a wave of dirt sweeps downhill over the
## chosen 2/3 of the lane. Every peer moves the wave the same way so it looks the
## same everywhere; only the host deals damage.

const DAMAGE := 40
const WARNING_TIME := 2.0
const BASE_SPEED := 6.0
const SPEED_PER_METRE := 0.12  # further from the peak = faster
const DOWNHILL := Vector3.BACK  # the greybox climbs toward -Z
const BLOCKS_PER_METRE := 1.5
const DROP_HEIGHT := Vector2(4.0, 9.0)  # blocks start this far above the wave and fall in
const GRAVITY := 20.0
const MAX_TIME := 15.0
const TERRAIN_MASK := 1

var _width := 10.0
var _speed := BASE_SPEED
var _running := false
var _elapsed := 0.0
var _hit := {}
var _fall := {}  # block -> [rest_y, fall_speed]

@onready var _warning: MeshInstance3D = $Warning
@onready var _wave: Area3D = $Wave
@onready var _block_template: MeshInstance3D = $Wave/BlockTemplate
@onready var _siren: AudioStreamPlayer = $Siren
@onready var _rumble: AudioStreamPlayer3D = $Wave/Rumble


func setup(data: Dictionary) -> void:
	_width = data.x_max - data.x_min
	position = Vector3((data.x_min + data.x_max) / 2.0, data.pos.y, data.pos.z)


func _ready() -> void:
	var peak := get_tree().current_scene.find_child("Peak", true, false) as Node3D
	if peak:
		_speed = BASE_SPEED + peak.global_position.distance_to(global_position) * SPEED_PER_METRE

	_warning.scale.x = _width
	var shape := ($Wave/Shape.shape as BoxShape3D).duplicate() as BoxShape3D
	shape.size.x = _width
	$Wave/Shape.shape = shape
	_wave.hide()
	_wave.monitoring = false
	if _siren.stream:
		_siren.play()

	await get_tree().create_timer(WARNING_TIME).timeout
	_warning.hide()
	_spawn_blocks()
	_wave.show()
	if _rumble.stream:
		_rumble.play()
	_running = true
	if is_multiplayer_authority():
		_wave.monitoring = true
		_wave.body_entered.connect(_on_hit)


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	var pos := _wave.global_position + DOWNHILL * _speed * delta
	# Follow the ground; past the bottom of the mountain there is none.
	var from := pos + Vector3.UP * 20.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0, TERRAIN_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or _elapsed > MAX_TIME:
		_finish()
		return
	pos.y = hit.position.y
	_wave.global_position = pos
	for block: MeshInstance3D in _fall:
		block.rotate_x(_speed * delta * 0.5)
		var f: Array = _fall[block]
		if block.position.y > f[0]:
			f[1] += GRAVITY * delta
			block.position.y = maxf(block.position.y - f[1] * delta, f[0])


func _spawn_blocks() -> void:
	for i in maxi(int(_width * BLOCKS_PER_METRE), 6):
		var block := _block_template.duplicate() as MeshInstance3D
		var rest_y := randf_range(0.5, 2.5)
		block.position = Vector3(randf_range(-_width / 2.0, _width / 2.0), rest_y + randf_range(DROP_HEIGHT.x, DROP_HEIGHT.y), randf_range(-2.0, 2.0))
		_fall[block] = [rest_y, 0.0]
		var size := randf_range(0.8, 1.6)
		block.scale = Vector3.ONE * size
		block.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
		block.show()
		_wave.add_child(block)


func _finish() -> void:
	_running = false
	_wave.hide()
	_wave.set_deferred("monitoring", false)
	if is_multiplayer_authority():
		get_tree().create_timer(1.0).timeout.connect(queue_free)


func _on_hit(body: Node3D) -> void:
	if body.is_in_group("hikers") and not _hit.has(body):
		_hit[body] = true
		body.take_damage.rpc(DAMAGE)
