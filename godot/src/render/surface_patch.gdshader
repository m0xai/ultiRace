shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
// Road surface patches (graphics pass 4). UV = (across −1…1, along 0…1); UV2 = world metres
// (d, s) for detail. kind: 0 ice (frosted, cracked, bright rim), 1 water (mirror puddle with
// moving ripples), 2 oil (black film with a rainbow sheen). Soft, irregular edges.

uniform int kind = 0;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_normal : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec2 pu;
varying vec2 wm;

void vertex() {
	pu = UV;
	wm = UV2;
}

void fragment() {
	float n = texture(noise, wm * 0.18).r;
	float n2 = texture(noise, wm * 0.9 + 0.5).r;
	// irregular outline: a rounded rectangle (covers the physics footprint, which is a
	// rectangle) whose edge wobbles with two noise scales
	vec2 q = abs(vec2(pu.x, (pu.y - 0.5) * 2.0));
	float r = pow(pow(q.x, 4.0) + pow(q.y, 4.0), 0.25);
	float wob = 0.3 * (texture(noise, wm * 0.45).r - 0.5) + 0.18 * (n2 - 0.5);
	float shape = 1.0 - smoothstep(0.8 + wob, 0.95 + wob, r);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	if (kind == 0) {
		// ice: milky blue-white, darker clear patches, crack lines, bright frosty rim
		float clear = smoothstep(0.45, 0.7, n2);
		float crack = 1.0 - smoothstep(0.0, 0.025, abs(texture(noise, wm * 0.35 + 3.1).r - 0.5));
		vec3 c = mix(vec3(0.62, 0.78, 0.92), vec3(0.3, 0.45, 0.6), clear);
		c = mix(c, vec3(0.95, 0.98, 1.0), crack * 0.9);
		float rim = (1.0 - smoothstep(0.0, 0.5, shape)) * shape;
		c = mix(c, vec3(0.95, 0.98, 1.0), clamp(rim * 2.0, 0.0, 1.0));
		ALBEDO = c;
		ROUGHNESS = mix(0.12, 0.02, clear);
		SPECULAR = 1.0;
		ALPHA = shape * (0.62 + 0.3 * crack + 0.25 * fres);
		NORMAL_MAP = texture(ripple_normal, wm * 0.4).rgb;
		NORMAL_MAP_DEPTH = 0.25;
	} else if (kind == 1) {
		// water: dark, mirror-smooth, slow ripples; muddy rim
		vec2 t = vec2(TIME * 0.05, TIME * 0.035);
		vec3 nm = normalize(texture(ripple_normal, wm * 0.5 + t).rgb + texture(ripple_normal, wm * 0.37 - t).rgb - 1.0);
		ALBEDO = mix(vec3(0.02, 0.025, 0.03), vec3(0.08, 0.07, 0.06), (1.0 - smoothstep(0.0, 0.5, shape)) * 0.8);
		ROUGHNESS = 0.06;
		METALLIC = 0.0;
		SPECULAR = 1.0;
		NORMAL_MAP = nm * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 0.35;
		ALPHA = shape * (0.6 + 0.35 * fres);
	} else {
		// oil: near-black film, thin-film rainbow sheen that shifts with view angle
		float h = fract(n * 2.5 + n2 * 0.7 + dot(VIEW, vec3(0.0, 0.6, 0.4)) * 1.4);
		vec3 rainbow = 0.5 + 0.5 * cos(6.2832 * (h + vec3(0.0, 0.33, 0.67)));
		float sheen = smoothstep(0.35, 0.8, n2) * 0.35;
		ALBEDO = mix(vec3(0.015, 0.015, 0.02), rainbow * 0.5, sheen);
		ROUGHNESS = 0.08;
		METALLIC = 0.3;
		SPECULAR = 0.9;
		ALPHA = shape * 0.92;
	}
}
