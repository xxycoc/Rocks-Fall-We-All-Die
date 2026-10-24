extends RigidBody3D
## Boulder (P2). Runs on the host; clients follow the synced position.
## With a Trail in the level it drops onto the trail and rolls down along it,
## keeping its place across the trail, so it can't roll off where the trail turns.
## Without a Trail it falls back to plain physics.

const DAMAGE := 20
const DROP_HEIGHT := 3.0
const LIFETIME := 10.0
const KILL_Y := -30.0
const RADIUS := 1.2
const GRAVITY := 20.0
const ROLL_ACCEL := 6.0
const MAX_SPEED := 14.0

var _hit := {}
var _trail: Trail
var _offset := 0.0  # distance along the trail
var _t := 0.5  # place across the trail, 0 = left edge, 1 = right edge
var _speed := 0.0
var _fall_speed := 0.0
var _landed := false


func setup(data: Dictionary) -> void:
	position = data.pos + Vector3.UP * DROP_HEIGHT


func _ready() -> void:
	Sfx.play($Roll, "boulder_roll", true)
	if not is_multiplayer_authority():
		freeze = true
		$HitArea.monitoring = false
		return
	$HitArea.body_entered.connect(_on_hit)
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)
	_trail = Trail.find(get_tree())
	if _trail:
		freeze_mode = FREEZE_MODE_KINEMATIC
		freeze = true
		var ground := global_position - Vector3.UP * DROP_HEIGHT
		_offset = _trail.offset_of(ground)
		_t = _trail.t_of(ground, _offset)
		var start := _trail.across(_offset, _t, RADIUS)
		global_position = start + Vector3.UP * (DROP_HEIGHT + RADIUS)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if global_position.y < KILL_Y:
		queue_free()
		return
	if _trail:
		_roll_along_trail(delta)


func _roll_along_trail(delta: float) -> void:
	var target := _trail.across(_offset, _t, RADIUS) + Vector3.UP * RADIUS
	if not _landed:
		_fall_speed += GRAVITY * delta
		global_position.y -= _fall_speed * delta
		if global_position.y <= target.y:
			global_position.y = target.y
			_landed = true
		return
	if _offset <= 0.0:
		queue_free()  # reached the bottom of the trail
		return
	_speed = minf(_speed + ROLL_ACCEL * delta, MAX_SPEED)
	_offset -= _speed * delta
	target = _trail.across(_offset, _t, RADIUS) + Vector3.UP * RADIUS
	global_position = target
	rotate(_trail.side_at(_offset), _speed / RADIUS * delta)


func _on_hit(body: Node3D) -> void:
	# Once per hiker, or a rolling boulder would hit someone every frame.
	if body.is_in_group("hikers") and not _hit.has(body):
		_hit[body] = true
		body.take_damage.rpc(DAMAGE)
