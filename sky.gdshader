shader_type sky;
render_mode use_debanding;

// Set every frame by sun_controller.gd
uniform vec3 sun_dir = vec3(0.0, 0.3, 1.0);   // direction TOWARD the sun
uniform vec3 moon_dir = vec3(0.0, 0.3, -1.0); // direction TOWARD the moon
uniform float daylight : hint_range(0.0, 1.0) = 1.0;

uniform vec3 day_zenith : source_color = vec3(0.17, 0.35, 0.72);
uniform vec3 day_horizon : source_color = vec3(0.64, 0.76, 0.93);
uniform vec3 night_zenith : source_color = vec3(0.010, 0.015, 0.040);
uniform vec3 night_horizon : source_color = vec3(0.030, 0.050, 0.100);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 moon_color : source_color = vec3(0.70, 0.78, 0.95);
uniform float sun_size : hint_range(0.0, 0.2) = 0.015;
uniform float moon_size : hint_range(0.0, 0.2) = 0.030;
uniform float star_amount : hint_range(0.9, 1.0) = 0.985; // higher = fewer stars
uniform float milky_way_strength : hint_range(0.0, 1.0) = 0.6;
uniform vec3 ground_color : source_color = vec3(0.10, 0.09, 0.08); // below the horizon

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);

	// --- Day gradient + sun ---
	vec3 day = mix(day_horizon, day_zenith, pow(up, 0.6));
	float sd = dot(dir, normalize(sun_dir));
	float sun_disk = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.5, sd);
	float sun_glow = pow(max(sd, 0.0), 120.0) * 0.6;
	day += sun_color * (sun_disk * 8.0 + sun_glow);

	// --- Night gradient + stars + Milky Way + moon ---
	vec3 night = mix(night_horizon, night_zenith, pow(up, 0.8));

	// Stars: quantise the direction, random per cell, only above the horizon.
	vec3 cell = floor(dir * 250.0);
	float rnd = hash13(cell);
	float star = step(star_amount, rnd);
	float twinkle = 0.65 + 0.35 * sin(TIME * 3.0 + rnd * 120.0);
	float star_fade = smoothstep(0.02, 0.30, dir.y);
	night += vec3(1.0) * (star * twinkle * star_fade);

	// Milky Way: a soft noisy band across the sky.
	float band = smoothstep(0.22, 0.0, abs(dot(dir, normalize(vec3(0.7, 0.25, 0.6)))));
	float band_noise = hash13(floor(dir * 70.0));
	night += vec3(0.05, 0.06, 0.10) * band * band_noise * milky_way_strength * star_fade;

	// Moon: bright disk + soft glow.
	float md = dot(dir, normalize(moon_dir));
	float moon_disk = smoothstep(1.0 - moon_size, 1.0 - moon_size * 0.5, md);
	float moon_glow = pow(max(md, 0.0), 180.0) * 0.4;
	night += moon_color * (moon_disk * 3.0 + moon_glow);

	vec3 sky_col = mix(night, day, daylight);

	// Below the horizon, show ground (darker at night), not blue sky — so
	// downward reflections on objects read neutral, never blue.
	vec3 ground = ground_color * (0.25 + 0.75 * daylight);
	float horizon = smoothstep(-0.03, 0.04, dir.y);
	COLOR = mix(ground, sky_col, horizon);
}
