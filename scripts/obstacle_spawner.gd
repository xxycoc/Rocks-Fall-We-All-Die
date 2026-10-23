extends MultiplayerSpawner
## Replicates the Mountain's obstacles (P2). Only the host calls spawn(data);
## every peer builds the obstacle from the same data, so it starts in the same place.
## data.type is the ability index in MountainController.ABILITIES.

const SCENES: Array[PackedScene] = [
	preload("res://scenes/mudslick.tscn"),
	preload("res://scenes/boulder.tscn"),
	preload("res://scenes/landslide.tscn"),
]


func _ready() -> void:
	spawn_function = _build


func _build(data: Dictionary) -> Node:
	var obstacle: Node3D = SCENES[data.type].instantiate()
	obstacle.setup(data)
	return obstacle
