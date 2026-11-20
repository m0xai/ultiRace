shader_type spatial;
render_mode cull_back;

// Boxy cars (A1 v3): every opaque part is one surface; vertex colour = part colour × ambient
// occlusion baked in Blender (boxkit.bake_ao), UV = (metallic, 1 − roughness) per part.
// Low specular keeps the matte toy look (glossy clear-coat read as plastic).
// glow: effect tint (boost / hit flash), set per car by CarView.

uniform vec3 glow : source_color = vec3(0.0);
uniform float specular_amount : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	ALBEDO = COLOR.rgb;
	METALLIC = UV.x;
	ROUGHNESS = max(1.0 - UV.y, 0.08);
	SPECULAR = specular_amount;
	EMISSION = glow;
}
