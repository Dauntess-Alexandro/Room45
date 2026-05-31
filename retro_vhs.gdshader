shader_type canvas_item;
// ----------------------------------------------------------------------------
// Soft retro post-process (Voices of the Void–style).
//
// Mild downscale + light colour crunch, not heavy PS1/VHS crunch.
// HUD drawn above this rect stays sharp.
// ----------------------------------------------------------------------------

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// Virtual framebuffer size. Higher = cleaner (512x288 is a good VotV-ish default).
uniform vec2 pixel_resolution = vec2(960.0, 540.0);
// Horizontal RGB split, in UV units.
uniform float aberration : hint_range(0.0, 0.01) = 0.00035;
// How dark the scanline troughs get.
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.06;
// Strength of the animated grain.
uniform float noise_strength : hint_range(0.0, 0.5) = 0.015;
// Colour steps per channel (higher = smoother gradients).
uniform float color_levels = 64.0;
// Blend between full-res source (0) and retro-treated (1).
uniform float retro_mix : hint_range(0.0, 1.0) = 0.55;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 col_hi = texture(screen_texture, SCREEN_UV).rgb;

	// Pixel snap at reduced resolution (centre of each virtual pixel).
	vec2 uv = (floor(SCREEN_UV * pixel_resolution) + 0.5) / pixel_resolution;

	vec2 offset = vec2(aberration, 0.0);
	vec3 col_lo;
	col_lo.r = texture(screen_texture, uv + offset).r;
	col_lo.g = texture(screen_texture, uv).g;
	col_lo.b = texture(screen_texture, uv - offset).b;
	col_lo = floor(col_lo * color_levels) / color_levels;

	float scan = 0.5 + 0.5 * sin(SCREEN_UV.y * pixel_resolution.y * 3.14159265);
	col_lo *= 1.0 - scanline_strength * scan;

	float n = rand(uv + vec2(TIME * 0.08, TIME * 0.11));
	col_lo += (n - 0.5) * noise_strength;

	vec3 col = mix(col_hi, col_lo, retro_mix);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
