shader_type spatial;
// Ground (graphics pass 5): TerrainField vertex colours × world-space detail. kind 0 grass,
// 1 snow, 2 sand. Two-scale patchy variation (no flat colour fields), fine speckle, a soft normal
// that catches the light; snow gets cool shading and sparkles, sand gets wind ripples.

uniform int kind = 0;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;      // seamless value noise (R)
uniform sampler2D noise_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float night = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float macro = texture(noise, p * 0.004).r;  // ~250 m patches
	float mid = texture(noise, p * 0.025).r;    // ~40 m
	float fine = texture(noise, p * 0.35).r;    // ~3 m
	float micro = texture(noise, p * 2.1).r;    // speckle
	vec3 c = COLOR.rgb;
	c *= 0.8 + 0.28 * macro + 0.16 * (mid - 0.5);
	float rough = 0.95;
	float spec = 0.2;
	vec3 nm = texture(noise_n, p * 0.6).rgb;
	float nd = 0.35;
	if (kind == 0) {
		// grass: dry/yellow patches, darker lush patches, clover speckle
		vec3 dry = c * vec3(1.18, 1.08, 0.72);
		vec3 lush = c * vec3(0.78, 0.92, 0.75);
		c = mix(c, dry, smoothstep(0.58, 0.8, mid) * 0.55);
		c = mix(c, lush, smoothstep(0.45, 0.25, fine) * 0.4);
		c *= 0.92 + 0.16 * micro;
		nd = 0.45;
	} else if (kind == 1) {
		// snow: very slight blue in the troughs, wind-packed variation, sparkles
		c *= 0.96 + 0.06 * fine;
		c = mix(c, c * vec3(0.86, 0.92, 1.05), smoothstep(0.55, 0.3, mid) * 0.5);
		float glint = smoothstep(0.86, 0.9, texture(noise, p * 5.3 + vec2(TIME * 0.002)).r);
		EMISSION = vec3(glint) * 0.25 * (1.0 - night);
		rough = 0.6;
		spec = 0.45;
		nd = 0.25;
	} else {
		// sand: wind ripples (bent by noise), darker in the troughs
		float warp = texture(noise, p * 0.05).r * 6.0;
		float rip = sin((p.x * 0.8 + p.y * 0.55) * 3.2 + warp * 3.0);
		c *= 0.93 + 0.07 * rip;
		c *= 0.92 + 0.12 * micro;
		nm = normalize(vec3(0.5 + 0.18 * cos((p.x * 0.8 + p.y * 0.55) * 3.2 + warp * 3.0), 0.5, 1.0));
		nd = 0.5;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = spec;
	// bump in world space (the terrain mesh has no UVs/tangents for NORMAL_MAP)
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 bump = (nm.xy * 2.0 - 1.0) * nd;
	nw = normalize(nw + vec3(bump.x, 0.0, bump.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
