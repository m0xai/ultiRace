shader_type spatial;
render_mode cull_back;
// Vertex-coloured foliage (graphics pass 5): MultiMesh instance tint × baked vertex colours,
// gentle wind sway that grows with height (instances are unit models scaled up, so the local
// y is 0 at the base and 1 at the top). Each instance sways with its own phase.

uniform float sway = 0.035;    // metres per metre of height at the top
uniform float speed = 1.3;

varying vec3 tint;

void vertex() {
	tint = COLOR.rgb;
	vec3 wpos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = wpos.x * 0.11 + wpos.z * 0.07;
	float h = clamp(VERTEX.y, 0.0, 1.2);
	float w = sin(TIME * speed + phase) + 0.4 * sin(TIME * speed * 2.3 + phase * 1.7);
	VERTEX.x += w * sway * h * h;
	VERTEX.z += w * sway * 0.6 * h * h;
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
