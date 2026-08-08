class_name LevelEditor
extends Control

## The level editor, in the game's own sketchbook idiom.
##
## It is an ordinary scene rather than a Godot plugin so that it ships: a player
## can draw a level in an exported build, which is the whole point of the level
## files being data. It writes exactly the format `DataLevel` reads, and Playtest
## enters the level for real with the build currently in the Lab — so what you
## see while testing is what a player gets, not an approximation of it.

signal closed
signal playtest_requested(level: LevelData)

const CAMERA_PAN_BUTTON: MouseButton = MOUSE_BUTTON_MIDDLE
const ZOOM_STEP: float = 1.15
## Room left around a level when the view is framed to it.
const FRAME_MARGIN: float = 240.0

var level: LevelData = null
var history: EditorHistory = EditorHistory.new()

var _canvas: EditorCanvas = null
var _camera: Camera2D = null
var _world: SubViewport = null
var _panel: VBoxContainer = null
var _status: Label = null
var _title: Label = null
var _tool_buttons: Dictionary = {}
var _panning: bool = false
var _unsaved: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Paper.background(self)
	# One theme at the root, so panels rebuilt later cannot arrive in Godot's
	# default grey — which is not a colour this game has (Mandate A1).
	theme = Paper.control_theme()
	if level == null:
		level = _blank_level()
	history.begin(level)
	_build()
	_frame_level()
	_refresh()


## Open an existing level by id, or start a new one when it does not exist yet.
func open(level_id: String) -> void:
	var problems: PackedStringArray = PackedStringArray()
	var path: String = LevelData.find(level_id)
	if path != "":
		var loaded: LevelData = LevelData.load_from(path, problems)
		if loaded != null:
			level = loaded
		else:
			_say("could not open %s: %s" % [level_id, ", ".join(problems)])
	else:
		level = _blank_level()
		level.id = level_id
		level.name = level_id.replace("_", " ")
	if _canvas != null:
		_canvas.set_level(level)
		history.begin(level)
		_frame_level()
		_refresh()


## A level with somewhere to stand, somewhere to start and somewhere to leave —
## an empty file is technically valid and practically useless.
func _blank_level() -> LevelData:
	var fresh: LevelData = LevelData.new()
	fresh.id = "untitled"
	fresh.name = "Untitled"
	fresh.spawn = Vector2(0.0, -120.0)

	var ground: LevelData.Terrain = LevelData.Terrain.new()
	ground.kind = "solid"
	ground.points = PackedVector2Array([
		Vector2(-800.0, 0.0), Vector2(1600.0, 0.0),
		Vector2(1600.0, 400.0), Vector2(-800.0, 400.0)])
	fresh.terrain.append(ground)

	var door: LevelData.Door = LevelData.Door.new()
	door.at = Vector2(1400.0, 0.0)
	fresh.doors.append(door)
	return fresh


# --- layout --------------------------------------------------------------------

func _build() -> void:
	var root: HBoxContainer = HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_tool_column())
	root.add_child(_build_viewport())
	root.add_child(_build_side_panel())


## The drawing surface, inside a SubViewport so the world has its own camera and
## the UI around it keeps screen coordinates.
func _build_viewport() -> Control:
	var frame: VBoxContainer = VBoxContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var container: SubViewportContainer = SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	frame.add_child(container)

	_world = SubViewport.new()
	_world.handle_input_locally = false
	_world.transparent_bg = true
	container.add_child(_world)

	_camera = Camera2D.new()
	_camera.name = "EditorCamera"
	_world.add_child(_camera)

	_canvas = EditorCanvas.new()
	_canvas.name = "Canvas"
	_canvas.set_level(level)
	_canvas.level_edited.connect(_on_level_edited)
	_canvas.selection_changed.connect(_refresh_panel)
	_canvas.status.connect(_say)
	_world.add_child(_canvas)

	_status = Paper.label("", 18, Paper.FADED)
	_status.custom_minimum_size = Vector2(0, 30)
	frame.add_child(_status)
	frame.add_child(_build_bottom_bar())
	return frame


