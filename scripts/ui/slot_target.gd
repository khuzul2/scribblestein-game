class_name SlotTarget
extends PanelContainer

## One slot of the blueprint on the sketchbook's right page — a drop target.
##
## It accepts a part only when the part's own `slot` matches, so a wrong drop is
## refused by the engine and the card snaps back on its own; the editor turns
## that refusal into `sfx_ui_error_scratch` (DESIGN §11).

signal part_dropped(slot: String, part_id: String)
signal cleared(slot: String)

const HEIGHT: float = 78.0

var slot: String = ""
var slot_spec: Dictionary = {}
var part_id: Variant = null

var _label: Label = null
var _clear_button: Button = null


static func create(slot_id: String, spec: Dictionary) -> SlotTarget:
	var target: SlotTarget = SlotTarget.new()
	target.slot = slot_id
	target.slot_spec = spec
	target.name = "Slot_%s" % slot_id
	target.custom_minimum_size = Vector2(0, HEIGHT)
	target.add_theme_stylebox_override("panel", Paper.panel())

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	target.add_child(row)

	var heading: Label = Paper.label(target._heading(), 18)
	heading.custom_minimum_size = Vector2(190, 0)
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(heading)

	target._label = Paper.label("— empty —", 22)
	target._label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	target._label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(target._label)

	target._clear_button = Paper.button("x", 20)
	target._clear_button.custom_minimum_size = Vector2(48, 0)
	target._clear_button.visible = false
	target._clear_button.pressed.connect(func() -> void: target.cleared.emit(target.slot))
	row.add_child(target._clear_button)
	return target


## "HEAD · attack · primary" — kind and wiring, straight from blueprints.json.
func _heading() -> String:
	var bits: PackedStringArray = PackedStringArray([slot.to_upper()])
	bits.append(str(slot_spec.get("kind", "")))
	if bool(slot_spec.get("required", false)):
		bits.append("required")
	var wired: String = str(slot_spec.get("wired_to", ""))
	if wired != "":
		bits.append(wired.replace("attack_", ""))
	return " · ".join(bits)


func show_part(new_part_id: Variant) -> void:
	part_id = new_part_id
	if part_id == null:
		_label.text = "— empty —"
		Paper.style_label(_label, 22, Paper.FADED)
		_clear_button.visible = false
		return
	_label.text = str(Config.part(str(part_id))["name"])
	Paper.style_label(_label, 22, Paper.INK)
	_clear_button.visible = not bool(slot_spec.get("required", false))


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var payload: Dictionary = data as Dictionary
	return str(payload.get("kind", "")) == "part" and str(payload.get("slot", "")) == slot


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	part_dropped.emit(slot, str((data as Dictionary)["part_id"]))


## Highlight while a compatible part is being dragged over the whole editor.
func set_highlighted(highlighted: bool) -> void:
	add_theme_stylebox_override("panel",
		Paper.panel(Paper.BORDER_WIDTH + 3) if highlighted else Paper.panel())
