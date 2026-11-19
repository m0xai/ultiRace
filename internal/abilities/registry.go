// Package abilities implements the eight ULTs (GAME_PLAN §2.6) on top of sim's status effects.
// All numbers come from balance.json → ults. Server only: clients see results in snapshots/events.
package abilities

import (
	"math"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/sim"
)

// System is one race's ULT state (create one per sim.World).
type System struct {
	bal      *gamedata.Balance
	ramUntil map[int]int
}

// New returns a ULT system; assign it to world.Ults.
func New(bal *gamedata.Balance) *System {
	return &System{bal: bal, ramUntil: map[int]int{}}
}

func (s *System) u(id, key string) float64 { return s.bal.Ult(id, key) }

// Activate fires car's ULT (sim calls this on the button's rising edge when charged).
func (s *System) Activate(w *sim.World, car int) bool {
	switch w.Cars[car].Ult {
	case "nitro":
		return s.nitro(w, car)
	case "ram":
		return s.ram(w, car)
	case "ice":
		return s.ice(w, car)
	case "emp":
		return s.emp(w, car)
	case "grapple":
		return s.grapple(w, car)
	case "goo":
		return s.goo(w, car)
	case "phase":
		return s.phase(w, car)
	case "tornado":
		return s.tornado(w, car)
	}
	return false
}

// Tick runs traps, projectiles and Ram contacts after the cars moved.
func (s *System) Tick(w *sim.World) {
	s.tickRam(w)
	s.tickTraps(w)
	s.tickProjectiles(w)
}

// ---------- shared helpers ----------

// gap returns (ds, dd): how far other is ahead of car along the track, and laterally.
func gap(w *sim.World, car, other int) (float64, float64) {
	a, b := w.Cars[car].State, w.Cars[other].State
	return mathx.WrapDelta(a.S, b.S, w.Track.Length), b.D - a.D
}

// nearestAhead finds the closest opponent ahead within maxDist (−1 if none).
func nearestAhead(w *sim.World, car int, maxDist float64) int {
	best, bestDS := -1, math.Inf(1)
	for o := range w.Cars {
		if o == car || w.Cars[o].Finished || w.Cars[o].Status.Ghost(w.Tick) {
			continue
		}
		ds, _ := gap(w, car, o)
		if ds > 0 && ds <= maxDist && ds < bestDS {
			best, bestDS = o, ds
		}
	}
	return best
}

func hit(w *sim.World, victim, source int, ult string) {
	w.Events = append(w.Events, sim.Event{Tick: w.Tick, Kind: "hit", Car: victim, Other: source, Ult: ult})
}
