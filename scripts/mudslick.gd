extends Area3D
## Mudslick (P2). Exists on every peer. Hiker movement runs on the hiker's owner
## (CONTRACT.md), so each peer only changes the hikers it owns.

const FRICTION := 0.05
const LIFETIME := 15.0

var _inside: Array[Node3D] = []


func setup(data: Dictionary) -> void:
	position = data.pos
	quaternion = Quaternion(Vector3.UP, data.normal)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if is_multiplayer_authority():
		get_tree().create_timer(LIFETIME).timeout.connect(queue_free)


func _exit_tree() -> void:
	# body_exited doesn't fire when the mud disappears under someone.
	for body in _inside:
		if is_instance_valid(body):
			body.friction_multiplier = 1.0


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("hikers") and body.is_multiplayer_authority():
		body.friction_multiplier = FRICTION
		_inside.append(body)


func _on_body_exited(body: Node3D) -> void:
	if body in _inside:
		body.friction_multiplier = 1.0
		_inside.erase(body)
