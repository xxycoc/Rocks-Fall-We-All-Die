extends Node3D
## Landslide (P2). A 2 s warning, then a wave of dirt sweeps down the Trail over
## 2/3 of its width on the chosen side. The band is re-measured as the wave moves,
## so it narrows and widens with the trail. Every peer moves the wave the same
## way so it looks the same everywhere; only the host deals damage.

const DAMAGE := 40
const WARNING_TIME := 2.0
const BASE_SPEED := 6.0
const SPEED_PER_METRE := 0.12  # further from the peak = faster
const MAX_SPEED := 20.0
const BAND := 2.0 / 3.0
const BLOCKS_PER_METRE := 1.5
const DROP_HEIGHT := Vector2(4.0, 9.0)  # blocks start this far above the wave and fall in
const GRAVITY := 20.0
const MAX_TIME := 15.0

var _offset := 0.0  # distance along the trail
var _side := 1.0  # -1 = left 2/3, 1 = right 2/3 (facing up the trail)
var _trail: Trail
var _speed := BASE_SPEED
var _running := false
var _elapsed := 0.0
var _hit := {}
var _fall := {}  # block -> [rest_y, fall_speed, place across the band from -0.5 to 0.5]

@onready var _warning: MeshInstance3D = $Warning
@onready var _wave: Area3D = $Wave
@onready var _shape: CollisionShape3D = $Wave/Shape
@onready var _block_template: MeshInstance3D = $Wave/BlockTemplate
@onready var _siren: AudioStreamPlayer3D = $Warning/Siren
@onready var _rumble: AudioStreamPlayer3D = $Wave/Rumble


func setup(data: Dictionary) -> void:
	position = data.pos
	_offset = data.offset
	_side = data.side


func _ready() -> void:
	_trail = Trail.find(get_tree())
	if _trail == null:
		push_warning("Landslide needs a Trail in the level.")
		if is_multiplayer_authority():
			queue_free.call_deferred()
		return
	var peak := _trail.point_at(_trail.length())
	_speed = minf(BASE_SPEED + peak.distance_to(_trail.point_at(_offset)) * SPEED_PER_METRE, MAX_SPEED)

	_shape.shape = _shape.shape.duplicate()
	var width := _place(_warning)
	_warning.position.y += 1.5
	_warning.scale.x = width
	_wave.hide()
	_wave.monitoring = false
	Sfx.play(_siren, "landslide_siren")

	await get_tree().create_timer(WARNING_TIME).timeout
	_warning.hide()
	_spawn_blocks(_place(_wave))
	_wave.show()
	Sfx.play(_rumble, "landslide_rumble", true)
	_running = true
	if is_multiplayer_authority():
		_wave.monitoring = true
		_wave.body_entered.connect(_on_hit)


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	_offset -= _speed * delta
	if _offset <= 0.0 or _elapsed > MAX_TIME:
		_finish()
		return
	var width := _place(_wave)
	(_shape.shape as BoxShape3D).size.x = width
	for block: MeshInstance3D in _fall:
		var f: Array = _fall[block]
		block.position.x = f[2] * width
		block.rotate_x(_speed * delta * 0.5)
		if block.position.y > f[0]:
			f[1] += GRAVITY * delta
			block.position.y = maxf(block.position.y - f[1] * delta, f[0])


## Puts `node` on the band at the current offset, facing down the trail.
## Returns the band width.
func _place(node: Node3D) -> float:
	var band := _trail.band(_offset, _side, BAND)
	node.global_transform = band.transform
	return band.width


func _spawn_blocks(width: float) -> void:
	for i in maxi(int(width * BLOCKS_PER_METRE), 6):
		var block := _block_template.duplicate() as MeshInstance3D
		var u := randf_range(-0.5, 0.5)
		var rest_y := randf_range(0.5, 2.5)
		block.position = Vector3(u * width, rest_y + randf_range(DROP_HEIGHT.x, DROP_HEIGHT.y), randf_range(-2.0, 2.0))
		block.scale = Vector3.ONE * randf_range(0.8, 1.6)
		block.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
		block.show()
		_wave.add_child(block)
		_fall[block] = [rest_y, 0.0, u]


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
