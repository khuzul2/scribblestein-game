class_name PauseMenu
extends Control

## Pause, and the always-available way out (DESIGN §3): leaving a level mid-run
## keeps banked state and any death blob, and abandons level progress.

signal resumed
signal return_to_lab

var _panel: PanelContainer = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dim: ColorRect = ColorRect.new()
	dim.color = Paper.PAPER
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Paper.panel(5))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-240, -200)
	_panel.custom_minimum_size = Vector2(480, 340)
	add_child(_panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(column)

	var title: Label = Paper.label("PAUSED", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(Paper.rule())

	var resume: Button = Paper.button("RESUME", 28)
	resume.pressed.connect(toggle)
	column.add_child(resume)

	var leave: Button = Paper.button("RETURN TO LAB", 28)
	leave.pressed.connect(func() -> void:
		Audio.sfx("sfx_ui_page_turn")
		_set_paused(false)
		return_to_lab.emit())
	column.add_child(leave)

	column.add_child(Paper.label(
		"leaving keeps your ink and any blob you left behind,\nbut abandons this run",
		16, Paper.FADED))


func toggle() -> void:
	_set_paused(not visible)
	Audio.sfx("sfx_ui_click_scratch")
	if not visible:
		resumed.emit()


func _set_paused(paused: bool) -> void:
	visible = paused
	get_tree().paused = paused
