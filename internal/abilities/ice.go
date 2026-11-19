package abilities

import (
	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/sim"
)

// Ice Slick (Glacier, trap): a patch behind the car; cars on it slide (steering ×0.25, small
// slow). At most `max` patches per owner; each car is affected once per patch.
func (s *System) ice(w *sim.World, car int) bool {
	c := w.Cars[car].State
	length := s.u("ice", "lengthM")
	start := mathx.WrapPos(c.S-s.u("ice", "behindM")-length, w.Track.Length)
	mine := 0
	for _, t := range w.Traps {
		if t.Kind == "ice" && t.Owner == car {
			mine++
		}
	}
	if mine >= int(s.u("ice", "max")) { // drop the oldest of ours
		for i, t := range w.Traps {
			if t.Kind == "ice" && t.Owner == car {
				w.Traps = append(w.Traps[:i], w.Traps[i+1:]...)
				break
			}
		}
	}
	w.Traps = append(w.Traps, &sim.Trap{Kind: "ice", Owner: car, S: start, D: c.D, Len: length, HalfW: s.u("ice", "halfWidthM"),
		Until: w.Tick + w.Bal.Ticks(s.u("ice", "lifeS")), Hit: map[int]bool{}})
	return true
}
