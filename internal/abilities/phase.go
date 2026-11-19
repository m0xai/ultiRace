package abilities

import "github.com/m0xai/ultiRace/internal/sim"

// Phase (Phantom, defensive): ghost — CC immune, passes cars and traps, small boost, clears effects.
func (s *System) phase(w *sim.World, car int) bool {
	d := s.u("phase", "durationS")
	w.Ghostify(car, d)
	w.Boost(car, s.u("phase", "speed"), 0, d)
	return true
}
