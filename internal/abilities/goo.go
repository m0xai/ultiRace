package abilities

import (
	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/sim"
)

// Goo Bomb (Goo, lob): a puddle lands ahead; cars inside are slowed while in it (+ short linger).
func (s *System) goo(w *sim.World, car int) bool {
	c := w.Cars[car].State
	w.Traps = append(w.Traps, &sim.Trap{Kind: "goo", Owner: car, S: mathx.WrapPos(c.S+s.u("goo", "aheadM"), w.Track.Length),
		D: c.D, Len: s.u("goo", "lengthM"), HalfW: s.u("goo", "halfWidthM"),
		Until: w.Tick + w.Bal.Ticks(s.u("goo", "lifeS")), Hit: map[int]bool{}})
	return true
}
