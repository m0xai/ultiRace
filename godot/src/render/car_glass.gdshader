shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

// Car cabin glass (window pass): tinted and see-through head-on so the interior shows, nearly
// opaque and mirror-like at grazing angles (Fresnel), reflecting the sky like real glass.

uniform vec3 tint : source_color = vec3(0.02, 0.03, 0.05);
uniform float alpha_front : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = tint;
	METALLIC = 0.0;
	ROUGHNESS = 0.03;
	SPECULAR = 0.9;
	ALPHA = mix(alpha_front, 0.97, f);
}
