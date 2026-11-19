package sim

import (
	"encoding/binary"
	"fmt"
	"hash/fnv"
	"math"
	"sort"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/track"
)

// Car is one participant in a race.
type Car struct {
	ID       int
	Vehicle  string
	Params   CarParams
	State    CarState
	Input    Input
	Finished bool
	// FinishTick is the tick on which the car completed its last lap (valid if Finished).
	FinishTick int
	// LapTicks holds the tick at which each lap was completed (index 0 = lap 1).
	LapTicks []int
}

// Event is something that happened during a tick (sent to clients as `ev` in M2).
type Event struct {
	Tick  int
	Kind  string // "wallHit", "lap", "finished", "bump", "launch", "land"
	Car   int
	Other int     // second car for "bump"
	Value float64 // impact speed, lap number, …
	Ticks int     // lap/finish tick count since race start
}

// World is a race in progress. Not safe for concurrent use: one goroutine per room owns it.
type World struct {
	Track   *track.Track
	Bal     *gamedata.Balance
	Laps    int
	Tick    int
	Cars    []*Car
	Events  []Event // events of the last Step only
	EndTick int     // tick at which the race ends (0 = not decided yet)
	dt      float64
}

// NewWorld places cars on the grid behind the start line. vehicles[i] is car i's vehicle id;
// grid order is the slice order (first = pole position).
func NewWorld(tr *track.Track, bal *gamedata.Balance, vehicles []gamedata.Vehicle, laps int) *World {
	w := &World{Track: tr, Bal: bal, Laps: laps, dt: 1 / float64(bal.TickRate)}
	for i, v := range vehicles {
		row, col := i/2, i%2
		s := tr.Length - bal.Race.GridStartGap - float64(row)*bal.Race.GridRowSpacing - float64(col)*bal.Race.GridRowSpacing/2
		d := -bal.Race.GridColumnOffset
		if col == 1 {
			d = bal.Race.GridColumnOffset
		}
		w.Cars = append(w.Cars, &Car{
			ID:      i,
			Vehicle: v.ID,
			Params:  ParamsFor(v.Stats, bal.Stats),
			State:   CarState{S: s, D: d, Lap: -1},
		})
	}
	return w
}

// Dt is the fixed timestep in seconds.
func (w *World) Dt() float64 { return w.dt }

// Over reports whether the race has ended.
func (w *World) Over() bool { return w.EndTick > 0 && w.Tick >= w.EndTick }

// Step advances the world by one tick using each car's current Input.
func (w *World) Step() {
	w.Tick++
	w.Events = w.Events[:0]
	ph := &w.Bal.Physics
	for _, c := range w.Cars {
		in := c.Input
		if c.Finished {
			in = Input{Throttle: 1} // finished cars cruise on; they no longer race
		}
		ev := StepCar(&c.State, in, c.Params, NeutralMods, w.Track, ph, w.dt)
		if ev.WallHit {
			w.Events = append(w.Events, Event{Tick: w.Tick, Kind: "wallHit", Car: c.ID, Value: ev.WallImpact})
		}
		if ev.Launched {
			w.Events = append(w.Events, Event{Tick: w.Tick, Kind: "launch", Car: c.ID})
		}
		if ev.Landed {
			w.Events = append(w.Events, Event{Tick: w.Tick, Kind: "land", Car: c.ID})
		}
	}
	w.collide()
	w.updateLaps()
}

