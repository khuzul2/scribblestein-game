class_name WorldMap
extends Control

## The sketchbook world map table (DESIGN §11): pick a level, see which are
## cleared, and see at a glance which are still holding an unrecovered ink blob.
##
## Entering a level is a loadout commitment (DESIGN §3), so the map states the
## anatomical keys each level advertises before you commit.

signal closed
signal level_chosen(level_id: String)
signal editor_requested(level_id: String)

var _list: VBoxContainer = null


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
	header.add_child(Paper.label("THE MAP TABLE", 40))
	header.add_child(Paper.spacer())

	var edit: Button = Paper.button("LEVEL EDITOR", 24)
	edit.pressed.connect(func() -> void:
		Audio.sfx("sfx_ui_page_turn")
		editor_requested.emit(""))
	header.add_child(edit)

	var back: Button = Paper.button("BACK", 24)
	back.pressed.connect(func() -> void:
		Audio.sfx("sfx_ui_page_turn")
		closed.emit())
	header.add_child(back)

	root.add_child(Paper.rule())
	root.add_child(Paper.label(
		"you cannot rebuild once you are inside. choose your anatomy first.",
		18, Paper.FADED))

	_list = VBoxContainer.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	root.add_child(_list)

	refresh()


func refresh() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for level_id: String in Config.map_level_ids():
		_list.add_child(_row(level_id))


func _row(level_id: String) -> Control:
	var level: Dictionary = Config.level(level_id)
	var unlocked: bool = _is_unlocked(level_id)
	var completed: bool = SaveManager.is_level_completed(level_id)
	var blob: Variant = SaveManager.death_blob(level_id)
	var buildable: bool = ResourceLoader.exists(str(level["scene"]))

	var frame: PanelContainer = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Paper.panel())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	frame.add_child(row)

	# A scrawled tick for cleared, an ink blot for an unrecovered wallet.
	var marks: PackedStringArray = PackedStringArray()
	if completed:
		marks.append("[X]")
	if blob != null:
		marks.append("(*%d ink)" % int((blob as Dictionary)["amount"]))
	var mark: Label = Paper.label(" ".join(marks), 26)
	mark.custom_minimum_size = Vector2(180, 0)
	row.add_child(mark)

	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(Paper.label(str(level["name"]), 30))
	text.add_child(Paper.label(str(level.get("blurb", "")), 17, Paper.FADED))
	var keys: Array = level.get("keys", []) as Array
	if not keys.is_empty():
		text.add_child(Paper.label("warning sketch: %s"
			% " · ".join(PackedStringArray(keys)), 17, Paper.FADED))
	row.add_child(text)

	var enter: Button = Paper.button("ENTER" if buildable else "NOT DRAWN YET", 24)
	enter.disabled = not unlocked or not buildable
	enter.pressed.connect(func() -> void:
		Audio.sfx("sfx_ui_click_scratch")
		level_chosen.emit(level_id))
	row.add_child(enter)
	return frame


## Levels unlock linearly at first: a level opens once everything it `requires`
## is cleared (DESIGN §3).
func _is_unlocked(level_id: String) -> bool:
	for required: Variant in Config.level(level_id).get("requires", []) as Array:
		if not SaveManager.is_level_completed(str(required)):
			return false
	return true
