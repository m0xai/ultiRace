package sim

import (
	"math"
	"testing"

	"github.com/m0xai/ultiRace/gamedata"
)

// firstHazard returns the first hazard of a kind on a map.
func firstHazard(t *testing.T, f *fixture, mapID, kind string) gamedata.Hazard {
	t.Helper()
	for _, h := range f.tracks[mapID].Hazards {
		if h.Kind == kind {
			return h
		}
	}
	t.Fatalf("%s has no %s hazard", mapID, kind)
	return gamedata.Hazard{}
}

// Driving straight into a road block pushes the car beside it, costs speed and reports a hit.
func TestRoadBlockPushesOutAndSlows(t *testing.T) {
	f := load(t)
	tr := f.tracks["sunny"]
	b := firstHazard(t, f, "sunny", gamedata.HazardBlock)
	p := ParamsFor(f.vehicle(t, "bolt").Stats, f.bal.Stats)
	c := CarState{S: b.S - 6, D: b.D, Speed: 30}
	hit := false
	for i := 0; i < 20 && !hit; i++ {
		ev := StepCar(&c, Input{Throttle: 1}, p, NeutralMods, tr, &f.bal.Physics, 1.0/30)
		hit = ev.WallHit
	}
	if !hit {
		t.Fatal("drove through the block")
	}
	reach := b.HalfW + f.bal.Physics.CarHalfWidth
	if d := c.D - b.D; d > -reach+1e-9 && d < reach-1e-9 {
		t.Fatalf("car still inside the block: d=%.2f block %.2f±%.2f", c.D, b.D, reach)
	}
	if c.Speed > 30*f.bal.Physics.BlockSpeedFactor+1 {
		t.Fatalf("no speed loss: %.1f", c.Speed)
	}
}

func hazardWorld(t *testing.T, mapID string, bots ...bool) *World {
	f := load(t)
	vs := []gamedata.Vehicle{f.vehicle(t, "bolt"), f.vehicle(t, "goo")}
	w := NewWorld(f.tracks[mapID], f.bal, vs[:len(bots)], 3)
	for i, b := range bots {
		w.Cars[i].Bot = b
	}
	w.Tick = 1000
	return w
}

// Water slows a car while on it; ice makes it slide (once per pass).
func TestSurfaceHazards(t *testing.T) {
	f := load(t)
	for _, tc := range []struct{ mapID, kind string }{{"sunny", gamedata.HazardWater}, {"frosty", gamedata.HazardIce}, {"neon", gamedata.HazardOil}} {
		h := firstHazard(t, f, tc.mapID, tc.kind)
		w := hazardWorld(t, tc.mapID, false)
		w.Cars[0].State = CarState{S: h.S - 1, D: h.D, Speed: 25}
		w.Cars[0].Input = Input{Throttle: 1}
		flagged, events := false, 0
		for i := 0; i < 15; i++ {
			w.Step()
			flagged = flagged || w.Cars[0].Flags&(EffSlow|EffSlide) != 0
			for _, e := range w.Events {
				if e.Kind == "hazard" {
					events++
				}
			}
		}
		if !flagged || events != 1 {
			t.Errorf("%s %s: flagged=%v hazard events=%d (want 1)", tc.mapID, tc.kind, flagged, events)
		}
	}
}

// Bot catch-up applies only to bots, only when a human races, and grows with the gap.
func TestBotCatchupOnlyBehindAHuman(t *testing.T) {
	w := hazardWorld(t, "sunny", false, true)
	cu := w.Bal.Catchup
	w.Cars[0].State = CarState{S: 600, Speed: 30, Lap: 0}
	w.Cars[1].State = CarState{S: 600 - cu.BotGapM - cu.BotRampM - 20, Speed: 30, Lap: 0}
	w.Step()
	if got := w.Cars[1].Status.botBoost; got < cu.BotBonus-1e-9 {
		t.Fatalf("far-behind bot boost %.3f, want %.3f", got, cu.BotBonus)
	}
	if w.Cars[0].Status.botBoost != 0 {
		t.Fatal("human got the bot boost")
	}
	all := hazardWorld(t, "sunny", true, true) // no human: never
	all.Cars[0].State = CarState{S: 600, Speed: 30}
	all.Cars[1].State = CarState{S: 300, Speed: 30}
	all.Step()
	if all.Cars[1].Status.botBoost != 0 {
		t.Fatal("bot boost without a human in the race")
	}
}

// A car hitting a block from the wall side is sent to the open lane, never pinned outside the road.
func TestRoadBlockNeverPushesIntoTheWall(t *testing.T) {
	f := load(t)
	tr := f.tracks["sunny"]
	for _, b := range tr.Blocks {
		lim := tr.HalfWidth(b.S) - f.bal.Physics.CarHalfWidth
		p := ParamsFor(f.vehicle(t, "bolt").Stats, f.bal.Stats)
		side := 1.0
		if b.D < 0 {
			side = -1
		}
		c := CarState{S: b.S - 5, D: side * lim, Speed: 30} // hugging the wall behind the block
		for i := 0; i < 30; i++ {
			StepCar(&c, Input{Throttle: 1}, p, NeutralMods, tr, &f.bal.Physics, 1.0/30)
			if math.Abs(c.D) > lim+1e-9 {
				t.Fatalf("block at s=%.0f: car pushed outside the road (d=%.2f, limit %.2f)", b.S, c.D, lim)
			}
		}
		if ds := c.S - b.S; ds > 0 && ds < b.Len && math.Abs(c.D-b.D) < b.HalfW+f.bal.Physics.CarHalfWidth-1e-9 {
			t.Fatalf("block at s=%.0f: car inside it", b.S)
		}
	}
}
