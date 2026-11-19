package bots

import (
	"math"

	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/sim"
)

// WantsUlt is the per-ULT bot heuristic (GAME_PLAN §2.9). Call only when w.UltReady(i).
func WantsUlt(w *sim.World, i int) bool {
	me := w.Cars[i]
	L := w.Track.Length
	ahead, behind := math.Inf(1), math.Inf(1)
	aheadLane := false
	near := 0
	for j, o := range w.Cars {
		if j == i || o.Finished {
			continue
		}
		ds := mathx.WrapDelta(me.State.S, o.State.S, L)
		dd := o.State.D - me.State.D
		if ds > 0 && ds < ahead {
			ahead = ds
			aheadLane = math.Abs(dd) < 2.5
		}
		if ds < 0 && -ds < behind {
			behind = -ds
		}
		if math.Hypot(ds, dd) <= w.Bal.Ult("emp", "radiusM") {
			near++
		}
	}
	switch me.Ult {
	case "nitro": // on a straight-ish stretch ahead
		k := 0.0
		for d := 0.0; d <= 80; d += 10 {
			k = math.Max(k, math.Abs(w.Track.Curvature(me.State.S+d)))
		}
		return k < 1.0/120
	case "ram":
		return ahead < 10 && aheadLane
	case "ice":
		return behind < 30
	case "emp":
		return near >= 2
	case "grapple":
		return ahead > 15 && ahead < w.Bal.Ult("grapple", "rangeM")
	case "goo":
		return ahead > 25 && ahead < 55
	case "phase":
		return me.Status.Spinning(w.Tick) || behind < 12 || len(w.Proj) > 0
	case "tornado":
		return ahead < 60
	}
	return false
}
