shader_type canvas_item;
// ----------------------------------------------------------------------------
// PS1 / VHS screen-space post-process.
//
// Apply this to a full-screen ColorRect (with a ShaderMaterial) sitting at the
// BOTTOM of the UI CanvasLayer. It reads the already-rendered frame via the
// screen texture, then:
//   1. snaps UVs to a low-resolution grid (chunky PS1 pixels),
//   2. quantizes colours to a limited palette,
//   3. adds horizontal chromatic aberration (VHS colour bleed),
//   4. lays down rolling scanlines and animated grain.
//
// Crisp HUD elements (crosshair, prompt) are drawn ABOVE this rect, so they
// stay sharp while the 3D world gets the retro treatment.
// ----------------------------------------------------------------------------

// `filter_nearest` keeps every fetch blocky — no bilinear smoothing.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Virtual framebuffer size. Lower = chunkier pixels. 320x240 ~ PS1.
uniform vec2 pixel_resolution = vec2(320.0, 240.0);
// Horizontal RGB split, in UV units.
uniform float aberration : hint_range(0.0, 0.01) = 0.0015;
// How dark the scanline troughs get.
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.15;
// Strength of the animated VHS grain.
uniform float noise_strength : hint_range(0.0, 0.5) = 0.05;
// Number of steps per colour channel (lower = more banding / retro).
uniform float color_levels = 32.0;

// Cheap hash-based pseudo-random value in [0, 1).
float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// 1. Pixelation: quantize the screen UV to the virtual framebuffer grid.
	vec2 uv = floor(SCREEN_UV * pixel_resolution) / pixel_resolution;

	// 2. Chromatic aberration: sample R and B with a small horizontal offset.
	vec2 offset = vec2(aberration, 0.0);
	vec3 col;
	col.r = texture(screen_texture, uv + offset).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - offset).b;

	// 3. Colour quantization for that limited-palette, low-bit look.
	col = floor(col * color_levels) / color_levels;

	// 4. Scanlines based on the true (un-pixelated) vertical position.
	float scan = 0.5 + 0.5 * sin(SCREEN_UV.y * pixel_resolution.y * 3.14159265);
	col *= 1.0 - scanline_strength * scan;

	// 5. Animated grain.
	float n = rand(uv + vec2(TIME * 0.10, TIME * 0.13));
	col += (n - 0.5) * noise_strength;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
