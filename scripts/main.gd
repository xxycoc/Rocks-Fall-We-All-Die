extends Node3D
## main.tscn root (P1). Handles host/join, spawns one hiker per client,
## and puts P2's Mountain on the host only.

const PORT := 7777
const MAX_HIKERS := 4
const HIKER_SCENE := preload("res://scenes/hiker.tscn")
const MOUNTAIN_SCENE := preload("res://scenes/mountain.tscn")

@onready var players: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints
@onready var lobby = $Lobby
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner

@onready var kill_zone: Area3D = $KillZone
@onready var extraction_zone: Area3D = $ExtractionZone

@onready var end_screen: CanvasLayer = $EndScreen
@onready var obstacles: Node3D = $Obstacles

var _is_host := false
var _auto_join := false
var _next_dummy := 1
var _spawn_index := 0


func _ready() -> void:
	player_spawner.spawn_function = _spawn_hiker
	lobby.host_requested.connect(host_game)
	lobby.join_requested.connect(join_game)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Test shortcut: Debug > Customize Run Instances, give the first
	# instance the argument --host and the others --join.
	if not GameManager.auto_connect_used:
		GameManager.auto_connect_used = true
		var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
		if "--host" in args:
			host_game()
		elif "--join" in args:
			_auto_join = true
			join_game("127.0.0.1")
	kill_zone.body_entered.connect(_on_kill_zone_body_entered)
	extraction_zone.body_entered.connect(_on_extraction_zone_body_entered)

	GameManager.game_over.connect(_on_game_over)
	%PlayAgainButton.pressed.connect(_restart_round)
	%LeaveButton.pressed.connect(leave_to_lobby)
	if GameManager.lobby_message != "":
		lobby.show_status(GameManager.lobby_message)
		GameManager.lobby_message = ""
		
# ---------- Hosting and joining ----------

func host_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_HIKERS)
	if err != OK:
		lobby.show_status("Couldn't host (error %d). Is another host already running?" % err)
		return
	multiplayer.multiplayer_peer = peer
	_is_host = true
	multiplayer.peer_connected.connect(_add_hiker)
	multiplayer.peer_disconnected.connect(_remove_hiker)

	# CONTRACT.md: the Mountain exists on the host only, so it is added
	# locally and never replicated.
	add_child(MOUNTAIN_SCENE.instantiate())

	lobby.hide()
	get_window().title = "HOST (Mountain)"


func join_game(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		lobby.show_status("Couldn't start connecting (error %d)." % err)
		return
	multiplayer.multiplayer_peer = peer
	lobby.show_status("Connecting to %s..." % ip)


func _on_connected() -> void:
	lobby.hide()
	get_window().title = "Hiker %d" % multiplayer.get_unique_id()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	if _auto_join:
		# The host instance may not be listening yet; keep retrying.
		await get_tree().create_timer(0.5).timeout
		join_game("127.0.0.1")
	else:
		lobby.show_status("Couldn't connect. Check the IP and that the host is running.")

func _on_server_disconnected() -> void:
	leave_to_lobby("The host left the game.")

# ---------- Spawning (host only) ----------

func _add_hiker(id: int) -> void:
	# Runs on the host. The spawner calls _spawn_hiker on EVERY machine
	# with the same data, so everyone starts the hiker in the same spot.
	player_spawner.spawn({"id": id, "pos": _next_spawn_position()})
	GameManager.register_hiker(id)


func _spawn_hiker(data: Dictionary) -> Node:
	var hiker := HIKER_SCENE.instantiate()
	hiker.name = str(data.id)   # CONTRACT.md: named after the owner's peer ID
	hiker.position = data.pos
	return hiker


func _remove_hiker(id: int) -> void:
	var hiker := players.get_node_or_null(str(id))
	if hiker:
		hiker.queue_free()
	GameManager.unregister_hiker(id)


func _next_spawn_position() -> Vector3:
	var points := spawn_points.get_children()
	if points.is_empty():
		return Vector3(0, 2, 0)
	var point: Node3D = points[_spawn_index % points.size()]
	_spawn_index += 1
	return point.global_position


# ---------- Host debug keys ----------

func _unhandled_input(event: InputEvent) -> void:
	if not _is_host:
		return
	if event.is_action_pressed("debug_spawn_dummy"):
		# Dummies get negative IDs (-1, -2, ...). hiker.gd gives them to the
		# host, so the Mountain can damage them with no extra players.
		_add_hiker(-_next_dummy)
		_next_dummy += 1
	elif event.is_action_pressed("start_round"):
		_restart_round()
	elif event.is_action_pressed("debug_damage"):
		# F10 hits every hiker for 50. Shift+F10 hits only dummies.
		var dummies_only: bool = event is InputEventKey and event.shift_pressed
		for hiker in get_tree().get_nodes_in_group("hikers"):
			if dummies_only and not hiker.is_dummy:
				continue
			hiker.take_damage.rpc(50)

func _on_kill_zone_body_entered(body: Node3D) -> void:
	# Each machine detects this, but only the hiker's owner acts on it
	if body.is_in_group("hikers") and body.is_multiplayer_authority():
		body.eliminate()

func _on_extraction_zone_body_entered(body: Node3D) -> void:
	if body.is_in_group("hikers") and body.is_multiplayer_authority():
		body.extract()

func _on_game_over(winner: String) -> void:
	%ResultTitle.text = "HIKERS ESCAPE!" if winner == "hikers" else "THE MOUNTAIN WINS"
	%ResultDetail.text = "Escaped: %d   Eliminated: %d" % [
		GameManager.count_state("extracted"), GameManager.count_state("eliminated")]
	end_screen.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%PlayAgainButton.visible = multiplayer.is_server()
	if not multiplayer.is_server():
		%ResultDetail.text += "\nWaiting for the host to play again..."
# ---------- New round ----------

## Host only: reset every hiker, clear obstacles, start a fresh round.
func _restart_round() -> void:
	if not multiplayer.is_server():
		return
	var points := spawn_points.get_children()
	var i := 0
	for hiker in players.get_children():
		var pos := Vector3(0, 2, 0)
		if not points.is_empty():
			pos = points[i % points.size()].global_position
		hiker.reset_for_round.rpc(pos)
		i += 1
	for obstacle in obstacles.get_children():
		obstacle.queue_free()
	_hide_end_screen.rpc()
	GameManager.start_round()

# ---------- Leaving ----------

## Disconnect and reload the scene, which brings back a fresh lobby.
func leave_to_lobby(message: String = "") -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	GameManager.reset()
	GameManager.lobby_message = message
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()

@rpc("authority", "call_local", "reliable")
func _hide_end_screen() -> void:
	end_screen.hide()
