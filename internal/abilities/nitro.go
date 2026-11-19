package abilities

import "github.com/m0xai/ultiRace/internal/sim"

// Nitro (Bolt, self): big top-speed and acceleration boost.
func (s *System) nitro(w *sim.World, car int) bool {
	w.Boost(car, s.u("nitro", "speed"), s.u("nitro", "accel"), s.u("nitro", "durationS"))
	return true
}
