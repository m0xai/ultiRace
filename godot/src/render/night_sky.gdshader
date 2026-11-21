shader_type sky;

// Desert night sky: deep blue gradient, faint horizon glow, dense stars with a soft Milky Way
// band, and a big shaded moon drawn where the moonlight (the scene's directional light) comes from.

uniform vec3 top_color : source_color = vec3(0.01, 0.015, 0.06);
uniform vec3 horizon_color : source_color = vec3(0.07, 0.09, 0.2);
uniform vec3 glow_color : source_color = vec3(0.16, 0.16, 0.32);
uniform vec3 ground_color : source_color = vec3(0.03, 0.03, 0.05);
uniform vec3 moon_color : source_color = vec3(0.95, 0.96, 1.0);

void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(horizon_color, top_color, smoothstep(0.0, 0.55, y));
	c += glow_color * exp(-abs(y) * 10.0) * 0.6;
	if (AT_CUBEMAP_PASS == false) {
		// Milky Way: a tilted band of faint glow, denser stars inside it
		float band = exp(-pow(dot(EYEDIR, normalize(vec3(0.35, 0.55, -0.76))) * 4.0, 2.0)) * smoothstep(0.02, 0.3, y);
		float cloud = 0.5 + 0.5 * sin(EYEDIR.x * 31.0 + EYEDIR.z * 17.0) * sin(EYEDIR.y * 23.0 - EYEDIR.x * 11.0);
		c += vec3(0.32, 0.34, 0.5) * band * (0.08 + 0.07 * cloud);
		vec3 d = EYEDIR * 170.0;
		vec3 id = floor(d);
		float h = fract(sin(dot(id, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float thr = mix(0.9955, 0.985, band);
		float star = step(thr, h) * smoothstep(0.42, 0.0, length(fract(d) - 0.5)) * smoothstep(0.03, 0.25, y);
		vec3 tint = mix(vec3(0.85, 0.9, 1.0), vec3(1.0, 0.88, 0.75), fract(h * 31.0));
		c += tint * star * (0.5 + 0.5 * fract(h * 97.0));
	}
	if (LIGHT0_ENABLED) {
		float m = dot(EYEDIR, LIGHT0_DIRECTION);
		float disc = smoothstep(0.99875, 0.999, m);
		// maria: darker blotches across the disc (offset from the centre in the disc plane)
		vec3 off = (EYEDIR - LIGHT0_DIRECTION * m) * 60.0;
		float maria = 0.5 + 0.5 * sin(off.x * 2.1 + off.y * 1.3) * sin(off.z * 1.7 - off.x * 0.9);
		c += moon_color * disc * (0.82 + 0.18 * (1.0 - maria));
		c += moon_color * pow(max(m, 0.0), 220.0) * 0.3;  // halo
	}
	if (y < 0.0) {
		c = mix(c, ground_color, smoothstep(0.0, -0.15, y));
	}
	COLOR = c;
}
