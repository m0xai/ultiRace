shader_type sky;

// Neon night sky (A3): vertical gradient, warm city glow along the horizon and small stars.

uniform vec3 top_color : source_color = vec3(0.01, 0.01, 0.05);
uniform vec3 horizon_color : source_color = vec3(0.22, 0.07, 0.32);
uniform vec3 glow_color : source_color = vec3(0.9, 0.3, 0.6);
uniform vec3 ground_color : source_color = vec3(0.03, 0.03, 0.06);

void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(horizon_color, top_color, smoothstep(0.0, 0.55, y));
	c += glow_color * exp(-abs(y) * 14.0) * 0.55;
	if (AT_CUBEMAP_PASS == false) {
		vec3 d = EYEDIR * 160.0;
		vec3 id = floor(d);
		float h = fract(sin(dot(id, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float star = step(0.9965, h) * smoothstep(0.42, 0.0, length(fract(d) - 0.5)) * smoothstep(0.04, 0.25, y);
		c += vec3(0.9, 0.92, 1.0) * star * (0.6 + 0.4 * fract(h * 97.0));
	}
	if (y < 0.0) {
		c = mix(c, ground_color, smoothstep(0.0, -0.15, y));
	}
	COLOR = c;
}
