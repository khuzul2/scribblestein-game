class_name SketchbookEditor
extends Control

## The messy-sketchbook part editor (DESIGN §11).
##
## Left page: the parts you own for the selected slot, each with the stat deltas
## equipping it would cause. Right page: the blueprint, one drop target per slot,
## with a live mannequin above it. Bottom: the always-visible readouts.
##
## The working loadout lives here and is written to the save on every change, so
## the Scratchpad round trip cannot lose it.

signal loadout_changed(loadout: Dictionary)
signal play_requested
signal unlock_requested
signal map_requested
signal blueprint_switched(blueprint_id: String)

## Which body type is being built. Read from the save on entry and changed by
## the blueprint tabs, which only appear once a second one is unlocked.
var blueprint_id: String = SaveManager.DEFAULT_BLUEPRINT
var loadout: Dictionary = {}
var selected_slot: String = "torso"

var _part_list: VBoxContainer = null
var _slot_targets: Dictionary = {}
var _readout: StatReadout = null
var _preview: CreaturePreview = null
var _problem_label: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Paper.background(self)
	blueprint_id = SaveManager.active_blueprint()
	loadout = _sanitised(SaveManager.loadout())
	_build()
	refresh()


## Change body type. The slots differ between blueprints, so the sketchbook's
## right page is rebuilt from scratch; the loadout comes from the save, which
## keeps one per blueprint — switching never throws a build away.
func switch_blueprint(new_blueprint_id: String) -> bool:
	if new_blueprint_id == blueprint_id:
		return true
	if not SaveManager.set_active_blueprint(new_blueprint_id):
		Audio.sfx("sfx_ui_error_scratch")
		return false

	blueprint_id = new_blueprint_id
	loadout = _sanitised(SaveManager.loadout())
	if not (Config.blueprint(blueprint_id)["slots"] as Dictionary).has(selected_slot):
		selected_slot = str((Config.blueprint(blueprint_id)["slots"] as Dictionary).keys()[0])

	_slot_targets.clear()
	for child: Node in get_children():
		if child is Control and child.name == "Sketchbook":
			remove_child(child)
			child.queue_free()
	_build()
	refresh()
	Audio.sfx("sfx_ui_page_turn")
	blueprint_switched.emit(blueprint_id)
	return true


# --- layout --------------------------------------------------------------------

func _build() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Sketchbook"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 40
	root.offset_top = 28
	root.offset_right = -40
	root.offset_bottom = -28
	add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 28)
	header.add_child(Paper.label("THE LAB — sketchbook", 40))
	header.add_child(Paper.spacer())
	var tabs: Control = _build_blueprint_tabs()
	if tabs != null:
		header.add_child(tabs)
	root.add_child(header)
	root.add_child(Paper.rule())

	var pages: HBoxContainer = HBoxContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.add_theme_constant_override("separation", 32)
	root.add_child(pages)

	pages.add_child(_build_left_page())
	pages.add_child(_build_right_page())

	root.add_child(Paper.rule())
	root.add_child(_build_bottom_bar())


## One tab per unlocked body type. Returns null while only one is unlocked —
## a chooser with a single choice is just clutter, and the quadruped is a
## discovery (DESIGN §8), so it should appear when it is found.
func _build_blueprint_tabs() -> Control:
	var unlocked: PackedStringArray = PackedStringArray()
	for candidate: Variant in Config.blueprints:
		if SaveManager.is_blueprint_unlocked(str(candidate)):
			unlocked.append(str(candidate))
	if unlocked.size() < 2:
		return null

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.name = "BlueprintTabs"
	tabs.add_theme_constant_override("separation", 12)
	for candidate: String in unlocked:
		var label: String = str(Config.blueprint(candidate).get("name", candidate))
		var is_current: bool = candidate == blueprint_id
		var tab: Button = Paper.button(("[ %s ]" if is_current else "  %s  ") % label, 22)
		tab.disabled = is_current
		tab.pressed.connect(switch_blueprint.bind(candidate))
		tabs.add_child(tab)
	return tabs


