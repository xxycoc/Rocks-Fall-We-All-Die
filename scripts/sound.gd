extends Node
## Sound effects (P1). Autoload named "Sound".
## Sound files live in res://audio/ (e.g. hiker_dash.ogg).
## .ogg, .wav and .mp3 all work. Missing files are skipped silently.

const FOLDER := "res://audio/"
const EXTENSIONS := ["ogg", "wav", "mp3"]

var _cache := {}


func _ready() -> void:
	# Every button in the game gets hover and click sounds automatically
	get_tree().node_added.connect(_on_node_added)


## A flat sound everyone hears the same (menus, UI).
func play_ui(sound: String, volume_db: float = 0.0) -> void:
	var stream := _load_sound(sound)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = "SFX"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


## A sound coming from a spot in the world: louder when you're close.
func play_at(sound: String, position: Vector3, volume_db: float = 0.0) -> void:
	var stream := _load_sound(sound)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = 15.0       # how far it stays at full volume
	player.max_distance = 250.0   # far enough for the Mountain's camera to hear
	player.bus = "SFX"
	add_child(player)
	player.global_position = position
	player.play()
	player.finished.connect(player.queue_free)


func _load_sound(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	var stream: AudioStream = null
	for ext in EXTENSIONS:
		var path := "%s%s.%s" % [FOLDER, sound, ext]
		if ResourceLoader.exists(path):
			stream = load(path)
			break
	_cache[sound] = stream
	return stream


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.mouse_entered.connect(_on_button_hover.bind(node))
		node.pressed.connect(play_ui.bind("ui_click", -4.0))


func _on_button_hover(button: BaseButton) -> void:
	if not button.disabled:
		play_ui("ui_hover", -8.0)
