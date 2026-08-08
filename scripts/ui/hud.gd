class_name Hud
extends Control

## The in-play readout: health, the wallet, and the class stamp. Deliberately
## sparse — the page should read as a drawing, not a dashboard.

const BAR_SIZE: Vector2 = Vector2(420, 34)

var _health_fill: ColorRect = null
var _health_text: Label = null
var _ink: Label = null
var _stamp: Label = null
var _creature: Creature = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var root: HBoxContainer = HBoxContainer.new()
	root.position = Vector2(40, 32)
	root.add_theme_constant_override("separation", 24)
	add_child(root)

	var frame: PanelContainer = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Paper.panel(3))
	root.add_child(frame)

	var bar: Control = Control.new()
	bar.custom_minimum_size = BAR_SIZE
	frame.add_child(bar)

	_health_fill = ColorRect.new()
	_health_fill.color = Paper.INK
	_health_fill.size = BAR_SIZE
	bar.add_child(_health_fill)

	_health_text = Paper.label("", 22, Paper.PAPER)
	_health_text.position = Vector2(10, 2)
	bar.add_child(_health_text)

	var stamp_frame: PanelContainer = PanelContainer.new()
	stamp_frame.add_theme_stylebox_override("panel", Paper.panel(4))
	_stamp = Paper.label("M", 30)
	_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stamp.custom_minimum_size = Vector2(42, 0)
	stamp_frame.add_child(_stamp)
	root.add_child(stamp_frame)

	_ink = Paper.label("INK 0", 28)
	root.add_child(_ink)

	SaveManager.ink_changed.connect(func(_amount: int) -> void: _refresh_ink())
	_refresh_ink()


## Follow a creature's health and weight class.
func watch(creature: Creature) -> void:
	_creature = creature
	if creature == null:
		return
	creature.health.changed.connect(_on_health_changed)
	creature.assembled.connect(func(_stats: CreatureStats) -> void: _refresh_stamp())
	_on_health_changed(creature.health.current, creature.health.maximum)
	_refresh_stamp()


func _on_health_changed(current: float, maximum: float) -> void:
	var fraction: float = 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	_health_fill.size = Vector2(BAR_SIZE.x * fraction, BAR_SIZE.y)
	_health_text.text = "%d / %d" % [int(current), int(maximum)]
	# Once the bar is short the black fill no longer sits under the text.
	Paper.style_label(_health_text, 22, Paper.PAPER if fraction > 0.35 else Paper.INK)


func _refresh_ink() -> void:
	_ink.text = "INK %d" % SaveManager.ink


func _refresh_stamp() -> void:
	if _creature != null:
		_stamp.text = _creature.weight_class.stamp()