// collide resolves car–car overlaps as circles in (s, d) space (GAME_PLAN §2.5 step 5).
func (w *World) collide() {
	ph := &w.Bal.Physics
	L := w.Track.Length
	minDist := 2 * ph.CarRadius
	for i := 0; i < len(w.Cars); i++ {
		for j := i + 1; j < len(w.Cars); j++ {
			a, b := &w.Cars[i].State, &w.Cars[j].State
			if math.Abs(a.Y-b.Y) > ph.CarCollisionMaxDy {
				continue
			}
			ds := mathx.WrapDelta(a.S, b.S, L) // + means b is ahead of a
			dd := b.D - a.D
			dist := math.Sqrt(ds*ds + dd*dd)
			if dist >= minDist {
				continue
			}
			var ns, nd float64
			if dist > 1e-9 {
				ns, nd = ds/dist, dd/dist
			} else {
				ns, nd = 0, 1 // perfectly overlapping: separate sideways, lower id to −d
			}
			overlap := minDist - dist
			ma, mb := w.Cars[i].Params.Mass, w.Cars[j].Params.Mass
			wa, wb := mb/(ma+mb), ma/(ma+mb) // the lighter car moves more
			a.S -= ns * overlap * wa
			a.D -= nd * overlap * wa
			b.S += ns * overlap * wb
			b.D += nd * overlap * wb

			// Speed exchange: a faster car bumping into the one ahead gives it some speed.
			rear, front, mr, mf := a, b, ma, mb
			if ds < 0 {
				rear, front, mr, mf = b, a, mb, ma
			}
			if rel := rear.Speed - front.Speed; rel > 0 && math.Abs(ns) > 0.3 {
				transfer := rel * ph.CollisionSpeedExchange
				rear.Speed -= transfer * mf / (mr + mf)
				front.Speed += transfer * mr / (mr + mf)
			}
			w.Events = append(w.Events, Event{Tick: w.Tick, Kind: "bump", Car: w.Cars[i].ID, Other: w.Cars[j].ID, Value: overlap})
			w.fixup(a)
			w.fixup(b)
		}
	}
}

// fixup re-wraps s (adjusting the lap) and clamps d to the walls after a push.
func (w *World) fixup(c *CarState) {
	L := w.Track.Length
	if c.S >= L {
		c.S -= L
		c.Lap++
	} else if c.S < 0 {
		c.S += L
		c.Lap--
	}
	lim := w.Track.HalfWidth(c.S) - w.Bal.Physics.CarHalfWidth
	c.D = mathx.Clamp(c.D, -lim, lim)
}

// updateLaps records lap completions, finishes and the end of the race.
func (w *World) updateLaps() {
	finishWindow := int(math.Round(w.Bal.Race.FinishWindowS * float64(w.Bal.TickRate)))
	for _, c := range w.Cars {
		if c.Finished {
			continue
		}
		// Lap k (1-based) is completed when Lap reaches k; record each new maximum only once,
		// so driving backwards over the line and forward again doesn't count twice.
		for c.State.Lap > len(c.LapTicks) && c.State.Lap >= 1 {
			c.LapTicks = append(c.LapTicks, w.Tick)
			w.Events = append(w.Events, Event{Tick: w.Tick, Kind: "lap", Car: c.ID, Value: float64(len(c.LapTicks)), Ticks: w.Tick})
		}
		if len(c.LapTicks) >= w.Laps {
			c.Finished = true
			c.FinishTick = w.Tick
			w.Events = append(w.Events, Event{Tick: w.Tick, Kind: "finished", Car: c.ID, Ticks: w.Tick})
			if w.EndTick == 0 {
				w.EndTick = w.Tick + finishWindow
			}
		}
	}
	all := true
	for _, c := range w.Cars {
		all = all && c.Finished
	}
	if all && (w.EndTick == 0 || w.EndTick > w.Tick) {
		w.EndTick = w.Tick
	}
}

// Ranking returns car IDs in race order: finished cars by finish tick, then the rest by
// progress (lap·L + s), ties broken by ID.
func (w *World) Ranking() []int {
	cars := append([]*Car(nil), w.Cars...)
	L := w.Track.Length
	sort.SliceStable(cars, func(i, j int) bool {
		a, b := cars[i], cars[j]
		if a.Finished != b.Finished {
			return a.Finished
		}
		if a.Finished {
			if a.FinishTick != b.FinishTick {
				return a.FinishTick < b.FinishTick
			}
			return a.ID < b.ID
		}
		pa, pb := a.State.Progress(L), b.State.Progress(L)
		if pa != pb {
			return pa > pb
		}
		return a.ID < b.ID
	})
	ids := make([]int, len(cars))
	for i, c := range cars {
		ids[i] = c.ID
	}
	return ids
}

// Hash is a stable FNV-64 digest of the full physical state (determinism tests).
func (w *World) Hash() string {
	h := fnv.New64a()
	var buf [8]byte
	put := func(f float64) {
		binary.LittleEndian.PutUint64(buf[:], math.Float64bits(f))
		h.Write(buf[:])
	}
	put(float64(w.Tick))
	for _, c := range w.Cars {
		s := c.State
		for _, f := range []float64{s.S, s.D, s.YawRel, s.Y, s.Vy, s.Speed, float64(s.Lap), float64(c.FinishTick)} {
			put(f)
		}
	}
	return fmt.Sprintf("%016x", h.Sum64())
}
