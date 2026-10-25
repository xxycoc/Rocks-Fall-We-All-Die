extends CanvasLayer
## Lobby UI (P1). Lives inside main.tscn as a child called "Lobby".
## It only reports button presses; main.gd does the networking.

signal host_requested
signal join_requested(ip: String)
signal start_requested   # NEW: host clicked "Start climb"

const MAX_HIKERS := 4
const JACKET_COLORS: Array = preload("res://scripts/hiker.gd").JACKET_COLORS
var _color_buttons: Array[Button] = []
var _color_styles: Array[StyleBoxFlat] = []

@onready var ip_edit: LineEdit = %IPEdit
@onready var status_label: Label = %Status
@onready var menu: Control = $Menu 

@export var music_volume_db := -6.0

func _ready() -> void:
	%HostButton.pressed.connect(func(): host_requested.emit())
	%JoinButton.pressed.connect(_on_join_pressed)
	ip_edit.text_submitted.connect(func(_t): _on_join_pressed())
	status_label.text = ""
	# NEW
	%StartButton.pressed.connect(func(): start_requested.emit())
	GameManager.round_started.connect(func(): %WaitingCard.hide())
	_build_color_picker()

	# Music: gameplay track during rounds, menu track the rest of the time
	GameManager.round_started.connect(func(): _switch_music(%GameMusic))
	GameManager.game_over.connect(func(_winner): _switch_music(%MenuMusic))

func _on_join_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	join_requested.emit(ip)


func show_status(text: String) -> void:
	status_label.text = text


# ---------- NEW: waiting card ----------

## Called by main.gd after hosting or joining.
func show_waiting(is_host: bool) -> void:
	menu.hide()
	%WaitingCard.show()
	# Only the host sees the IP and the Start button
	%IPHeading.visible = is_host
	%IPList.visible = is_host
	%StartButton.visible = is_host
	# Only hikers pick a jacket (the host is the Mountain)
	%PickLabel.visible = not is_host
	%ColorPicker.visible = not is_host
	if is_host:
		%WaitTitle.text = "Waiting for hikers"
		%WaitHint.text = "Share your IP. Start when everyone's in."
		%IPList.text = "\n".join(_local_ips())
	else:
		%WaitTitle.text = "You're in!"
		%WaitHint.text = "Walk around while you wait. The host will start the climb."


func _process(_delta: float) -> void:
	# Round timer: shown while a round is running, for everyone
	%TimerLabel.visible = GameManager.round_running
	if %TimerLabel.visible:
		var secs := int(ceil(GameManager.time_left))
		%TimerLabel.text = "%d:%02d" % [floori(secs / 60.0), secs % 60]
		# Turn red in the last 30 seconds
		%TimerLabel.modulate = Color(1, 0.45, 0.4) if secs <= 30 else Color.WHITE

	if not %WaitingCard.visible:
		return
	var count: int = GameManager.hiker_states.size()
	%PlayerCount.text = "Hikers joined:  %d / %d" % [count, MAX_HIKERS]
	%StartButton.disabled = count == 0   # can't start with nobody
	if %ColorPicker.visible:
		_update_color_picker()


## This computer's addresses that friends can join with.
func _local_ips() -> Array[String]:
	var lan: Array[String] = []
	var vpn: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") != 3 or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue   # skip IPv6, this-PC-only and broken addresses
		if ip.begins_with("100."):
			vpn.append(ip + "  (Tailscale)")
		elif ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			lan.append(ip)
	var all: Array[String] = lan + vpn
	if all.is_empty():
		all.append("Not found. Run ipconfig.")
	return all

# ---------- Jacket picker ----------

func _build_color_picker() -> void:
	for i in JACKET_COLORS.size():
		var color: Color = JACKET_COLORS[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(56, 56)
		button.focus_mode = Control.FOCUS_NONE
		var normal := _circle(color)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", _circle(color.lightened(0.25)))
		button.add_theme_stylebox_override("pressed", _circle(color.darkened(0.15)))
		# Taken colours keep their colour; an X is drawn on top instead
		button.add_theme_stylebox_override("disabled", _circle(color))
		button.add_theme_font_size_override("font_size", 30)
		button.add_theme_color_override("font_disabled_color", Color.BLACK)
		button.pressed.connect(_pick_color.bind(i))
		%ColorPicker.add_child(button)
		_color_buttons.append(button)
		_color_styles.append(normal)


func _circle(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(28)
	style.border_color = Color.BLACK
	return style


## This player's own hiker (named after their peer ID).
func _my_hiker() -> Node:
	return get_node_or_null("../Players/%d" % multiplayer.get_unique_id())


func _pick_color(index: int) -> void:
	var me := _my_hiker()
	if me:
		me.request_jacket.rpc_id(1, index)   # ask the host; it refuses if taken


func _update_color_picker() -> void:
	var me = _my_hiker()
	var taken := {}
	for hiker in get_tree().get_nodes_in_group("hikers"):
		if hiker != me:
			taken[hiker.jacket_index] = true
	for i in _color_buttons.size():
		_color_buttons[i].disabled = taken.has(i)
		_color_buttons[i].text = "X" if taken.has(i) else ""
		# White ring around your own colour
		_color_styles[i].set_border_width_all(4 if me and me.jacket_index == i else 0)


# ---------- Music ----------

## Fade out whatever's playing and fade in the new track from the start.
func _switch_music(to: AudioStreamPlayer) -> void:
	var from: AudioStreamPlayer = %MenuMusic if to == %GameMusic else %GameMusic
	if from.playing:
		var fade_out := create_tween()
		fade_out.tween_property(from, "volume_db", -40.0, 1.0)
		fade_out.tween_callback(from.stop)
	to.volume_db = -40.0
	to.play()
	create_tween().tween_property(to, "volume_db", music_volume_db, 1.0)
