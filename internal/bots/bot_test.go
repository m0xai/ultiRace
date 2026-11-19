package bots

import (
	"math"
	"testing"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/sim"
	"github.com/m0xai/ultiRace/internal/track"
)

func setup(t *testing.T, mapID string) (*track.Track, *gamedata.Balance, []gamedata.Vehicle) {
	t.Helper()
	bal, err := gamedata.LoadBalance()
	if err != nil {
		t.Fatal(err)
	}
	veh, err := gamedata.LoadVehicles()
	if err != nil {
		t.Fatal(err)
	}
	tr, err := track.Load(mapID, bal.Track.ArcSamplesPerSegment)
	if err != nil {
		t.Fatal(err)
	}
	return tr, bal, veh
}

// runBots races 8 bots and returns the world.
func runBots(t *testing.T, mapID string, laps int, seed uint32) *sim.World {
	tr, bal, veh := setup(t, mapID)
	w := sim.NewWorld(tr, bal, veh, laps)
	line := NewRacingLine(tr)
	ctrls := make([]*Controller, len(w.Cars))
	for i := range ctrls {
		ctrls[i] = NewController(line, Normal, seed+uint32(i))
	}
	states := make([]*sim.CarState, len(w.Cars))
	for i, c := range w.Cars {
		states[i] = &c.State
	}
	for !w.Over() && w.Tick < 30*60*5 {
		for i, c := range w.Cars {
			others := make([]*sim.CarState, 0, len(states)-1)
			for j, s := range states {
				if j != i {
					others = append(others, s)
				}
			}
			c.Input = ctrls[i].Decide(&c.State, others, tr)
		}
		w.Step()
	}
	return w
}

// GAME_PLAN §9: a bot finishes 3 laps on every map (here: a full 8-bot field).
func TestEightBotsFinishThreeLapsOnEveryMap(t *testing.T) {
	for _, id := range gamedata.MapIDs() {
		w := runBots(t, id, 3, 1)
		finished, walls := 0, 0
		for _, c := range w.Cars {
			if c.Finished {
				finished++
			}
		}
		if finished < 6 {
			t.Errorf("%s: only %d/8 bots finished in time (tick %d)", id, finished, w.Tick)
		}
		first := w.Cars[w.Ranking()[0]]
		raceS := float64(first.FinishTick) / 30
		t.Logf("%s: winner %s in %.1fs (%.1fs/lap), %d finished, walls %d", id, first.Vehicle, raceS, raceS/3, finished, walls)
		if raceS/3 < 30 || raceS/3 > 50 {
			t.Errorf("%s: average lap %.1fs outside 30–50 s", id, raceS/3)
		}
	}
}

func TestRacingLineStaysOnTrack(t *testing.T) {
	for _, id := range gamedata.MapIDs() {
		tr, _, _ := setup(t, id)
		rl := NewRacingLine(tr)
		for s := 0.0; s < tr.Length; s += 1 {
			if d := rl.TargetD(s); math.Abs(d) > tr.HalfWidth(s)-2.9 {
				t.Fatalf("%s: line %.2f off track at s=%.0f", id, d, s)
			}
		}
	}
}

func TestBotsAreDeterministic(t *testing.T) {
	a := runBots(t, "neon", 1, 9).Hash()
	b := runBots(t, "neon", 1, 9).Hash()
	if a != b {
		t.Fatal("same seed, different races")
	}
}
