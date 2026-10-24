class_name MountainHUD
extends CanvasLayer
## Energy bar (with a mark at the Landslide cost) and the three ability slots.

@export var controller: MountainController

var _slots: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _style_normal := StyleBoxFlat.new()
var _style_selected: StyleBoxFlat

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
	_style_normal.set_content_margin_all(8)
	_style_selected = _style_normal.duplicate()
	_style_selected.border_color = Color(1.0, 0.85, 0.2)
	_style_selected.set_border_width_all(3)

	for i in MountainController.ABILITIES.size():
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(150, 70)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(label)
		_slots_box.add_child(slot)
		_slots.append(slot)
		_slot_labels.append(label)

	if controller:
		controller.energy_changed.connect(_refresh.unbind(1))
		controller.cooldown_changed.connect(_refresh.unbind(1))
		controller.ability_selected.connect(_refresh.unbind(1))
	_refresh()


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
