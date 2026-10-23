extends CanvasLayer
## Lobby UI (P1). Lives inside main.tscn as a child called "Lobby".
## It only reports button presses; main.gd does the networking.

signal host_requested
signal join_requested(ip: String)

@onready var ip_edit: LineEdit = %IPEdit
@onready var status_label: Label = %Status


func _ready() -> void:
	%HostButton.pressed.connect(func(): host_requested.emit())
	%JoinButton.pressed.connect(_on_join_pressed)
	ip_edit.text_submitted.connect(func(_t): _on_join_pressed())
	status_label.text = ""


func _on_join_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	join_requested.emit(ip)


func show_status(text: String) -> void:
	status_label.text = text
