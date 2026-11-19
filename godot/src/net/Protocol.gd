class_name Protocol
extends RefCounted

## Mirror of internal/protocol (Go). Message builders return Dictionaries that encode to the
## exact JSON the server expects; snapshots are decoded from the binary format in codec.go.
## Checked against gamedata/fixtures/protocol/messages.json by test/protocol_conformance_test.gd.

const VERSION: int = 1

const SNAP_KIND: int = 1
const SNAP_HEADER: int = 10
const SNAP_CAR_BYTES: int = 18
const QS: float = 0.01
const QYAW: float = 0.0001
const QSPEED: float = 0.01
const FLAG_FINISHED: int = 1
const POS_SHIFT: int = 12 # flags bits 12–15: race position from the server (0 = unknown)
const CHARGE_SHIFT: int = 8 # flags bits 8–11: ULT charge 0–15 (15 = ready)
# effect bits (internal/sim/effects.go)
const EFF_SPINOUT: int = 1 << 1
const EFF_SLOW: int = 1 << 2
const EFF_SLIDE: int = 1 << 3
const EFF_BOOST: int = 1 << 4
const EFF_GHOST: int = 1 << 5
const EFF_IMMUNE: int = 1 << 6
const EFF_DRAFT: int = 1 << 7
const PROJ_TORNADO: int = 1
const TRAP_ICE: int = 1
const TRAP_GOO: int = 2


static func charge_of(flags: int) -> float:
	return float((flags >> CHARGE_SHIFT) & 0xF) / 15.0


static func pos_of(flags: int) -> int:
	return (flags >> POS_SHIFT) & 0xF

# client → server
const T_HELLO: String = "hello"
const T_READY: String = "ready"
const T_SETTINGS: String = "settings"
const T_START: String = "start"
const T_KICK: String = "kick"
const T_PREVIEW: String = "preview"
const T_LOCK: String = "lock"
const T_IN: String = "in"
const T_REMATCH: String = "rematch"
const T_REPORT: String = "report"
const T_PING: String = "ping"
const T_LEAVE: String = "leave"
# server → client
const T_WELCOME: String = "welcome"
const T_ROOM: String = "room"
const T_SELECT: String = "select"
const T_RACE_START: String = "raceStart"
const T_EV: String = "ev"
const T_RESULTS: String = "results"
const T_KICKED: String = "kicked"
const T_PONG: String = "pong"
const T_ERR: String = "err"

const PUBLIC: String = "public"
const PRIVATE: String = "private"


class SnapCar:
	extends RefCounted
	var id: int
	var s: float
	var d: float
	var yaw_rel: float
	var y: float
	var speed: float
	var vy: float
	var lap: int
	var flags: int


class SnapThing:
	extends RefCounted
	var kind: int
	var s: float
	var d: float
	var length: float


class Snapshot:
	extends RefCounted
	var ack: int
	var tick: int
	var cars: Array[SnapCar] = []
	var proj: Array[SnapThing] = []
	var traps: Array[SnapThing] = []


# ---------- builders (omit empty optional fields like Go's omitempty) ----------

static func hello(player_name: String, opts: Dictionary) -> Dictionary:
	var m: Dictionary = {"t": T_HELLO, "v": VERSION, "name": player_name}
	for key: String in ["token", "room"]:
		if opts.has(key) and str(opts[key]) != "":
			m[key] = str(opts[key])
	for key: String in ["quick", "practice"]:
		if opts.get(key, false):
			m[key] = true
	if opts.has("create"):
		m["create"] = {"visibility": str(opts["create"])}
	if opts.has("blocked") and (opts["blocked"] as Array).size() > 0:
		m["blocked"] = opts["blocked"]
	m["auth"] = {"provider": str(opts.get("auth", "guest"))}
	return m


static func ready(is_ready: bool) -> Dictionary:
	return {"t": T_READY, "ready": is_ready}


