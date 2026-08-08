class_name UnlockDesk
extends Control

## The unlock desk (DESIGN §11): the Blueprint Sketches you have found, and the
## ink price of turning each into a permanently owned part.
##
## A sketch is the permission to buy; the ink is the cost. Both are required, and
## the cost is `parts_db.json → unlock_cost` — never a number typed here.

signal closed
signal part_unlocked(part_id: String)
signal blueprint_bought(blueprint_id: String)

var _list: VBoxContainer = null
var _wallet: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Paper.background(self)

	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 120
	root.offset_top = 60
	root.offset_right = -120
	root.offset_bottom = -60
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 30)
	root.add_child(header)
	header.add_child(Paper.label("UNLOCK DESK", 40))
	header.add_child(Paper.spacer())
	_wallet = Paper.label("", 30)
	header.add_child(_wallet)

	var back: Button = Paper.button("BACK", 24)
	back.pressed.connect(func() -> void:
		Audio.sfx("sfx_ui_page_turn")
		closed.emit())
	header.add_child(back)

	root.add_child(Paper.rule())
	root.add_child(Paper.label(
		"a sketch is permission to build it; the ink is the price", 18, Paper.FADED))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	refresh()


func refresh() -> void:
	_wallet.text = "INK  %d" % SaveManager.ink
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var sketches: Array = SaveManager.blueprints_found()
	var offered: int = 0
	for part_id: Variant in sketches:
		if SaveManager.is_unlocked(str(part_id)):
			continue
		offered += 1
		_list.add_child(_row(str(part_id)))

	if offered == 0:
		_list.add_child(Paper.label(
			"no unspent sketches. kill what you want to become.", 20, Paper.FADED))

	offered += _add_blueprint_rows()

	_list.add_child(Paper.spacer(24))
	_list.add_child(Paper.label("ALREADY YOURS", 22, Paper.FADED))
	var owned: Array = SaveManager.unlocked_parts().duplicate()
	owned.sort()
	for part_id: Variant in owned:
		_list.add_child(Paper.label("  %s" % str(Config.part(str(part_id))["name"]), 18, Paper.FADED))


## Whole body types are sold here too. A part is a limb; a blueprint is the thing
## the limbs hang off, so it is priced separately in `blueprints.json` and comes
## with the free parts it needs to stand up (SaveManager.unlock_blueprint).
func _add_blueprint_rows() -> int:
	var rows: int = 0
	for blueprint_id: Variant in Config.blueprints:
		var blueprint: Dictionary = Config.blueprints[blueprint_id] as Dictionary
		if SaveManager.is_blueprint_unlocked(str(blueprint_id)):
			continue
		if not blueprint.has("unlock_cost"):
			continue
		if rows == 0:
			_list.add_child(Paper.spacer(24))
			_list.add_child(Paper.label("WHOLE BODIES", 22, Paper.FADED))
		rows += 1
		_list.add_child(_blueprint_row(str(blueprint_id), blueprint))
	return rows


func _blueprint_row(blueprint_id: String, blueprint: Dictionary) -> Control:
	var cost: int = int(blueprint["unlock_cost"])
	var affordable: bool = SaveManager.ink >= cost

	var frame: PanelContainer = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Paper.panel())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	frame.add_child(row)

	var slots: Dictionary = blueprint["slots"] as Dictionary
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(Paper.label(str(blueprint["name"]), 26))
	text.add_child(Paper.label("BLUEPRINT · %s" % ", ".join(PackedStringArray(slots.keys())),
		16, Paper.FADED))
	row.add_child(text)

	row.add_child(Paper.label("%d ink" % cost, 26,
		Paper.INK if affordable else Paper.FADED))

	var buy: Button = Paper.button("UNLOCK", 24)
	buy.disabled = not affordable
	buy.pressed.connect(_buy_blueprint.bind(blueprint_id))
	row.add_child(buy)
	return frame


func _buy_blueprint(blueprint_id: String) -> void:
	var cost: int = int(Config.blueprint(blueprint_id)["unlock_cost"])
	if not SaveManager.spend_ink(cost):
		Audio.sfx("sfx_ui_error_scratch")
		return
	SaveManager.unlock_blueprint(blueprint_id)
	SaveManager.request_save()
	Audio.sfx("sfx_unlock_kaching_mouth")
	Audio.sfx("sfx_ui_stamp")
	blueprint_bought.emit(blueprint_id)
	refresh()


func _row(part_id: String) -> Control:
	var part: Dictionary = Config.part(part_id)
	var cost: int = int(part["unlock_cost"])
	var affordable: bool = SaveManager.ink >= cost

	var frame: PanelContainer = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Paper.panel())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	frame.add_child(row)

	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(Paper.label(str(part["name"]), 26))
	text.add_child(Paper.label("%s · %s" % [str(part["slot"]).to_upper(),
		str(part.get("flavor", ""))], 16, Paper.FADED))
	row.add_child(text)

	row.add_child(Paper.label("%d ink" % cost, 26,
		Paper.INK if affordable else Paper.FADED))

	var buy: Button = Paper.button("UNLOCK", 24)
	buy.disabled = not affordable
	buy.pressed.connect(_buy.bind(part_id))
	row.add_child(buy)
	return frame


## Spend exactly `unlock_cost` and persist immediately — an unlock the player
## paid for must survive whatever happens next.
func _buy(part_id: String) -> void:
	var cost: int = int(Config.part(part_id)["unlock_cost"])
	if not SaveManager.spend_ink(cost):
		Audio.sfx("sfx_ui_error_scratch")
		return
	SaveManager.unlock_part(part_id)
	SaveManager.request_save()
	Audio.sfx("sfx_unlock_kaching_mouth")
	Audio.sfx("sfx_ui_stamp")
	part_unlocked.emit(part_id)
	refresh()
