shader_type spatial;
// Asphalt in track space (graphics pass 4): UV = (lateral d, distance s) in metres, UV2.x = local
// half width. Fine aggregate grain + normal detail, darker polished tyre tracks in every lane,
// repair patches, a few cracks and dirt toward the edges. One texture fetch set, mobile friendly.

uniform vec3 base_color : source_color = vec3(0.24, 0.24, 0.27);
uniform sampler2D grain : filter_linear_mipmap, repeat_enable; // seamless noise (R)
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D blotch : filter_linear_mipmap, repeat_enable; // low-frequency seamless noise
uniform float lane_w = 3.6;
uniform float curb_w = 1.2;
uniform float wet = 0.0; // 0 dry … 1 glossy (night map)

varying vec2 tp; // d, s
varying float hw;

void vertex() {
	tp = UV;
	hw = UV2.x;
}

void fragment() {
	float d = tp.x;
	float s = tp.y;
	float g = texture(grain, vec2(d, s) * 0.55).r;      // ~2 m tiles
	float g2 = texture(grain, vec2(d, s) * 2.3 + 0.37).r; // fine aggregate
	float b = texture(blotch, vec2(d, s) * 0.025).r;     // 40 m blotches

	// lanes like the markings: tyre tracks ±0.85 m from each lane centre
	float inner = max(2.0 * hw - 2.0 * curb_w, 1.0);
	float lanes = max(2.0, floor(inner / lane_w + 0.5));
	float lw = inner / lanes;
	float x = d + hw - curb_w;               // 0 at the inner curb edge
	float in_lane = mod(x, lw) - lw * 0.5;   // −lw/2 … lw/2 from the lane centre
	float tyre = 1.0 - smoothstep(0.18, 0.42, abs(abs(in_lane) - 0.85));
	tyre *= smoothstep(0.25, 0.75, texture(blotch, vec2(d * 0.3, s * 0.02)).r);

	// repair patches: rectangular-ish darker areas from thresholded blotch noise
	float pn = texture(blotch, vec2(floor(d / 2.2) * 0.31, s * 0.011)).r;
	float patch = step(0.72, pn) * step(abs(d), hw - curb_w - 0.6);

	// hairline cracks: thin bands where the noise crosses 0.5
	float cn = texture(blotch, vec2(d * 0.21, s * 0.09)).r;
	float crack = (1.0 - smoothstep(0.0, 0.01, abs(cn - 0.5))) * smoothstep(0.62, 0.7, b);

	// dirt toward the edges (just inside the curbs)
	float edge = smoothstep(hw - curb_w - 1.6, hw - curb_w, abs(d));

	vec3 c = base_color;
	c *= 0.84 + 0.26 * g + 0.2 * (g2 - 0.5);
	// aggregate: tiny light and dark stones
	float st = texture(grain, vec2(d, s) * 7.0).r;
	c *= 1.0 + 0.28 * smoothstep(0.66, 0.74, st) - 0.18 * smoothstep(0.36, 0.28, st);
	c *= 0.93 + 0.14 * b;
	c *= 1.0 - 0.09 * tyre;
	c = mix(c, c * 0.78 + vec3(0.01), patch * 0.85);
	c *= 1.0 - 0.45 * crack;
	c = mix(c, c * vec3(1.05, 1.0, 0.92) * 0.9, edge * 0.5);
	ALBEDO = c;
	ROUGHNESS = clamp(0.9 - 0.07 * tyre - 0.06 * patch - wet * 0.5 * (0.6 + 0.4 * b), 0.12, 1.0);
	SPECULAR = 0.35;
	NORMAL_MAP = texture(grain_normal, vec2(d, s) * 1.6).rgb;
	NORMAL_MAP_DEPTH = 0.6;
}