func _build_left_page() -> Control:
	var page: VBoxContainer = Paper.page("parts you own")
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_stretch_ratio = 1.1

	var hint: Label = Paper.label("drag a part onto its slot, or click to equip", 16, Paper.FADED)
	page.add_child(hint)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	_part_list = VBoxContainer.new()
	_part_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_part_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_part_list)
	return page


func _build_right_page() -> Control:
	var page: VBoxContainer = Paper.page(
		str(Config.blueprint(blueprint_id).get("name", blueprint_id)).to_lower())
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	page.add_child(body)

	_preview = CreaturePreview.new()
	body.add_child(_preview)

	var slots_column: VBoxContainer = VBoxContainer.new()
	slots_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_column.add_theme_constant_override("separation", 8)
	body.add_child(slots_column)

	for slot_id: Variant in (Config.blueprint(blueprint_id)["slots"] as Dictionary):
		var slot: String = str(slot_id)
		var target: SlotTarget = SlotTarget.create(slot,
			(Config.blueprint(blueprint_id)["slots"] as Dictionary)[slot] as Dictionary)
		target.part_dropped.connect(_on_part_dropped)
		target.cleared.connect(_on_slot_cleared)
		target.gui_input.connect(_on_slot_clicked.bind(slot))
		slots_column.add_child(target)
		_slot_targets[slot] = target

	_problem_label = Paper.label("", 18)
	_problem_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slots_column.add_child(_problem_label)
	return page


func _build_bottom_bar() -> Control:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 40)

	_readout = StatReadout.new()
	bar.add_child(_readout)
	bar.add_child(Paper.spacer())

	var play: Button = Paper.button("PLAY IN LAB", 26)
	play.pressed.connect(func() -> void:
		Audio.sfx("sfx_ui_click_scratch")
		play_requested.emit())
	bar.add_child(play)

	var desk: Button = Paper.button("UNLOCK DESK", 26)
	desk.pressed.connect(func() -> void:
		Audio.sfx("sfx_ui_page_turn")
		unlock_requested.emit())
	bar.add_child(desk)

	var map: Button = Paper.button("WORLD MAP", 26)
	map.pressed.connect(func() -> void:
		Audio.sfx("sfx_ui_page_turn")
		map_requested.emit())
	bar.add_child(map)
	return bar


# --- state ---------------------------------------------------------------------

## Redraw everything from the current loadout. Cheap enough to call on any change.
func refresh() -> void:
	var stats: CreatureStats = PartAssembler.preview_stats(loadout, blueprint_id)
	_readout.show_stats(stats)

	for slot_id: Variant in _slot_targets:
		(_slot_targets[slot_id] as SlotTarget).show_part(loadout.get(slot_id, null))

	var problems: PackedStringArray = PartAssembler.validate(loadout, blueprint_id)
	_problem_label.text = "" if problems.is_empty() else "! %s" % "\n! ".join(problems)
	if problems.is_empty():
		_preview.show_loadout(loadout, blueprint_id)
		_preview.fit()

	_rebuild_part_list()


func _rebuild_part_list() -> void:
	for child: Node in _part_list.get_children():
		_part_list.remove_child(child)
		child.queue_free()

	var slot_spec: Dictionary = (Config.blueprint(blueprint_id)["slots"] as Dictionary)[selected_slot] as Dictionary
	_part_list.add_child(Paper.label(
		"%s  ·  %s" % [selected_slot.to_upper(), str(slot_spec.get("kind", ""))], 24))

	if not bool(slot_spec.get("required", false)):
		var none: Button = Paper.button("  — leave empty —", 20)
		none.custom_minimum_size = Vector2(0, 64)
		none.alignment = HORIZONTAL_ALIGNMENT_LEFT
		none.pressed.connect(func() -> void: _equip(selected_slot, null))
		_part_list.add_child(none)

	var any: bool = false
	for part_id: String in owned_parts_for(selected_slot):
		any = true
		var card: PartCard = PartCard.create(part_id, deltas_for(selected_slot, part_id),
			loadout.get(selected_slot, null) == part_id)
		card.picked.connect(func(id: String) -> void: _equip(selected_slot, id))
		_part_list.add_child(card)

	if not any:
		_part_list.add_child(Paper.label(
			"nothing unlocked for this slot yet — kill things, then visit the desk",
			18, Paper.FADED))


