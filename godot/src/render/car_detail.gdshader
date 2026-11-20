shader_type spatial;

// Car "Detail" surface (A1 detail pass): every non-paint, non-glass part of a car (trim, chrome,
// rubber, lamp housings, calipers…) is one surface with vertex colours. The Blender kit stores
// each part's metallic in UV.x and roughness in UV.y (carkit2._surface; glTF flips V, hence
// 1 − UV.y), so chrome stays
// mirror-like and tyres stay matte without extra draw calls.

void fragment() {
	ALBEDO = COLOR.rgb;
	METALLIC = UV.x;
	ROUGHNESS = max(1.0 - UV.y, 0.06);
}
