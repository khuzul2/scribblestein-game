class_name StatReadout
extends HBoxContainer

## The always-visible character sheet (DESIGN §11): HP, weight total plus the
## scribbled class stamp, attack power per button, defense, and the active
## abilities.
##
## Every figure is recomputed from the loadout through the same
## `PartAssembler.preview_stats` the real assembly uses, so the sketchbook can
## never show a number the creature will not actually have.

var _hp: Label = null
var _defense: Label = null
var _weight: Label = null
var _stamp: Label = null
var _primary: Label = null
var _secondary: Label = null
var _abilities: Label = null


func _ready() -> void:
	add_theme_constant_override("separation", 28)
	_hp = _add_field("HP")
	_defense = _add_field("DEF")
	_weight = _add_field("WEIGHT")
	_stamp = _add_stamp()
	_primary = _add_field("PRIMARY")
	_secondary = _add_field("SECONDARY")
	_abilities = _add_field("ABILITIES")


func show_stats(stats: CreatureStats) -> void:
	_hp.text = str(int(stats.max_hp))
	_defense.text = str(int(stats.total_defense))
	_weight.text = str(int(stats.total_weight))

	var class_id: String = WeightClass.class_for_weight(stats.total_weight)
	_stamp.text = class_id.substr(0, 1).to_upper()
	_stamp.tooltip_text = class_id.capitalize()

	_primary.text = _attack_text(stats, "attack_primary")
	_secondary.text = _attack_text(stats, "attack_secondary")

	var abilities: PackedStringArray = PackedStringArray()
	for effect_id: Variant in stats.effects:
		if str(Config.effect(str(effect_id)).get("category", "")) != "attack":
			abilities.append(str(effect_id))
	abilities.sort()
	_abilities.text = "—" if abilities.is_empty() else " · ".join(abilities)


func _attack_text(stats: CreatureStats, action: String) -> String:
	var attack: Dictionary = stats.attack_for(action)
	if attack.is_empty():
		return "—"
	return "%d" % int(float(attack["attack_power"]))


func _add_field(title: String) -> Label:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.add_child(Paper.label(title, 16, Paper.FADED))
	var value: Label = Paper.label("—", 28)
	column.add_child(value)
	add_child(column)
	return value


## The scribbled L / M / H stamp (DESIGN §5).
func _add_stamp() -> Label:
	var frame: PanelContainer = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Paper.panel(4))
	var stamp: Label = Paper.label("M", 34)
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.custom_minimum_size = Vector2(46, 0)
	frame.add_child(stamp)
	add_child(frame)
	return stamp
