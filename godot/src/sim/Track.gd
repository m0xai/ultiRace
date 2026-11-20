class_name Track
extends RefCounted

## Mirror of internal/track (Go): closed uniform Catmull-Rom track with an arc-length table.
## See the Go file for conventions (s, d, Normal, signed curvature κ). Keep the arithmetic
## identical; gamedata/fixtures/track_*.json is checked by test/track_conformance_test.gd.


class Sample:
	extends RefCounted
	var s: float = 0.0
	var px: float = 0.0
	var py: float = 0.0
	var pz: float = 0.0
	var tx: float = 0.0
	var ty: float = 0.0
	var tz: float = 0.0
	var nx: float = 0.0
	var ny: float = 0.0
	var nz: float = 0.0
	var curvature: float = 0.0
	var half_width: float = 0.0
	var bank: float = 0.0


var id: String = ""
var length: float = 0.0
var ramps: Array[Dictionary] = []
var theme: String = ""
var display_name: String = ""

var _pts: Array[PackedFloat64Array] = []
var _k: int = 64
var _sample_s: PackedFloat64Array = PackedFloat64Array()


static func load_map(map_id: String) -> Track:
	var bal: Dictionary = GameData.balance()
	var tp: Dictionary = bal["track"] as Dictionary
	return Track.new(GameData.map_data(map_id), int(tp["arcSamplesPerSegment"]))


func _init(map: Dictionary, samples_per_segment: int) -> void:
	id = map["id"] as String
	theme = map.get("theme", "") as String
	display_name = map.get("name", id) as String
	for p: Variant in map["points"] as Array:
		var arr: Array = p as Array
		_pts.append(PackedFloat64Array([float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]), float(arr[4])]))
	for r: Variant in map.get("ramps", []) as Array:
		var rd: Dictionary = r as Dictionary
		ramps.append({"s": float(rd["s"]), "length": float(rd["length"]), "vy": float(rd["vy"]), "height": float(rd["height"])})
	_k = samples_per_segment
	var n: int = _pts.size()
	_sample_s.resize(n * _k + 1)
	var acc: float = 0.0
	var prev: PackedFloat64Array = _pos_at(0, 0.0)
	for seg: int in n:
		for j: int in _k:
			var idx: int = seg * _k + j
			if idx > 0:
				var p: PackedFloat64Array = _pos_at(seg, float(j) / float(_k))
				acc += _dist(p, prev)
				prev = p
			_sample_s[idx] = acc
	var p0: PackedFloat64Array = _pos_at(0, 0.0)
	acc += _dist(p0, prev)
	_sample_s[n * _k] = acc
	length = acc


