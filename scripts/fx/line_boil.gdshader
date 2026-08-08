shader_type canvas_item;
render_mode unshaded;

// The Line Boil (Mandate A3).
//
// Time is floored to `boil_fps` steps, so the hash — and therefore the UV
// offset — only changes 8 to 12 times a second however fast the game is
// running. The wobble is strictly a texture-sampling effect: it never touches
// the node's transform, so physics, movement and the camera stay perfectly
// smooth at full frame rate while the linework stutters like hand-drawn
// animation.
//
// `seed` is randomised per sprite instance (see line_boil.gd) so no two parts
// boil in sync.

uniform float boil_fps : hint_range(8.0, 12.0) = 10.0;
uniform float amplitude_px = 2.5;
uniform float seed = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	// Floored time is the whole trick: within one boil step every frame samples
	// the identical offset, so the drawing holds still and then jumps.
	float step_time = floor(TIME * boil_fps) / boil_fps;

	vec2 wobble = vec2(
		hash21(vec2(step_time, seed)) * 2.0 - 1.0,
		hash21(vec2(step_time + 19.73, seed + 4.21)) * 2.0 - 1.0);

	// Sampling past the edge is safe: part canvases carry a transparent margin
	// and the sampler clamps, so a shifted sprite fades to nothing rather than
	// wrapping. Tiled surfaces repeat, which is what they want anyway.
	COLOR = texture(TEXTURE, UV + wobble * amplitude_px * TEXTURE_PIXEL_SIZE);
}
