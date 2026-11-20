shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

// Ghost variant of car_body.gdshader (Phantom's Phase ULT): same look, translucent.

uniform vec3 glow : source_color = vec3(0.0);
uniform float alpha : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	ALBEDO = COLOR.rgb;
	METALLIC = UV.x;
	ROUGHNESS = max(1.0 - UV.y, 0.08);
	SPECULAR = 0.3;
	EMISSION = glow;
	ALPHA = alpha;
}