func _build_tool_column() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(230, 0)
	column.add_theme_constant_override("separation", 4)
	column.offset_left = 12

	_title = Paper.label("EDITOR", 30)
	column.add_child(_title)
	column.add_child(Paper.rule())

	var groups: Array[Array] = [
		["draw", [
			[EditorCanvas.Tool.TERRAIN_SOLID, "ground"],
			[EditorCanvas.Tool.TERRAIN_ONEWAY, "platform (one-way)"],
			[EditorCanvas.Tool.TERRAIN_CLIMBABLE, "climbable wall"],
			[EditorCanvas.Tool.TERRAIN_CRACKED, "cracked floor"],
			[EditorCanvas.Tool.TERRAIN_HAZARD, "hazard"],
			[EditorCanvas.Tool.ROPE, "rope"],
		]],
		["place", [
			[EditorCanvas.Tool.ENEMY, "enemy"],
			[EditorCanvas.Tool.INK, "ink"],
			[EditorCanvas.Tool.SKETCH, "blueprint sketch"],
			[EditorCanvas.Tool.FLUID, "correction fluid"],
			[EditorCanvas.Tool.SIGN, "warning sketch"],
			[EditorCanvas.Tool.DOOR, "exit door"],
			[EditorCanvas.Tool.SPAWN, "start"],
		]],
	]

	column.add_child(_tool_button(EditorCanvas.Tool.SELECT, "select / move"))
	for group: Array in groups:
		column.add_child(Paper.label(str(group[0]), 18, Paper.FADED))
		for entry: Variant in group[1] as Array:
			var pair: Array = entry as Array
			column.add_child(_tool_button(pair[0] as EditorCanvas.Tool, str(pair[1])))

	column.add_child(Paper.spacer(10))
	var grid_toggle: CheckBox = CheckBox.new()
	grid_toggle.text = "snap to grid"
	grid_toggle.toggled.connect(func(on: bool) -> void:
		_canvas.snap_to_grid = on
		_say("grid snap %s" % ("on" if on else "off")))
	column.add_child(grid_toggle)
	return column


func _tool_button(which: EditorCanvas.Tool, label: String) -> Button:
	var button: Button = Paper.button("  %s" % label, 20)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(_choose_tool.bind(which))
	_tool_buttons[which] = button
	return button


func _build_side_panel() -> Control:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_panel = VBoxContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_theme_constant_override("separation", 6)
	scroll.add_child(_panel)
	return scroll


func _build_bottom_bar() -> Control:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)

	var actions: Array[Array] = [
		["SAVE", save_level], ["PLAYTEST", playtest], ["CHECK", check_level],
		["UNDO", undo], ["REDO", redo], ["FRAME", _frame_level], ["BACK", _leave],
	]
	for entry: Array in actions:
		var button: Button = Paper.button(str(entry[0]), 22)
		button.pressed.connect(entry[1] as Callable)
		bar.add_child(button)
	return bar


# --- tools ---------------------------------------------------------------------

func _choose_tool(which: EditorCanvas.Tool) -> void:
	_canvas.cancel_draft()
	_canvas.tool = which
	Audio.sfx("sfx_ui_click_scratch")
	_refresh()


func _refresh() -> void:
	for key: Variant in _tool_buttons:
		var button: Button = _tool_buttons[key] as Button
		button.disabled = (key as EditorCanvas.Tool) == _canvas.tool
	_title.text = "EDITOR — %s%s" % [level.id, "*" if _unsaved else ""]
	_refresh_panel()


# --- the side panel ------------------------------------------------------------

## Properties of whatever is selected, or of the tool about to be used. One
## panel, because "what am I about to place?" and "what did I just select?" are
## the same question at different moments.
func _refresh_panel() -> void:
	for child: Node in _panel.get_children():
		_panel.remove_child(child)
		child.queue_free()

	_panel.add_child(Paper.label("LEVEL", 24))
	_panel.add_child(_text_field("id", level.id, func(value: String) -> void:
		level.id = value.to_lower().replace(" ", "_")
		_touch("rename")))
	_panel.add_child(_text_field("name", level.name, func(value: String) -> void:
		level.name = value
		_touch("rename")))
	_panel.add_child(Paper.rule())

	match _canvas.selected_kind():
		"enemy":
			_build_enemy_panel(level.enemies[_canvas.selected_index()])
		"pickup":
			_build_pickup_panel(level.pickups[_canvas.selected_index()])
		"rope":
			_build_rope_panel(level.ropes[_canvas.selected_index()])
		"sign":
			_build_sign_panel(level.signs[_canvas.selected_index()])
		"terrain":
			_panel.add_child(Paper.label("TERRAIN", 24))
			_panel.add_child(Paper.label(
				"%s · %d points" % [level.terrain[_canvas.selected_index()].kind,
					level.terrain[_canvas.selected_index()].points.size()], 18, Paper.FADED))
		_:
			_build_tool_defaults_panel()

	_panel.add_child(Paper.rule())
	_build_music_panel()


