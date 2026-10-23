extends RigidBody3D
## Boulder (P2). Physics runs on the host; clients follow the synced position.

const DAMAGE := 20
const DROP_HEIGHT := 3.0
const LIFETIME := 10.0
const KILL_Y := -30.0

var _hit := {}


func setup(data: Dictionary) -> void:
	position = data.pos + Vector3.UP * DROP_HEIGHT


func _ready() -> void:
	if not is_multiplayer_authority():
		freeze = true
		$HitArea.monitoring = false
		return
	$HitArea.body_entered.connect(_on_hit)
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)


func _physics_process(_delta: float) -> void:
	if is_multiplayer_authority() and global_position.y < KILL_Y:
		queue_free()


func _on_hit(body: Node3D) -> void:
	# Once per hiker, or a rolling boulder would hit someone every frame.
	if body.is_in_group("hikers") and not _hit.has(body):
		_hit[body] = true
		body.take_damage.rpc(DAMAGE)