## Unlocked parts that fit this blueprint and this slot, in catalogue order.
func owned_parts_for(slot: String) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		if str(part["slot"]) != slot:
			continue
		if not (part["fits_blueprints"] as Array).has(blueprint_id):
			continue
		if not SaveManager.is_unlocked(str(part_id)):
			continue
		ids.append(str(part_id))
	ids.sort()
	return ids


## What equipping `part_id` into `slot` would change, versus the current build.
func deltas_for(slot: String, part_id: String) -> Dictionary:
	var current: CreatureStats = PartAssembler.preview_stats(loadout, blueprint_id)
	var candidate_loadout: Dictionary = loadout.duplicate(true)
	candidate_loadout[slot] = part_id
	var candidate: CreatureStats = PartAssembler.preview_stats(candidate_loadout, blueprint_id)

	var slot_spec: Dictionary = (Config.blueprint(blueprint_id)["slots"] as Dictionary)[slot] as Dictionary
	var wired: String = str(slot_spec.get("wired_to", ""))
	var attack_delta: float = 0.0
	if wired != "":
		attack_delta = float(candidate.attack_for(wired).get("attack_power", 0.0)) \
			- float(current.attack_for(wired).get("attack_power", 0.0))

	return {
		"hp": candidate.max_hp - current.max_hp,
		"def": candidate.total_defense - current.total_defense,
		"weight": candidate.total_weight - current.total_weight,
		"atk": attack_delta,
	}


func _equip(slot: String, part_id: Variant) -> void:
	var candidate: Dictionary = loadout.duplicate(true)
	candidate[slot] = part_id
	var problems: PackedStringArray = PartAssembler.validate(candidate, blueprint_id)
	if not problems.is_empty():
		Audio.sfx("sfx_ui_error_scratch")
		_problem_label.text = "! %s" % "\n! ".join(problems)
		return

	loadout = candidate
	Audio.sfx("sfx_ui_click_scratch")
	SaveManager.set_loadout(loadout)
	loadout_changed.emit(loadout)
	refresh()


func _on_part_dropped(slot: String, part_id: String) -> void:
	selected_slot = slot
	_equip(slot, part_id)


func _on_slot_cleared(slot: String) -> void:
	selected_slot = slot
	_equip(slot, null)


func _on_slot_clicked(event: InputEvent, slot: String) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if selected_slot == slot:
		return
	selected_slot = slot
	Audio.sfx("sfx_ui_page_turn")
	_rebuild_part_list()


# --- drag feedback -------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_highlight_compatible_slots(true)
	elif what == NOTIFICATION_DRAG_END:
		_highlight_compatible_slots(false)
		# The engine refuses a drop onto a slot the part does not belong in, and
		# the card springs back on its own. That refusal is what the player hears.
		if not get_viewport().gui_is_drag_successful():
			Audio.sfx("sfx_ui_error_scratch")


func _highlight_compatible_slots(highlight: bool) -> void:
	var payload: Variant = get_viewport().gui_get_drag_data()
	var slot: String = str((payload as Dictionary).get("slot", "")) \
		if payload is Dictionary else ""
	for slot_id: Variant in _slot_targets:
		(_slot_targets[slot_id] as SlotTarget).set_highlighted(highlight and str(slot_id) == slot)


## Fill in any slot the blueprint declares but the save omits, so a save written
## by an older build cannot leave a hole in the sketchbook.
func _sanitised(saved: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for slot_id: Variant in (Config.blueprint(blueprint_id)["slots"] as Dictionary):
		result[str(slot_id)] = saved.get(slot_id, null)
	return result
