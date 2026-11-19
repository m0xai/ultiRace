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


class Snapshot:
	extends RefCounted
	var ack: int
	var tick: int
	var cars: Array[SnapCar] = []
	var proj: int
	var traps: int


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
	s.proj = b.decode_u8(o)
	s.traps = b.decode_u8(o + 1)
	return s
