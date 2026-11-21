class_name TerrainField
extends RefCounted

## Procedural terrain around a track (A3 world pass 3). Height at (x, z) depends on the distance
## to the nearest road point, so the ground never rises through the road:
##   "desert": flat sand beside the road, then low dune ridges that build up gently further out
##             (nothing tall near the road: the figure-8 crosses itself, steep walls hung over it)
##   "hills":  gentle rolling grass hills rising away from the road
##   "snow":   snowy slopes that follow the (climbing) road nearby and roll into hills further out
## Also gives a colour per point (strata, grass/rock, snow/rock by slope) for vertex colours.

var kind: String
var floor_y: float
var _pts: PackedVector4Array = PackedVector4Array() # x, z, road y, half width
var _buckets: Dictionary = {} # Vector2i → PackedInt32Array
const BUCKET: float = 40.0
var _noise: FastNoiseLite
var _detail: FastNoiseLite


func _init(tr: Track, terrain_kind: String, base_y: float, seed_: int) -> void:
	kind = terrain_kind
	floor_y = base_y
	var s: float = 0.0
	while s < tr.length:
		var smp: Track.Sample = tr.at(s)
		var i: int = _pts.size()
		_pts.append(Vector4(smp.px, smp.pz, smp.py, smp.half_width))
		var key: Vector2i = Vector2i(floori(smp.px / BUCKET), floori(smp.pz / BUCKET))
		# packed arrays are values: append to the stored array, then store it back
		var arr: PackedInt32Array = _buckets.get(key, PackedInt32Array())
		arr.append(i)
		_buckets[key] = arr
		s += 3.0
	_noise = FastNoiseLite.new()
	_noise.seed = seed_
	_noise.frequency = 0.006
	_noise.fractal_octaves = 3
	_detail = FastNoiseLite.new()
	_detail.seed = seed_ + 7
	_detail.frequency = 0.05
	_detail.fractal_octaves = 2


## (distance to the road centreline, road y, half width) of the nearest road sample.
func nearest(x: float, z: float) -> Vector3:
	var kx: int = floori(x / BUCKET)
	var kz: int = floori(z / BUCKET)
	var best: float = INF
	var by: float = floor_y
	var bhw: float = 10.0
	for ring: int in 4:
		for dx: int in range(-ring, ring + 1):
			for dz: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var key: Vector2i = Vector2i(kx + dx, kz + dz)
				if not _buckets.has(key):
					continue
				for i: int in _buckets[key] as PackedInt32Array:
					var p: Vector4 = _pts[i]
					var d2: float = (p.x - x) * (p.x - x) + (p.y - z) * (p.y - z)
					if d2 < best:
						best = d2
						by = p.z
						bhw = p.w
		if best < INF and sqrt(best) < float(ring) * BUCKET:
			break
	if best == INF:
		return Vector3(9999.0, floor_y, 10.0)
	return Vector3(sqrt(best), by, bhw)


func height(x: float, z: float) -> float:
	var n: Vector3 = nearest(x, z)
	var e: float = n.x - n.z # metres beyond the road edge
	var road_y: float = n.y
	var h: float = floor_y
	var nv: float = _noise.get_noise_2d(x, z) * 0.5 + 0.5 # 0..1
	match kind:
		"desert":
			# dune ridges across the wind (sharp crests, wide troughs), bent by noise; height
			# grows with the distance from the road and a slow swell further out
			var warp: float = _noise.get_noise_2d(x * 0.7 + 90.0, z * 0.7) * 45.0
			var ridge: float = pow(1.0 - absf(sin((x * 0.8 + z * 0.6 + warp) * 0.045)), 2.0)
			var amp: float = (3.0 + 8.0 * nv) * smoothstep(12.0, 70.0, e)
			h = floor_y + amp * ridge + smoothstep(60.0, 260.0, e) * 12.0 * nv
			h += _detail.get_noise_2d(x, z) * 0.25
		"snow":
			var hills: float = floor_y + smoothstep(10.0, 140.0, e) * (8.0 + 26.0 * nv) + _detail.get_noise_2d(x, z) * 1.2
			var near: float = road_y - 0.7
			h = lerpf(near, maxf(hills, near - 6.0), smoothstep(4.0, 55.0, e))
		_:
			h = floor_y + smoothstep(8.0, 110.0, e) * (8.0 + 26.0 * nv) + _detail.get_noise_2d(x, z) * smoothstep(0.0, 25.0, e) * 1.4
	if e < 6.0: # never above the road nearby
		h = minf(h, road_y - 0.45)
	return h


## Vertex colour for a point at height h with surface slope (0 flat … 1 vertical).
func color_at(x: float, z: float, h: float, slope: float) -> Color:
	var v: float = _detail.get_noise_2d(x * 2.0, z * 2.0) * 0.5 + 0.5
	match kind:
		"desert":
			# warm sand; crests catch the moon, troughs and gravel patches are darker
			var t: float = clampf((h - floor_y) / 9.0, 0.0, 1.0)
			var sand: Color = Color(0.56, 0.4, 0.27).lerp(Color(0.5, 0.35, 0.23), v)
			sand = sand.lerp(Color(0.72, 0.55, 0.38), t * 0.6)
			var gravel: float = smoothstep(0.25, 0.45, _noise.get_noise_2d(x * 3.5 + 40.0, z * 3.5))
			sand = sand.lerp(Color(0.33, 0.26, 0.21), gravel * 0.55)
			return sand.darkened(0.25 * smoothstep(0.25, 0.6, slope))
		"snow":
			var snow: Color = Color(0.93, 0.95, 0.99).lerp(Color(0.86, 0.9, 0.97), v)
			var rock: Color = Color(0.42, 0.44, 0.5).lerp(Color(0.5, 0.5, 0.55), v)
			return snow.lerp(rock, smoothstep(0.45, 0.7, slope))
		_:
			var grass: Color = Color(0.36, 0.6, 0.25).lerp(Color(0.46, 0.66, 0.28), v)
			var dry: Color = Color(0.58, 0.6, 0.33)
			var rock2: Color = Color(0.5, 0.47, 0.42)
			var c2: Color = grass.lerp(dry, smoothstep(0.55, 0.9, _noise.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5) * 0.6)
			return c2.lerp(rock2, smoothstep(0.5, 0.8, slope))
