class_name PartCard
extends Button

## One entry in the sketchbook's left page: a part you own, with the stat deltas
## equipping it would cause (DESIGN §11 — "scribbled stat deltas").
##
## Cards are the drag source. The drop targets decide what is legal; a card only
## has to say which part it is.

signal picked(part_id: String)

const DRAG_PREVIEW_HEIGHT: float = 96.0

var part_id: String = ""
var part: Dictionary = {}
var slot: String = ""
## True when this part is the one currently in its slot.
var equipped: bool = false


static func create(id: String, deltas: Dictionary, is_equipped: bool) -> PartCard:
	var card: PartCard = PartCard.new()
	card.part_id = id
	card.part = Config.part(id)
	card.slot = str(card.part["slot"])
	card.equipped = is_equipped
	card.name = "Card_%s" % id
	card.custom_minimum_size = Vector2(0, 92)
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.clip_text = false
	card.autowrap_mode = TextServer.AUTOWRAP_OFF
	Paper.style_button(card, 20)
	card.text = card._compose_text(deltas)
	card.tooltip_text = str(card.part.get("flavor", ""))
	card.pressed.connect(func() -> void: card.picked.emit(card.part_id))
	return card


func _compose_text(deltas: Dictionary) -> String:
	var marker: String = "> " if equipped else "  "
	var summary: PackedStringArray = PackedStringArray()
	for key: String in ["hp", "def", "atk", "weight"]:
		if not deltas.has(key):
			continue
		var value: float = float(deltas[key])
		if is_zero_approx(value):
			continue
		summary.append("%s %+d" % [key.to_upper(), int(round(value))])
	for effect_id: Variant in part.get("effects", []) as Array:
		summary.append(str(effect_id))
	return "%s%s\n   %s" % [marker, str(part["name"]), " · ".join(summary)]


## Godot asks for this when a drag starts. The payload is just the identity;
## legality is the drop target's business.
func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview: Button = Paper.button(str(part["name"]), 20)
	preview.custom_minimum_size = Vector2(320, 56)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_drag_preview(preview)
	return {"kind": "part", "part_id": part_id, "slot": slot}
