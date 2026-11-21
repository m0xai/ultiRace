shader_type sky;

// Canyon night sky (A3): deep blue gradient, faint horizon glow, stars and a moon drawn where the
// moonlight (the scene's directional light) comes from.

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
		vec3 d = EYEDIR * 160.0;
		vec3 id = floor(d);
		float h = fract(sin(dot(id, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float star = step(0.9962, h) * smoothstep(0.42, 0.0, length(fract(d) - 0.5)) * smoothstep(0.03, 0.25, y);
		c += vec3(0.9, 0.92, 1.0) * star * (0.6 + 0.4 * fract(h * 97.0));
	}
	if (LIGHT0_ENABLED) {
		float m = dot(EYEDIR, LIGHT0_DIRECTION);
		c += moon_color * smoothstep(0.99935, 0.99955, m);  // disc
		c += moon_color * pow(max(m, 0.0), 300.0) * 0.25;  // halo
	}
	if (y < 0.0) {
		c = mix(c, ground_color, smoothstep(0.0, -0.15, y));
	}
	COLOR = c;
}