func _build_tool_defaults_panel() -> void:
	_panel.add_child(Paper.label("NEXT PLACED", 24))
	_panel.add_child(_enemy_picker(_canvas.enemy_id, func(id: String) -> void:
		_canvas.enemy_id = id))
	_panel.add_child(_part_picker(_canvas.sketch_part_id, func(id: String) -> void:
		_canvas.sketch_part_id = id))
	_panel.add_child(_number_field("ink amount", float(_canvas.ink_amount), 1.0, 999.0,
		func(value: float) -> void: _canvas.ink_amount = int(value)))
	_panel.add_child(_text_field("sign text", _canvas.sign_text,
		func(value: String) -> void: _canvas.sign_text = value))


func _build_enemy_panel(record: LevelData.EnemySpawn) -> void:
	_panel.add_child(Paper.label("ENEMY", 24))
	_panel.add_child(_enemy_picker(record.id, func(id: String) -> void:
		record.id = id
		_touch("change enemy")))
	_panel.add_child(_number_field("patrol half-width", record.patrol, 0.0, 4000.0,
		func(value: float) -> void:
			record.patrol = value
			_touch("set patrol")))
	var facing: Button = Paper.button("facing: %s" % ("right" if record.facing > 0 else "left"), 20)
	facing.pressed.connect(func() -> void:
		record.facing = -record.facing
		_touch("turn enemy"))
	_panel.add_child(facing)


func _build_pickup_panel(record: LevelData.PickupSpawn) -> void:
	_panel.add_child(Paper.label(record.kind.to_upper(), 24))
	if record.kind == "ink":
		_panel.add_child(_number_field("amount", float(record.amount), 1.0, 999.0,
			func(value: float) -> void:
				record.amount = int(value)
				_touch("set ink")))
	elif record.kind == "sketch":
		_panel.add_child(_part_picker(record.part, func(id: String) -> void:
			record.part = id
			_touch("set sketch")))


func _build_rope_panel(record: LevelData.Rope) -> void:
	_panel.add_child(Paper.label("ROPE", 24))
	_panel.add_child(_number_field("length", record.length, 40.0, 4000.0,
		func(value: float) -> void:
			record.length = value
			_touch("set rope length")))


func _build_sign_panel(record: LevelData.Sign) -> void:
	_panel.add_child(Paper.label("WARNING SKETCH", 24))
	_panel.add_child(_text_field("text", record.text, func(value: String) -> void:
		record.text = value
		_touch("edit sign")))


## Up to five songs per level, in the order they will play.
func _build_music_panel() -> void:
	_panel.add_child(Paper.label("SOUNDTRACK", 24))
	_panel.add_child(Paper.label(
		"up to %d songs · ogg, mp3 or wav" % LevelData.MAX_TRACKS, 16, Paper.FADED))

	for index: int in range(level.music.tracks.size()):
		var row: HBoxContainer = HBoxContainer.new()
		row.add_child(Paper.label("%d. %s" % [index + 1, level.music.tracks[index]], 18))
		row.add_child(Paper.spacer())
		if index > 0:
			var up: Button = Paper.button("↑", 18)
			up.pressed.connect(_move_track.bind(index, -1))
			row.add_child(up)
		if index < level.music.tracks.size() - 1:
			var down: Button = Paper.button("↓", 18)
			down.pressed.connect(_move_track.bind(index, 1))
			row.add_child(down)
		var drop: Button = Paper.button("×", 18)
		drop.pressed.connect(_remove_track.bind(index))
		row.add_child(drop)
		_panel.add_child(row)

	if level.music.tracks.size() < LevelData.MAX_TRACKS:
		var add: Button = Paper.button("+ add a song…", 20)
		add.pressed.connect(_pick_track_file)
		_panel.add_child(add)
	else:
		_panel.add_child(Paper.label("five is the limit", 16, Paper.FADED))

	var shuffle: CheckBox = CheckBox.new()
	shuffle.text = "shuffle"
	shuffle.button_pressed = level.music.shuffle
	shuffle.toggled.connect(func(on: bool) -> void:
		level.music.shuffle = on
		_touch("shuffle %s" % ("on" if on else "off")))
	_panel.add_child(shuffle)


