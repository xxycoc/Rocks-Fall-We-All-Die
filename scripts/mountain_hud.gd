class_name MountainHUD
extends CanvasLayer
## Energy bar (with a mark at the Landslide cost), the three ability slots and
## a live list of hikers. Ability icons load from res://art/icons/<ability>.png
## (mudslick.png, boulder.png, landslide.png) when the artist adds them.

const ICON_PATH := "res://art/icons/%s.png"
const STATE_COLORS := {
	"alive": Color.WHITE,
	"unconscious": Color(1.0, 0.6, 0.2),
	"eliminated": Color(0.5, 0.5, 0.5),
	"extracted": Color(0.4, 1.0, 0.5),
}
const LIST_REFRESH := 0.25

@export var controller: MountainController

var _slots: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _style_normal := StyleBoxFlat.new()
var _style_selected: StyleBoxFlat
var _hiker_list: VBoxContainer
var _message: Label
var _message_tween: Tween
var _list_timer := 0.0

@onready var _bar: ProgressBar = %EnergyBar
@onready var _mark: ColorRect = %Mark
@onready var _energy_label: Label = %EnergyLabel
@onready var _slots_box: HBoxContainer = %Slots


func _ready() -> void:
	_bar.max_value = MountainController.MAX_ENERGY
	var landslide_cost: float = MountainController.ABILITIES[2].cost
	_mark.anchor_left = landslide_cost / MountainController.MAX_ENERGY
	_mark.anchor_right = _mark.anchor_left

	_style_normal.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	_style_normal.set_content_margin_all(12)   # a bit more room so text clears the rounded corners
	_style_normal.set_corner_radius_all(20)
	_style_selected = _style_normal.duplicate()
	_style_selected.border_color = Color(1.0, 0.85, 0.2)
	_style_selected.set_border_width_all(3)

	for i in MountainController.ABILITIES.size():
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(150, 70)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := HBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(box)
		var icon_path := ICON_PATH % String(MountainController.ABILITIES[i].name).to_lower()
		if ResourceLoader.exists(icon_path):
			var icon := TextureRect.new()
			icon.texture = load(icon_path)
			icon.custom_minimum_size = Vector2(48, 48)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			box.add_child(icon)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(label)
		_slots_box.add_child(slot)
		_slots.append(slot)
		_slot_labels.append(label)

	if controller:
		controller.energy_changed.connect(_refresh.unbind(1))
		controller.cooldown_changed.connect(_refresh.unbind(1))
		controller.ability_selected.connect(_refresh.unbind(1))
		controller.ability_failed.connect(_flash)
	_refresh()
	_build_hiker_list()
	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.modulate.a = 0.0
	# Dark outlines keep the text readable over light terrain.
	for label: Label in [_message, _energy_label]:
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	$Root.add_child(_message)
	$Root.move_child(_message, 0)

	# Rounded energy bar
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	bar_bg.set_corner_radius_all(20)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.88, 0.48, 0.31)
	bar_fill.set_corner_radius_all(20)
	_bar.add_theme_stylebox_override("background", bar_bg)
	_bar.add_theme_stylebox_override("fill", bar_fill)

## Says briefly why a click did nothing.
func _flash(text: String) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(0.8)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.4)


func _process(delta: float) -> void:
	_list_timer -= delta
	if _list_timer <= 0.0:
		_list_timer = LIST_REFRESH
		_refresh_hiker_list()


func _build_hiker_list() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_normal)
	panel.position = Vector2(16, 16)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hiker_list = VBoxContainer.new()
	_hiker_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_hiker_list)
	add_child(panel)


## One row per hiker: name, HP bar and state. hp and state are synced by P1's hiker.
func _refresh_hiker_list() -> void:
	var hikers := get_tree().get_nodes_in_group("hikers")
	hikers.sort_custom(func(a, b): return a.name.to_int() > b.name.to_int())  # players first, then dummies
	while _hiker_list.get_child_count() < hikers.size() + 1:
		var row := Label.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hiker_list.add_child(row)
	while _hiker_list.get_child_count() > hikers.size() + 1:
		var last := _hiker_list.get_child(-1)
		_hiker_list.remove_child(last)
		last.queue_free()
	var title: Label = _hiker_list.get_child(0)
	title.text = "Hikers" if hikers.size() > 0 else "No hikers yet"
	for i in hikers.size():
		var hiker: Node = hikers[i]
		var row: Label = _hiker_list.get_child(i + 1)
		var id := hiker.name.to_int()
		var who := ("Dummy %d" % -id) if id < 0 else ("Hiker %d" % (i + 1))
		var hp: int = hiker.hp
		var bar := "■".repeat(ceili(hp / 10.0)) + "□".repeat(10 - ceili(hp / 10.0))
		row.text = "%s  %s %3d  %s" % [who, bar, hp, hiker.state]
		row.add_theme_color_override("font_color", STATE_COLORS.get(hiker.state, Color.WHITE))


func _refresh() -> void:
	if controller == null:
		return
	_bar.value = controller.energy
	_energy_label.text = "Energy %d / %d" % [floori(controller.energy), int(MountainController.MAX_ENERGY)]
	if not controller.round_active():
		_energy_label.text = "Waiting for the round (Enter to start)"
	for i in _slots.size():
		var ability: Dictionary = MountainController.ABILITIES[i]
		var text := "[%d] %s\nCost %d" % [i + 1, ability.name, ability.cost]
		if controller.cooldown_left > 0.0:
			text += "  (%.1fs)" % controller.cooldown_left
		_slot_labels[i].text = text
		var usable := controller.can_use(ability.cost)
		_slots[i].modulate = Color.WHITE if usable else Color(0.5, 0.5, 0.5, 0.7)
		_slots[i].add_theme_stylebox_override("panel", _style_selected if i == controller.selected else _style_normal)
