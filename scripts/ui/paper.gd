class_name Paper
extends RefCounted

## Shared look for every Control in the game: black ink on paper white, nothing
## in between (Mandate A1). Built in code rather than as a `.theme` resource so
## the palette has exactly one definition and the asset validator's allowlist and
## the UI can never disagree.
##
## The final hand-drawn UI pass (borders that wobble, a scrawled typeface) is
## M6's job; this is the honest monochrome skeleton it will dress.

const INK: Color = Color("#000000")
const PAPER: Color = Color("#f4f0e6")
## De-emphasised text. Still pure ink — Mandate A1 allows no grey anywhere, so
## hierarchy is carried by size and weight, never by a faded tint.
const FADED: Color = INK

const BORDER_WIDTH: int = 3
const PADDING: int = 12


static func panel(border: int = BORDER_WIDTH, fill: Color = PAPER) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = INK
	box.set_border_width_all(border)
	box.set_content_margin_all(PADDING)
	return box


static func inverted_panel() -> StyleBoxFlat:
	var box: StyleBoxFlat = panel(BORDER_WIDTH, INK)
	box.border_color = INK
	return box


static func blank() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


## Apply the ink-on-paper look to a button, inverting on hover so the affordance
## reads without colour.
static func style_button(button: Button, font_size: int = 22) -> void:
	button.add_theme_stylebox_override("normal", panel())
	button.add_theme_stylebox_override("hover", inverted_panel())
	button.add_theme_stylebox_override("pressed", inverted_panel())
	button.add_theme_stylebox_override("focus", panel(BORDER_WIDTH + 1))
	button.add_theme_stylebox_override("disabled", panel(1))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", PAPER)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", FADED)
	button.add_theme_font_size_override("font_size", font_size)


static func style_label(label: Label, font_size: int = 22, colour: Color = INK) -> void:
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", font_size)


static func label(text: String, font_size: int = 22, colour: Color = INK) -> Label:
	var node: Label = Label.new()
	node.text = text
	style_label(node, font_size, colour)
	return node


static func button(text: String, font_size: int = 22) -> Button:
	var node: Button = Button.new()
	node.text = text
	style_button(node, font_size)
	return node


## A full-bleed sheet of paper, grain and all, behind everything else.
static func background(root: Control) -> void:
	var sheet: ColorRect = ColorRect.new()
	sheet.name = "PaperSheet"
	sheet.color = PAPER
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sheet)
	root.move_child(sheet, 0)

	var grain: TextureRect = TextureRect.new()
	grain.name = "PaperGrain"
	grain.texture = load("res://assets/tiles/paper_bg.png") as Texture2D
	grain.stretch_mode = TextureRect.STRETCH_TILE
	grain.set_anchors_preset(Control.PRESET_FULL_RECT)
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grain)
	root.move_child(grain, 1)


## A titled page of the sketchbook.
static func page(title: String) -> VBoxContainer:
	var container: VBoxContainer = VBoxContainer.new()
	container.name = "%sPage" % title.capitalize().replace(" ", "")
	container.add_theme_constant_override("separation", 10)
	var heading: Label = label(title.to_upper(), 30)
	container.add_child(heading)
	container.add_child(rule())
	return container


static func rule() -> Control:
	var line: ColorRect = ColorRect.new()
	line.color = INK
	line.custom_minimum_size = Vector2(0, 3)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line


static func spacer(height: float = 0.0) -> Control:
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	if height <= 0.0:
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return gap


## A full-bleed paper sheet behind a *world* scene, on its own CanvasLayer so it
## neither scrolls with the camera nor picks up the creature's zoom.
static func background_layer(parent: Node) -> CanvasLayer:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "PaperBackground"
	layer.layer = -10
	var holder: Control = Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	background(holder)
	parent.add_child(layer)
	return layer