# --- small widgets -------------------------------------------------------------

func _text_field(label: String, value: String, on_change: Callable) -> Control:
	var row: VBoxContainer = VBoxContainer.new()
	row.add_child(Paper.label(label, 16, Paper.FADED))
	var field: LineEdit = LineEdit.new()
	field.text = value
	field.text_submitted.connect(func(text: String) -> void: on_change.call(text))
	field.focus_exited.connect(func() -> void: on_change.call(field.text))
	row.add_child(field)
	return row


func _number_field(label: String, value: float, low: float, high: float,
		on_change: Callable) -> Control:
	var row: VBoxContainer = VBoxContainer.new()
	row.add_child(Paper.label(label, 16, Paper.FADED))
	var field: SpinBox = SpinBox.new()
	field.min_value = low
	field.max_value = high
	field.step = 1.0
	field.value = value
	field.value_changed.connect(func(changed: float) -> void: on_change.call(changed))
	row.add_child(field)
	return row


func _enemy_picker(selected: String, on_change: Callable) -> Control:
	var row: VBoxContainer = VBoxContainer.new()
	row.add_child(Paper.label("enemy", 16, Paper.FADED))
	var picker: OptionButton = OptionButton.new()
	var ids: PackedStringArray = PackedStringArray(Config.enemies.keys())
	ids.sort()
	for index: int in range(ids.size()):
		picker.add_item(str(Config.enemy(ids[index])["name"]), index)
		if ids[index] == selected:
			picker.select(index)
	picker.item_selected.connect(func(index: int) -> void: on_change.call(ids[index]))
	row.add_child(picker)
	return row


func _part_picker(selected: String, on_change: Callable) -> Control:
	var row: VBoxContainer = VBoxContainer.new()
	row.add_child(Paper.label("sketch part", 16, Paper.FADED))
	var picker: OptionButton = OptionButton.new()
	var ids: PackedStringArray = PackedStringArray(Config.parts.keys())
	ids.sort()
	for index: int in range(ids.size()):
		picker.add_item(str(Config.part(ids[index])["name"]), index)
		if ids[index] == selected:
			picker.select(index)
	picker.item_selected.connect(func(index: int) -> void: on_change.call(ids[index]))
	row.add_child(picker)
	return row


# --- soundtrack ----------------------------------------------------------------

## A native file dialog, because the songs are the player's own files and live
## outside the game. Whatever is chosen is copied into the level's soundtrack
## folder, so the level keeps working if the original is later moved.
func _pick_track_file() -> void:
	var dialog: FileDialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.ogg, *.mp3, *.wav ; Audio"])
	dialog.file_selected.connect(_add_track)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)


func _add_track(source_path: String) -> void:
	var problems: PackedStringArray = PackedStringArray()
	var stored: String = MusicDirector.import_track(level.id, source_path, problems)
	if stored == "":
		_say(", ".join(problems))
		return
	if level.music.tracks.size() >= LevelData.MAX_TRACKS:
		_say("this level already has %d songs" % LevelData.MAX_TRACKS)
		return
	level.music.tracks.append(stored)
	_touch("add song")
	_say("added %s" % stored)


func _move_track(index: int, direction: int) -> void:
	var target: int = index + direction
	if target < 0 or target >= level.music.tracks.size():
		return
	var held: String = level.music.tracks[index]
	level.music.tracks[index] = level.music.tracks[target]
	level.music.tracks[target] = held
	_touch("reorder songs")


func _remove_track(index: int) -> void:
	level.music.tracks.remove_at(index)
	_touch("remove song")


# --- file and playtest ---------------------------------------------------------

func save_level() -> void:
	var problems: PackedStringArray = level.save()
	if not problems.is_empty():
		_say("cannot save: %s" % ", ".join(problems))
		Audio.sfx("sfx_ui_error_scratch")
		return
	_unsaved = false
	Audio.sfx("sfx_ui_stamp")
	_say("saved to %s" % level.source_path)
	_refresh()


