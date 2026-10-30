shader_type canvas_item;
render_mode unshaded, blend_mix;

// Soft bokeh starfield (Neon Stack cyan).
// Local VERTEX pixels keep discs circular; point list avoids cell-edge squares.
// Polynomial falloff stays stable on GLES3 mediump (exp can brick into blocks).
uniform vec2 viewport_size = vec2(1280.0, 800.0);
uniform float horizon_y = 300.0;
uniform float time = 0.0;

varying vec2 v_pixel;

void vertex() {
	v_pixel = VERTEX;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float soft_disc(float dist, float radius) {
	float t = clamp(1.0 - dist / max(radius, 0.001), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

vec3 star_at(float fi, vec2 pixel, float hy, float width) {
	float ux = hash21(vec2(fi, 11.3));
	float vy = hash21(vec2(fi * 3.17, 7.71));
	float size_n = hash21(vec2(fi, 19.2));

	// Keep whole halo above the floor clip so orbs are not sliced by a hard horizon seam.
	float margin = 38.0;
	float y_span = max(hy - margin, 1.0);
	float y_t = 1.0 - pow(1.0 - vy, 2.5);
	vec2 sp = vec2(ux * width, y_t * y_span);

	float star_near = clamp(sp.y / max(hy, 1.0), 0.0, 1.0);
	float radius = mix(1.25, 14.0, pow(star_near, 2.0) * mix(0.4, 1.0, size_n));
	float dist = distance(pixel, sp);
	float core = soft_disc(dist, radius);
	float halo = soft_disc(dist, radius * 2.2) * 0.4;
	float tw = 0.86 + 0.14 * sin(time * (1.25 + size_n) + fi);
	float strength = (core * 0.9 + halo) * tw * mix(0.22, 1.05, star_near * star_near);

	vec3 cool = vec3(0.118, 0.784, 1.0);
	vec3 hot = vec3(0.557, 0.969, 1.0);
	vec3 white = vec3(0.92, 0.98, 1.0);
	vec3 tint = mix(cool, mix(hot, white, size_n), star_near);
	return tint * strength;
}

void fragment() {
	vec2 pixel = v_pixel;
	float hy = max(horizon_y, 1.0);
	float width = max(viewport_size.x, 1.0);
	// Opaque sky only; no mid-glow alpha cut (floor draws below hy in main).
	float above = step(pixel.y, hy);

	float near = clamp(pixel.y / hy, 0.0, 1.0);
	vec3 sky_top = vec3(0.02, 0.043, 0.071);
	// Match floor fill Color("071018") so the sky/floor join does not flash a band.
	vec3 sky_horizon = vec3(0.027, 0.063, 0.094);
	vec3 sky = mix(sky_top, sky_horizon, near * near);
	sky += vec3(0.118, 0.784, 1.0) * (smoothstep(0.62, 1.0, near) * 0.08);

	vec3 glow = vec3(0.0);
	glow += star_at(1.0, pixel, hy, width);
	glow += star_at(2.0, pixel, hy, width);
	glow += star_at(3.0, pixel, hy, width);
	glow += star_at(4.0, pixel, hy, width);
	glow += star_at(5.0, pixel, hy, width);
	glow += star_at(6.0, pixel, hy, width);
	glow += star_at(7.0, pixel, hy, width);
	glow += star_at(8.0, pixel, hy, width);
	glow += star_at(9.0, pixel, hy, width);
	glow += star_at(10.0, pixel, hy, width);
	glow += star_at(11.0, pixel, hy, width);
	glow += star_at(12.0, pixel, hy, width);
	glow += star_at(13.0, pixel, hy, width);
	glow += star_at(14.0, pixel, hy, width);
	glow += star_at(15.0, pixel, hy, width);
	glow += star_at(16.0, pixel, hy, width);
	glow += star_at(17.0, pixel, hy, width);
	glow += star_at(18.0, pixel, hy, width);
	glow += star_at(19.0, pixel, hy, width);
	glow += star_at(20.0, pixel, hy, width);
	glow += star_at(21.0, pixel, hy, width);
	glow += star_at(22.0, pixel, hy, width);
	glow += star_at(23.0, pixel, hy, width);
	glow += star_at(24.0, pixel, hy, width);
	glow += star_at(25.0, pixel, hy, width);
	glow += star_at(26.0, pixel, hy, width);
	glow += star_at(27.0, pixel, hy, width);
	glow += star_at(28.0, pixel, hy, width);
	glow += star_at(29.0, pixel, hy, width);
	glow += star_at(30.0, pixel, hy, width);
	glow += star_at(31.0, pixel, hy, width);
	glow += star_at(32.0, pixel, hy, width);
	glow += star_at(33.0, pixel, hy, width);
	glow += star_at(34.0, pixel, hy, width);
	glow += star_at(35.0, pixel, hy, width);
	glow += star_at(36.0, pixel, hy, width);
	glow += star_at(37.0, pixel, hy, width);
	glow += star_at(38.0, pixel, hy, width);
	glow += star_at(39.0, pixel, hy, width);
	glow += star_at(40.0, pixel, hy, width);
	glow += star_at(41.0, pixel, hy, width);
	glow += star_at(42.0, pixel, hy, width);
	glow += star_at(43.0, pixel, hy, width);
	glow += star_at(44.0, pixel, hy, width);
	glow += star_at(45.0, pixel, hy, width);
	glow += star_at(46.0, pixel, hy, width);
	glow += star_at(47.0, pixel, hy, width);
	glow += star_at(48.0, pixel, hy, width);
	glow += star_at(49.0, pixel, hy, width);
	glow += star_at(50.0, pixel, hy, width);
	glow += star_at(51.0, pixel, hy, width);
	glow += star_at(52.0, pixel, hy, width);
	glow += star_at(53.0, pixel, hy, width);
	glow += star_at(54.0, pixel, hy, width);
	glow += star_at(55.0, pixel, hy, width);
	glow += star_at(56.0, pixel, hy, width);
	glow += star_at(57.0, pixel, hy, width);
	glow += star_at(58.0, pixel, hy, width);
	glow += star_at(59.0, pixel, hy, width);
	glow += star_at(60.0, pixel, hy, width);
	glow += star_at(61.0, pixel, hy, width);
	glow += star_at(62.0, pixel, hy, width);
	glow += star_at(63.0, pixel, hy, width);
	glow += star_at(64.0, pixel, hy, width);
	glow += star_at(65.0, pixel, hy, width);
	glow += star_at(66.0, pixel, hy, width);
	glow += star_at(67.0, pixel, hy, width);
	glow += star_at(68.0, pixel, hy, width);
	glow += star_at(69.0, pixel, hy, width);
	glow += star_at(70.0, pixel, hy, width);
	glow += star_at(71.0, pixel, hy, width);
	glow += star_at(72.0, pixel, hy, width);

	COLOR = vec4((sky + glow) * above, above);
}