static func _dist(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var dx: float = a[0] - b[0]
	var dy: float = a[1] - b[1]
	var dz: float = a[2] - b[2]
	return sqrt(dx * dx + dy * dy + dz * dz)


func _ctrl(i: int) -> PackedFloat64Array:
	var n: int = _pts.size()
	return _pts[((i % n) + n) % n]


func _pos_at(seg: int, u: float) -> PackedFloat64Array:
	var p0: PackedFloat64Array = _ctrl(seg - 1)
	var p1: PackedFloat64Array = _ctrl(seg)
	var p2: PackedFloat64Array = _ctrl(seg + 1)
	var p3: PackedFloat64Array = _ctrl(seg + 2)
	return PackedFloat64Array([
		MathX.catmull_rom(p0[0], p1[0], p2[0], p3[0], u),
		MathX.catmull_rom(p0[1], p1[1], p2[1], p3[1], u),
		MathX.catmull_rom(p0[2], p1[2], p2[2], p3[2], u),
	])


## Returns [segment, u] for any s (wraps).
func _locate(s: float) -> Array:
	s = MathX.wrap_pos(s, length)
	# largest idx with sample_s[idx] <= s  (Go: sort.Search(… > s) - 1)
	var idx: int = _sample_s.bsearch(s, false) - 1
	var last: int = _sample_s.size() - 2
	if idx < 0:
		idx = 0
	elif idx > last:
		idx = last
	var s0: float = _sample_s[idx]
	var s1: float = _sample_s[idx + 1]
	var frac: float = 0.0
	if s1 > s0:
		frac = (s - s0) / (s1 - s0)
	var seg: int = idx / _k
	var u: float = (float(idx % _k) + frac) / float(_k)
	return [seg, u]


func at(s: float) -> Sample:
	var loc: Array = _locate(s)
	var seg: int = loc[0] as int
	var u: float = loc[1] as float
	var p0: PackedFloat64Array = _ctrl(seg - 1)
	var p1: PackedFloat64Array = _ctrl(seg)
	var p2: PackedFloat64Array = _ctrl(seg + 1)
	var p3: PackedFloat64Array = _ctrl(seg + 2)
	var out: Sample = Sample.new()
	out.s = MathX.wrap_pos(s, length)
	out.px = MathX.catmull_rom(p0[0], p1[0], p2[0], p3[0], u)
	out.py = MathX.catmull_rom(p0[1], p1[1], p2[1], p3[1], u)
	out.pz = MathX.catmull_rom(p0[2], p1[2], p2[2], p3[2], u)
	var dx: float = MathX.catmull_rom_d1(p0[0], p1[0], p2[0], p3[0], u)
	var dy: float = MathX.catmull_rom_d1(p0[1], p1[1], p2[1], p3[1], u)
	var dz: float = MathX.catmull_rom_d1(p0[2], p1[2], p2[2], p3[2], u)
	var ddx: float = MathX.catmull_rom_d2(p0[0], p1[0], p2[0], p3[0], u)
	var ddz: float = MathX.catmull_rom_d2(p0[2], p1[2], p2[2], p3[2], u)
	var l: float = sqrt(dx * dx + dy * dy + dz * dz)
	if l > 0.0:
		out.tx = dx / l
		out.ty = dy / l
		out.tz = dz / l
	var hl: float = sqrt(dx * dx + dz * dz)
	out.nx = dz / hl
	out.ny = 0.0
	out.nz = -dx / hl
	out.curvature = (ddx * dz - ddz * dx) / (hl * hl * hl)
	out.half_width = (p1[3] + (p2[3] - p1[3]) * u) / 2.0
	out.bank = p1[4] + (p2[4] - p1[4]) * u
	return out


func curvature(s: float) -> float:
	return at(s).curvature


func half_width(s: float) -> float:
	var loc: Array = _locate(s)
	var seg: int = loc[0] as int
	var u: float = loc[1] as float
	var p1: PackedFloat64Array = _ctrl(seg)
	var p2: PackedFloat64Array = _ctrl(seg + 1)
	return (p1[3] + (p2[3] - p1[3]) * u) / 2.0


## Track-space (s, d, y above road) → world position (bank tilts the lateral axis; render only).
## Rendering only: height of the ramp surface at s (0 off ramps) and its slope (rise per metre).
## Physics keeps grounded cars at y = 0 on the wedge and launches them from the lip.
func ramp_height(s: float) -> float:
	for r: Dictionary in ramps:
		var u: float = MathX.wrap_delta(float(r["s"]), s, length) / float(r["length"])
		if u >= 0.0 and u <= 1.0:
			return float(r["height"]) * u
	return 0.0


func ramp_slope(s: float) -> float:
	for r: Dictionary in ramps:
		var u: float = MathX.wrap_delta(float(r["s"]), s, length) / float(r["length"])
		if u >= 0.0 and u <= 1.0:
			return float(r["height"]) / float(r["length"])
	return 0.0


func world(s: float, d: float, y: float) -> Vector3:
	var smp: Sample = at(s)
	var cb: float = cos(smp.bank)
	var sb: float = sin(smp.bank)
	var lx: float = smp.nx * cb
	var ly: float = sb
	var lz: float = smp.nz * cb
	return Vector3(smp.px + lx * d, smp.py + ly * d + y, smp.pz + lz * d)


## Unit lateral axis (with bank) at s, for building geometry.
func lateral(s: float) -> Vector3:
	var smp: Sample = at(s)
	return Vector3(smp.nx * cos(smp.bank), sin(smp.bank), smp.nz * cos(smp.bank))
