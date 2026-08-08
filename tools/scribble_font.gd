class_name ScribbleFont
extends RefCounted

## A 5x7 bitmap alphabet stamped straight into an `Image` as pure black pixels.
##
## Placeholder art has to label itself (ASSET_SPEC §4) but must still be palette
## exact, and a headless run has no rendering device to rasterise a real font
## with. So: a tiny hand-rolled glyph table, drawn with a per-pixel wobble so the
## result reads as scrawl rather than as clean type (Mandate A2).

const GLYPH_WIDTH: int = 5
const GLYPH_HEIGHT: int = 7

const GLYPHS: Dictionary = {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "11110", "10001", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11100", "10010", "10001", "10001", "10001", "10010", "11100"],
	"E": ["11111", "10000", "11110", "10000", "10000", "10000", "11111"],
	"F": ["11111", "10000", "11110", "10000", "10000", "10000", "10000"],
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
	"H": ["10001", "10001", "11111", "10001", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
	"K": ["10001", "10010", "11100", "10100", "10010", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"_": ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
}


## Width in pixels the given text will occupy at `scale`, including 1-cell gaps.
static func measure(text: String, scale: int) -> int:
	var glyphs: int = text.length()
	if glyphs == 0:
		return 0
	return (glyphs * (GLYPH_WIDTH + 1) - 1) * scale


## Stamp `text` into `image` with its top-left at (`x`, `y`). Every written pixel
## is `#000000ff`. `rng` supplies the per-pixel wobble that keeps it hand-drawn.
static func draw(image: Image, text: String, x: int, y: int, scale: int, rng: RandomNumberGenerator) -> void:
	var cursor: int = x
	for index: int in range(text.length()):
		var character: String = text[index].to_upper()
		var rows: Array = GLYPHS.get(character, GLYPHS["-"]) as Array
		for row: int in range(GLYPH_HEIGHT):
			var bits: String = str(rows[row])
			for column: int in range(GLYPH_WIDTH):
				if bits[column] != "1":
					continue
				var jitter_x: int = rng.randi_range(-1, 1) if scale > 2 else 0
				var jitter_y: int = rng.randi_range(-1, 1) if scale > 2 else 0
				_block(image, cursor + column * scale + jitter_x, y + row * scale + jitter_y, scale)
		cursor += (GLYPH_WIDTH + 1) * scale


static func _block(image: Image, x: int, y: int, size: int) -> void:
	for dy: int in range(size):
		for dx: int in range(size):
			var px: int = x + dx
			var py: int = y + dy
			if px >= 0 and py >= 0 and px < image.get_width() and py < image.get_height():
				image.set_pixel(px, py, Color(0, 0, 0, 1))
