class_name Physics
extends RefCounted

## Mirror of internal/sim/physics.go StepCar (own-car prediction only, GAME_PLAN §3.3).
## Keep the order of operations identical to Go; test/physics_conformance_test.gd replays
## gamedata/fixtures/physics_*.json and must match within 1e-4.


class CarState:
	extends RefCounted
	var s: float = 0.0
	var d: float = 0.0
	var yaw_rel: float = 0.0
	var y: float = 0.0
	var vy: float = 0.0
	var speed: float = 0.0
	var lap: int = -1

	func airborne() -> bool:
		return y > 0.0 or vy > 0.0

	func copy() -> CarState:
		var c: CarState = CarState.new()
		c.s = s
		c.d = d
		c.yaw_rel = yaw_rel
		c.y = y
		c.vy = vy
		c.speed = speed
		c.lap = lap
		return c


class CarParams:
	extends RefCounted
	var top_speed: float = 0.0
	var accel: float = 0.0
	var steer_rate: float = 0.0
	var wall_reflect: float = 0.0
	var mass: float = 0.0


class Mods:
	extends RefCounted
	var speed_mul: float = 1.0
	var accel_mul: float = 1.0
	var steer_mul: float = 1.0
	var no_input: bool = false


class StepEvents:
	extends RefCounted
	var wall_hit: bool = false
	var wall_impact: float = 0.0
	var launched: bool = false
	var landed: bool = false
	var crossed_start: int = 0


## Physics constants from balance.json, read once.
class Constants:
	extends RefCounted
	var coast_decel: float
	var overspeed_decel: float
	var steer_high_speed_falloff: float
	var steer_ref_speed: float
	var auto_align: float
	var max_yaw_rel: float
	var air_steer_factor: float
	var gravity: float
	var car_half_width: float
	var wall_speed_factor: float
	var wall_min_yaw_out: float
	var min_curvature_denominator: float
	var landing_speed_factor: float
	var car_half_length: float
	var block_speed_factor: float

	func _init(ph: Dictionary) -> void:
		coast_decel = float(ph["coastDecel"])
		overspeed_decel = float(ph["overspeedDecel"])
		steer_high_speed_falloff = float(ph["steerHighSpeedFalloff"])
		steer_ref_speed = float(ph["steerRefSpeed"])
		auto_align = float(ph["autoAlign"])
		max_yaw_rel = float(ph["maxYawRel"])
		air_steer_factor = float(ph["airSteerFactor"])
		gravity = float(ph["gravity"])
		car_half_width = float(ph["carHalfWidth"])
		wall_speed_factor = float(ph["wallSpeedFactor"])
		wall_min_yaw_out = float(ph["wallMinYawOut"])
		min_curvature_denominator = float(ph["minCurvatureDenominator"])
		landing_speed_factor = float(ph["landingSpeedFactor"])
		car_half_length = float(ph["carHalfLength"])
		block_speed_factor = float(ph["blockSpeedFactor"])


static func constants() -> Constants:
	return Constants.new(GameData.balance()["physics"] as Dictionary)


## Linear stat mapping (Go: sim.ParamsFor).
static func params_for(stats: Dictionary, mapping: Dictionary) -> CarParams:
	var p: CarParams = CarParams.new()
	var top: float = float(mapping["topSpeedBase"]) + float(mapping["topSpeedPerStat"]) * float(stats["speed"])
	var accel_time: float = float(mapping["accelTimeBase"]) - float(mapping["accelTimePerStat"]) * float(stats["accel"])
	p.top_speed = top
	p.accel = top / accel_time
	p.steer_rate = float(mapping["steerRateBase"]) + float(mapping["steerRatePerStat"]) * float(stats["handling"])
	p.wall_reflect = float(mapping["wallReflectBase"]) - float(mapping["wallReflectPerStat"]) * float(stats["handling"])
	p.mass = float(mapping["massBase"]) + float(mapping["massPerStat"]) * float(stats["weight"])
	return p


static func params_for_vehicle(vehicle_id: String) -> CarParams:
	var v: Dictionary = GameData.vehicle(vehicle_id)
	var bal: Dictionary = GameData.balance()
	var p: CarParams = params_for(v["stats"] as Dictionary, bal["stats"] as Dictionary)
	# per-vehicle top-speed trim (balance tuner); accel keeps its time-to-top-speed
	var trim: float = float((bal.get("vehicleTrim", {}) as Dictionary).get(vehicle_id, 0.0))
	var accel_time: float = p.top_speed / p.accel
	p.top_speed *= 1.0 + trim
	p.accel = p.top_speed / accel_time
	return p


