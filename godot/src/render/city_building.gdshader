shader_type spatial;

// Neon city buildings (A3): one MultiMesh of boxes. Windows are drawn procedurally from world
// position (no UVs/textures): a grid of dark glass panes, a random subset lit warm or cool.
// Per instance: COLOR = facade tint, INSTANCE_CUSTOM = (seed, sign hue or −1, roof height, 0)
// → some buildings carry a glowing neon sign band below the roof.

uniform vec3 window_warm : source_color = vec3(1.0, 0.78, 0.45);
uniform vec3 window_cool : source_color = vec3(0.55, 0.82, 1.0);
uniform float lit_share = 0.42;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 cdata;
varying vec3 tint;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cdata = INSTANCE_CUSTOM;
	tint = COLOR.rgb;
}

void fragment() {
	vec3 base = tint;
	vec3 emit = vec3(0.0);
	if (abs(wnrm.y) < 0.5) {
		float u = abs(wnrm.x) > abs(wnrm.z) ? wpos.z : wpos.x;
		vec2 cell = vec2(u / 2.6, wpos.y / 3.4);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.2, f.x) * step(f.x, 0.8) * step(0.28, f.y) * step(f.y, 0.78);
		float seed = cdata.x * 91.7;
		float lit = step(1.0 - lit_share, h21(id + seed));
		vec3 wc = mix(window_warm, window_cool, step(0.62, h21(id * 1.7 + seed)));
		base = mix(base, vec3(0.025, 0.03, 0.05), win);
		emit += win * lit * wc * (0.9 + 0.6 * h21(id * 3.1 + seed));
		if (cdata.y >= 0.0) {
			float top = cdata.z;
			float band = step(top - 7.0, wpos.y) * step(wpos.y, top - 3.8);
			vec3 nc = 0.5 + 0.5 * cos(6.2831 * (cdata.y + vec3(0.0, 0.33, 0.67)));
			emit = mix(emit, nc * 2.2, band);
			base = mix(base, nc * 0.25, band);
		}
	}
	ALBEDO = base;
	ROUGHNESS = 0.55;
	EMISSION = emit;
}