## Report what is wrong with the level before someone plays it — an unreachable
## exit is a much better thing to be told than to discover.
func check_level() -> void:
	var problems: PackedStringArray = LevelData.validate(level.to_dictionary())
	for record: LevelData.EnemySpawn in level.enemies:
		if not Config.enemies.has(record.id):
			problems.append("no such enemy '%s'" % record.id)
	for record: LevelData.PickupSpawn in level.pickups:
		if record.kind == "sketch" and not Config.parts.has(record.part):
			problems.append("no such part '%s'" % record.part)
	if level.doors.is_empty():
		problems.append("no way out — place an exit door")

	if problems.is_empty():
		var starter: CreatureStats = PartAssembler.preview_stats(
			SaveManager.loadout("biped"), "biped")
		if not LevelGeometry.walkable_to_exit(level, starter):
			problems.append("the exit may be out of reach of the build in the Lab — "
				+ "the checker only follows walking and jumping, so a route that "
				+ "needs climbing or gliding will say this too")

	if problems.is_empty():
		_say("no problems found")
		Audio.sfx("sfx_ui_stamp")
	else:
		_say("! %s" % "  ·  ".join(problems))
		Audio.sfx("sfx_ui_error_scratch")


func playtest() -> void:
	var problems: PackedStringArray = level.save()
	if not problems.is_empty():
		_say("cannot playtest an unsaveable level: %s" % ", ".join(problems))
		return
	_unsaved = false
	playtest_requested.emit(level)


func undo() -> void:
	var restored: LevelData = history.undo()
	if restored == null:
		_say("nothing to undo")
		return
	_restore(restored)
	_say("undid %s" % history.next_undo_label())


func redo() -> void:
	var restored: LevelData = history.redo()
	if restored == null:
		_say("nothing to redo")
		return
	_restore(restored)
	_say("redone")


func _restore(restored: LevelData) -> void:
	restored.source_path = level.source_path
	level = restored
	_canvas.set_level(level)
	_unsaved = true
	_refresh()


func _leave() -> void:
	closed.emit()


# --- edits ---------------------------------------------------------------------

func _on_level_edited(label: String) -> void:
	history.record(level, label)
	_unsaved = true
	_say(label)
	_refresh()


## For panel edits, which change the level in place rather than through the canvas.
func _touch(label: String) -> void:
	_on_level_edited(label)
	_canvas.queue_redraw()


func _say(message: String) -> void:
	if _status != null:
		_status.text = message


# --- camera and input ----------------------------------------------------------

func _frame_level() -> void:
	var box: Rect2 = LevelGeometry.bounds(level).grow(FRAME_MARGIN)
	_camera.position = box.get_center()
	var view: Vector2 = _world.size if _world.size.x > 0.0 else Vector2(1280.0, 720.0)
	var fit: float = minf(view.x / maxf(box.size.x, 1.0), view.y / maxf(box.size.y, 1.0))
	_camera.zoom = Vector2.ONE * clampf(fit, EditorCanvas.ZOOM_MIN, EditorCanvas.ZOOM_MAX)


func _world_position(screen_position: Vector2) -> Vector2:
	var view: Vector2 = _world.size
	return _camera.position + (screen_position - view * 0.5) / _camera.zoom


func _gui_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if _panning:
			_camera.position -= motion.relative / _camera.zoom
		_canvas.cursor_moved(_world_position(motion.position))
		return

	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null:
		return

	if button.button_index == CAMERA_PAN_BUTTON:
		_panning = button.pressed
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
		_zoom(ZOOM_STEP)
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
		_zoom(1.0 / ZOOM_STEP)
		return
	if button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_canvas.primary_pressed(_world_position(button.position))
		else:
			_canvas.primary_released()
		return
	if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		_canvas.secondary_pressed(_world_position(button.position))


func _zoom(factor: float) -> void:
	_camera.zoom = (_camera.zoom * factor).clampf(
		EditorCanvas.ZOOM_MIN, EditorCanvas.ZOOM_MAX)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.ctrl_pressed and key.keycode == KEY_Z:
		redo() if key.shift_pressed else undo()
	elif key.ctrl_pressed and key.keycode == KEY_S:
		save_level()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_canvas.close_draft()
	elif key.keycode == KEY_ESCAPE:
		_canvas.cancel_draft()
	elif key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE:
		_canvas.delete_selected()
	else:
		return
	get_viewport().set_input_as_handled()
