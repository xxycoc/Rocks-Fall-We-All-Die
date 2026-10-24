extends CanvasLayer
## Lobby UI (P1). Lives inside main.tscn as a child called "Lobby".
## It only reports button presses; main.gd does the networking.

signal host_requested
signal join_requested(ip: String)
signal start_requested   # NEW: host clicked "Start climb"

const MAX_HIKERS := 4

@onready var ip_edit: LineEdit = %IPEdit
@onready var status_label: Label = %Status
@onready var menu: Control = $Menu 


func _ready() -> void:
	%HostButton.pressed.connect(func(): host_requested.emit())
	%JoinButton.pressed.connect(_on_join_pressed)
	ip_edit.text_submitted.connect(func(_t): _on_join_pressed())
	status_label.text = ""
	# NEW
	%StartButton.pressed.connect(func(): start_requested.emit())
	GameManager.round_started.connect(func(): %WaitingCard.hide())


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
	if is_host:
		%WaitTitle.text = "Waiting for hikers"
		%WaitHint.text = "Share your IP. Start when everyone's in."
		%IPList.text = "\n".join(_local_ips())
	else:
		%WaitTitle.text = "You're in!"
		%WaitHint.text = "Walk around while you wait. The host will start the climb."


func _process(_delta: float) -> void:
	if not %WaitingCard.visible:
		return
	var count: int = GameManager.hiker_states.size()
	%PlayerCount.text = "Hikers joined:  %d / %d" % [count, MAX_HIKERS]
	%StartButton.disabled = count == 0   # can't start with nobody


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