static func settings(map_id: String, laps: int, bots: bool, visibility: String) -> Dictionary:
	return {"t": T_SETTINGS, "map": map_id, "laps": laps, "bots": bots, "visibility": visibility}


static func start() -> Dictionary:
	return {"t": T_START}


static func kick(player_id: String) -> Dictionary:
	return {"t": T_KICK, "playerId": player_id}


static func preview(vehicle: String) -> Dictionary:
	return {"t": T_PREVIEW, "vehicle": vehicle}


static func lock(vehicle: String) -> Dictionary:
	return {"t": T_LOCK, "vehicle": vehicle}


## Converts a screen/driver steering direction (+1 = right, −1 = left) to the protocol/physics
## value. Physics steers +1 toward +d (the track Normal), which is the driver's LEFT when looking
## along the track, so the sign flips. Always build `in.steer` through this.
static func steer_from_screen(dir: int) -> int:
	return -dir


static func input(seq: int, steer: int, thr: int, ab: bool) -> Dictionary:
	return {"t": T_IN, "seq": seq, "steer": steer, "thr": thr, "ab": ab}


static func rematch() -> Dictionary:
	return {"t": T_REMATCH}


static func report(player_id: String, reason: String) -> Dictionary:
	return {"t": T_REPORT, "playerId": player_id, "reason": reason}


static func ping(ts: int) -> Dictionary:
	return {"t": T_PING, "ts": ts}


static func leave() -> Dictionary:
	return {"t": T_LEAVE}


## Parses a server JSON message; returns {} on garbage.
static func parse(text: String) -> Dictionary:
	var v: Variant = JSON.parse_string(text)
	if v is Dictionary and (v as Dictionary).has("t"):
		return v as Dictionary
	return {}


## Decodes a binary snapshot (see internal/protocol/codec.go); null if malformed.
static func decode_snapshot(b: PackedByteArray) -> Snapshot:
	if b.size() < SNAP_HEADER + 2 or b.decode_u8(0) != SNAP_KIND:
		return null
	var n: int = b.decode_u8(9)
	if b.size() < SNAP_HEADER + n * SNAP_CAR_BYTES + 2:
		return null
	var s: Snapshot = Snapshot.new()
	s.ack = b.decode_u32(1)
	s.tick = b.decode_u32(5)
	var o: int = SNAP_HEADER
	for i: int in n:
		var c: SnapCar = SnapCar.new()
		c.id = b.decode_u8(o)
		c.s = float(b.decode_u32(o + 1)) * QS
		c.d = float(b.decode_s16(o + 5)) * QS
		c.yaw_rel = float(b.decode_s16(o + 7)) * QYAW
		c.y = float(b.decode_u16(o + 9)) * QS
		c.speed = float(b.decode_u16(o + 11)) * QSPEED
		c.vy = float(b.decode_s16(o + 13)) * QSPEED
		c.lap = b.decode_s8(o + 15)
		c.flags = b.decode_u16(o + 16)
		s.cars.append(c)
		o += SNAP_CAR_BYTES
	var np: int = b.decode_u8(o)
	o += 1
	if b.size() < o + np * 7 + 1:
		return null
	for i: int in np:
		var p: SnapThing = SnapThing.new()
		p.kind = b.decode_u8(o)
		p.s = float(b.decode_u32(o + 1)) * QS
		p.d = float(b.decode_s16(o + 5)) * QS
		s.proj.append(p)
		o += 7
	var nt: int = b.decode_u8(o)
	o += 1
	if b.size() < o + nt * 8:
		return null
	for i: int in nt:
		var t: SnapThing = SnapThing.new()
		t.kind = b.decode_u8(o)
		t.s = float(b.decode_u32(o + 1)) * QS
		t.d = float(b.decode_s16(o + 5)) * QS
		t.length = float(b.decode_u8(o + 7))
		s.traps.append(t)
		o += 8
	return s
