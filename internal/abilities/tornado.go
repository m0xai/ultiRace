package abilities

import (
	"math"

	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/sim"
)

// Tornado (Twister, projectile): flies down the track faster than its owner, homing sideways
// on the nearest car ahead; the first car hit spins out. No car ahead → not fired.
func (s *System) tornado(w *sim.World, car int) bool {
	if nearestAhead(w, car, 120) < 0 {
		return false
	}
	c := w.Cars[car].State
	speed := math.Max(c.Speed, s.u("tornado", "minSpeed")) * s.u("tornado", "speedFactor")
	w.Proj = append(w.Proj, &sim.Projectile{Kind: "tornado", Owner: car, S: mathx.WrapPos(c.S+3, w.Track.Length), D: c.D,
		Speed: speed, Until: w.Tick + w.Bal.Ticks(s.u("tornado", "lifeS")), Target: -1})
	return true
}

func (s *System) tickProjectiles(w *sim.World) {
	L := w.Track.Length
	dt := 1 / float64(w.Bal.TickRate)
	r := s.u("tornado", "hitRadiusM")
	kept := w.Proj[:0]
	for _, p := range w.Proj {
		if w.Tick >= p.Until {
			continue
		}
		p.S = mathx.WrapPos(p.S+p.Speed*dt, L)
		// home on the nearest opponent ahead of the projectile
		best, bestDS := -1, math.Inf(1)
		for o := range w.Cars {
			if o == p.Owner || w.Cars[o].Status.Ghost(w.Tick) {
				continue
			}
			ds := mathx.WrapDelta(p.S, w.Cars[o].State.S, L)
			if ds > -r && ds < 80 && ds < bestDS {
				best, bestDS = o, ds
			}
		}
		p.Target = best
		if best >= 0 {
			td := w.Cars[best].State.D
			step := s.u("tornado", "homingRate") * dt
			p.D += mathx.Clamp(td-p.D, -step, step)
		}
		hitCar := -1
		for o := range w.Cars {
			if o == p.Owner || w.Cars[o].Status.Ghost(w.Tick) {
				continue
			}
			ds := mathx.WrapDelta(p.S, w.Cars[o].State.S, L)
			if math.Abs(ds) < r && math.Abs(w.Cars[o].State.D-p.D) < r {
				hitCar = o
				break
			}
		}
		if hitCar >= 0 {
			if w.Spinout(hitCar, s.u("tornado", "spinS")) {
				hit(w, hitCar, p.Owner, "tornado")
			}
			continue // first hit consumes the tornado
		}
		kept = append(kept, p)
	}
	w.Proj = kept
}

func (s *System) tickTraps(w *sim.World) {
	L := w.Track.Length
	kept := w.Traps[:0]
	for _, t := range w.Traps {
		if w.Tick >= t.Until {
			continue
		}
		for o := range w.Cars {
			c := w.Cars[o]
			if o == t.Owner || c.Status.Ghost(w.Tick) || c.State.Y > 0.5 {
				continue // no self-hits; ghosts and airborne cars pass over
			}
			ds := mathx.WrapDelta(t.S, c.State.S, L)
			if ds < 0 || ds > t.Len || math.Abs(c.State.D-t.D) > t.HalfW {
				continue
			}
			switch t.Kind {
			case "ice":
				if !t.Hit[o] {
					t.Hit[o] = true
					w.Slide(o, s.u("ice", "steerMul"), s.u("ice", "slow"), s.u("ice", "effectS"))
					hit(w, o, t.Owner, "ice")
				}
			case "goo":
				w.Slow(o, s.u("goo", "slow"), s.u("goo", "lingerS"))
				if !t.Hit[o] {
					t.Hit[o] = true
					hit(w, o, t.Owner, "goo")
				}
			}
		}
		kept = append(kept, t)
	}
	w.Traps = kept
}