static func step_car(c: CarState, steer_in: int, throttle_in: int, p: CarParams, mods: Mods, tr: Track, ph: Constants, dt: float) -> StepEvents:
	var ev: StepEvents = StepEvents.new()
	var steer: float = float(steer_in)
	var thr: float = float(throttle_in)
	if mods.no_input:
		steer = 0.0
		thr = 0.0
	var airborne: bool = c.airborne()

	# 1. Speed
	var limit: float = p.top_speed * mods.speed_mul
	if thr > 0.0 and not airborne:
		if c.speed < limit:
			c.speed = minf(c.speed + p.accel * mods.accel_mul * dt, limit)
	elif not airborne:
		c.speed = maxf(c.speed - ph.coast_decel * dt, 0.0)
	if c.speed > limit:
		c.speed = maxf(c.speed - ph.overspeed_decel * dt, limit)

	# 2. Steering
	var speed_frac: float = minf(c.speed / ph.steer_ref_speed, 1.0)
	var rate: float = p.steer_rate * (1.0 - ph.steer_high_speed_falloff * speed_frac) * mods.steer_mul
	if airborne:
		rate *= ph.air_steer_factor
	c.yaw_rel += steer * rate * dt
	c.yaw_rel -= c.yaw_rel * minf(ph.auto_align * dt, 1.0)
	c.yaw_rel = MathX.clampf64(c.yaw_rel, -ph.max_yaw_rel, ph.max_yaw_rel)

	# 3. Move in the Frenet frame
	var kappa: float = tr.curvature(c.s)
	var den: float = maxf(1.0 - c.d * kappa, ph.min_curvature_denominator)
	var prev_s: float = c.s
	var new_s: float = c.s + c.speed * cos(c.yaw_rel) * dt / den
	c.d += c.speed * sin(c.yaw_rel) * dt
	c.yaw_rel -= kappa * (new_s - prev_s)

	# 6a. Ramps
	if not airborne:
		for r: Dictionary in tr.ramps:
			var end_s: float = float(r["s"]) + float(r["length"])
			if (prev_s < end_s and new_s >= end_s) or (prev_s < end_s + tr.length and new_s >= end_s + tr.length):
				c.y = maxf(c.y, float(r["height"]))
				c.vy = float(r["vy"])
				ev.launched = true
				break

	# Lap wrap
	if new_s >= tr.length:
		new_s -= tr.length
		c.lap += 1
		ev.crossed_start = 1
	elif new_s < 0.0:
		new_s += tr.length
		c.lap -= 1
		ev.crossed_start = -1
	c.s = new_s

	# 4. Walls
	var limit_d: float = tr.half_width(c.s) - ph.car_half_width
	if c.d > limit_d:
		c.d = limit_d
		if c.yaw_rel > 0.0:
			ev.wall_hit = true
			ev.wall_impact = c.speed * sin(c.yaw_rel)
			c.speed *= ph.wall_speed_factor
			c.yaw_rel = -maxf(c.yaw_rel * p.wall_reflect, ph.wall_min_yaw_out)
	elif c.d < -limit_d:
		c.d = -limit_d
		if c.yaw_rel < 0.0:
			ev.wall_hit = true
			ev.wall_impact = -c.speed * sin(c.yaw_rel)
			c.speed *= ph.wall_speed_factor
			c.yaw_rel = maxf(-c.yaw_rel * p.wall_reflect, ph.wall_min_yaw_out)

	# 4b. Road blocks (map hazards): pushed out to the nearer side, speed loss, turned away
	if c.y < 0.5:
		for b: Dictionary in tr.blocks:
			var ds: float = MathX.wrap_delta(float(b["s"]), c.s, tr.length)
			if ds < -ph.car_half_length or ds > float(b["len"]) + ph.car_half_length:
				continue
			var off: float = c.d - float(b["d"])
			var reach: float = float(b["halfW"]) + ph.car_half_width
			if absf(off) >= reach:
				continue
			var side: float = 1.0
			if off < 0.0:
				side = -1.0
			c.d = float(b["d"]) + side * reach
			ev.wall_hit = true
			ev.wall_impact = c.speed * 0.5
			c.speed *= ph.block_speed_factor
			c.yaw_rel = side * maxf(absf(c.yaw_rel) * 0.5, ph.wall_min_yaw_out)
			break

	# 6b. Vertical motion
	if c.y > 0.0 or c.vy > 0.0:
		c.vy -= ph.gravity * dt
		c.y += c.vy * dt
		if c.y <= 0.0:
			c.y = 0.0
			c.vy = 0.0
			c.speed *= ph.landing_speed_factor
			ev.landed = true
	return ev
