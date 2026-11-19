package abilities

import (
	"math"

	"github.com/m0xai/ultiRace/internal/sim"
)

// EMP Pulse (Volt, area): opponents within the radius are slowed.
func (s *System) emp(w *sim.World, car int) bool {
	r := s.u("emp", "radiusM")
	for o := range w.Cars {
		if o == car || w.Cars[o].Status.Ghost(w.Tick) {
			continue
		}
		ds, dd := gap(w, car, o)
		if math.Hypot(ds, dd) <= r {
			w.Slow(o, s.u("emp", "slow"), s.u("emp", "durationS"))
			hit(w, o, car, "emp")
		}
	}
	return true
}
