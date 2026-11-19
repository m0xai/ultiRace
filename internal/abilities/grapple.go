package abilities

import "github.com/m0xai/ultiRace/internal/sim"

// Grapple (Hook, target): tether to the nearest car ahead in range; Hook speeds up, the target
// slows down. No target → not fired (no cooldown spent).
func (s *System) grapple(w *sim.World, car int) bool {
	t := nearestAhead(w, car, s.u("grapple", "rangeM"))
	if t < 0 {
		return false
	}
	d := s.u("grapple", "durationS")
	w.Boost(car, s.u("grapple", "selfBoost"), 0, d)
	w.Slow(t, s.u("grapple", "targetSlow"), d)
	hit(w, t, car, "grapple")
	return true
}
