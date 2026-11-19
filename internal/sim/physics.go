package sim

import (
	"math"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/track"
)

// StepCar advances one car by dt (GAME_PLAN §2.5 steps 1–4 and 6). It is a pure function of
// its inputs and is mirrored line by line in godot/src/sim/Physics.gd — keep the order of
// operations identical when changing it, then run `make fixtures sync test`.
func StepCar(c *CarState, in Input, p CarParams, mods Mods, tr *track.Track, ph *gamedata.Physics, dt float64) StepEvents {
	var ev StepEvents
	steer, thr := float64(in.Steer), float64(in.Throttle)
	if mods.NoInput {
		steer, thr = 0, 0
	}
	airborne := c.Airborne()

	// 1. Speed: accelerate toward the cap, coast without throttle, bleed off overspeed.
	limit := p.TopSpeed * mods.SpeedMul
	if thr > 0 && !airborne {
		if c.Speed < limit {
			c.Speed = math.Min(c.Speed+p.Accel*mods.AccelMul*dt, limit)
		}
	} else if !airborne {
		c.Speed = math.Max(c.Speed-ph.CoastDecel*dt, 0)
	}
	if c.Speed > limit {
		c.Speed = math.Max(c.Speed-ph.OverspeedDecel*dt, limit)
	}

	// 2. Steering with high-speed falloff, air factor, then auto-align toward the tangent.
	speedFrac := math.Min(c.Speed/p.TopSpeed, 1)
	rate := p.SteerRate * (1 - ph.SteerHighSpeedFalloff*speedFrac) * mods.SteerMul
	if airborne {
		rate *= ph.AirSteerFactor
	}
	c.YawRel += steer * rate * dt
	c.YawRel -= c.YawRel * math.Min(ph.AutoAlign*dt, 1)
	c.YawRel = mathx.Clamp(c.YawRel, -ph.MaxYawRel, ph.MaxYawRel)

	// 3. Move in the Frenet frame: ds = v·cosθ·dt / (1 − d·κ).
	kappa := tr.Curvature(c.S)
	den := math.Max(1-c.D*kappa, ph.MinCurvatureDenominator)
	prevS := c.S
	newS := c.S + c.Speed*math.Cos(c.YawRel)*dt/den
	c.D += c.Speed * math.Sin(c.YawRel) * dt
	// The tangent turns under a car that goes straight: dθ = −κ·ds. Without this the car
	// would follow corners by itself and steering would not matter.
	c.YawRel -= kappa * (newS - prevS)

	// 6a. Ramps: launch when the car passes a ramp's end on the ground.
	if !airborne {
		for _, r := range tr.Ramps {
			end := r.S + r.Length
			if (prevS < end && newS >= end) || (prevS < end+tr.Length && newS >= end+tr.Length) {
				c.Vy = r.Vy
				ev.Launched = true
				break
			}
		}
	}

	// Lap wrap.
	if newS >= tr.Length {
		newS -= tr.Length
		c.Lap++
		ev.CrossedStart = 1
	} else if newS < 0 {
		newS += tr.Length
		c.Lap--
		ev.CrossedStart = -1
	}
	c.S = newS

	// 4. Walls: clamp, lose speed and reflect heading when driving into the wall.
	limitD := tr.HalfWidth(c.S) - ph.CarHalfWidth
	if c.D > limitD {
		c.D = limitD
		if c.YawRel > 0 {
			ev.WallHit = true
			ev.WallImpact = c.Speed * math.Sin(c.YawRel)
			c.Speed *= ph.WallSpeedFactor
			c.YawRel = -math.Max(c.YawRel*p.WallReflect, ph.WallMinYawOut)
		}
	} else if c.D < -limitD {
		c.D = -limitD
		if c.YawRel < 0 {
			ev.WallHit = true
			ev.WallImpact = -c.Speed * math.Sin(c.YawRel)
			c.Speed *= ph.WallSpeedFactor
			c.YawRel = math.Max(-c.YawRel*p.WallReflect, ph.WallMinYawOut)
		}
	}

	// 6b. Vertical motion.
	if c.Y > 0 || c.Vy > 0 {
		c.Vy -= ph.Gravity * dt
		c.Y += c.Vy * dt
		if c.Y <= 0 {
			c.Y = 0
			c.Vy = 0
			c.Speed *= ph.LandingSpeedFactor
			ev.Landed = true
		}
	}
	return ev
}
