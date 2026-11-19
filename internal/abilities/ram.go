package abilities

import (
	"math"

	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/sim"
)

// Ram Charge (Rhino, contact): short dash; the first car touched spins out and is knocked sideways.
func (s *System) ram(w *sim.World, car int) bool {
	w.Boost(car, s.u("ram", "speed"), 0, s.u("ram", "durationS"))
	s.ramUntil[car] = w.Tick + w.Bal.Ticks(s.u("ram", "durationS"))
	return true
}

func (s *System) tickRam(w *sim.World) {
	reach := 2*w.Bal.Physics.CarHalfLength + 0.6
	for car, until := range s.ramUntil {
		if w.Tick > until {
			delete(s.ramUntil, car)
			continue
		}
		for o := range w.Cars {
			if o == car || w.Cars[o].Status.Ghost(w.Tick) {
				continue
			}
			ds, dd := gap(w, car, o)
			if ds > -0.5 && ds < reach && math.Abs(dd) < 2*w.Bal.Physics.CarHalfWidth+0.4 {
				if w.Spinout(o, s.u("ram", "spinS")) {
					st := &w.Cars[o].State
					dir := 1.0
					if dd < 0 {
						dir = -1
					}
					lim := w.Track.HalfWidth(st.S) - w.Bal.Physics.CarHalfWidth
					st.D = mathx.Clamp(st.D+dir*s.u("ram", "knockD"), -lim, lim)
					hit(w, o, car, "ram")
				}
				delete(s.ramUntil, car) // first car hit ends the charge
				break
			}
		}
	}
}
