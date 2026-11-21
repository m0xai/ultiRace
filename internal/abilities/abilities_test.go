package abilities

import (
	"math"
	"testing"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/sim"
	"github.com/m0xai/ultiRace/internal/track"
)

// world builds a 1-lap race on sunny with the given vehicles, past the ULT lock.
func world(t *testing.T, ids ...string) *sim.World {
	t.Helper()
	bal, err := gamedata.LoadBalance()
	if err != nil {
		t.Fatal(err)
	}
	all, _ := gamedata.LoadVehicles()
	var vs []gamedata.Vehicle
	for _, id := range ids {
		for _, v := range all {
			if v.ID == id {
				vs = append(vs, v)
			}
		}
	}
	tr, _ := track.Load("sunny", bal.Track.ArcSamplesPerSegment)
	tr.Hazards, tr.Blocks = nil, nil // ULT tests run on a clean road (map hazards have their own tests)
	w := sim.NewWorld(tr, bal, vs, 3)
	w.Ults = New(bal)
	w.Tick = bal.Ticks(bal.Effects.UltLockS) + 1
	for _, c := range w.Cars {
		c.State = sim.CarState{S: 50, Speed: 30, Lap: 0}
		c.PrevThrottle = 1
		c.UltLeft = 0 // ULT tests start charged (races start with an empty bar, see sim tests)
	}
	return w
}

func place(w *sim.World, car int, s, d float64) {
	w.Cars[car].State.S, w.Cars[car].State.D = s, d
}

// fire releases the button for one tick, then presses it (ULTs fire on the rising edge).
func fire(w *sim.World, car int) {
	w.Cars[car].Input = sim.Input{Throttle: 1}
	w.Step()
	w.Cars[car].Input = sim.Input{Throttle: 1, Ability: true}
	w.Step()
	w.Cars[car].Input = sim.Input{Throttle: 1}
}

func step(w *sim.World, n int) {
	for range n {
		for _, c := range w.Cars {
			c.Input.Throttle = 1
		}
		w.Step()
	}
}

func events(w *sim.World, kind string) int {
	n := 0
	for _, e := range w.Events {
		if e.Kind == kind {
			n++
		}
	}
	return n
}

func TestEveryUltHasNumbers(t *testing.T) {
	bal, _ := gamedata.LoadBalance()
	vs, _ := gamedata.LoadVehicles()
	for _, v := range vs {
		if bal.Ult(v.Ult, "cooldownS") <= 0 {
			t.Fatalf("%s: no cooldown", v.Ult)
		}
	}
}

func TestNitroBoostsTopSpeedAndStartsCooldown(t *testing.T) {
	w := world(t, "bolt")
	top := w.Cars[0].Params.TopSpeed
	w.Cars[0].State.Speed = top
	fire(w, 0)
	if events(w, "abilityUsed") != 1 || w.Cars[0].UltLeft <= 0 {
		t.Fatal("nitro did not fire")
	}
	step(w, 45)
	if w.Cars[0].State.Speed <= top*1.2 {
		t.Fatalf("speed %.1f, want > %.1f with nitro", w.Cars[0].State.Speed, top*1.2)
	}
	fire(w, 0) // on cooldown
	if events(w, "abilityUsed") != 0 {
		t.Fatal("fired during cooldown")
	}
}

func TestNoUltsDuringLock(t *testing.T) {
	w := world(t, "bolt")
	w.Tick = 10
	fire(w, 0)
	if w.Cars[0].UltUses != 0 {
		t.Fatal("ULT fired in the first 3 s")
	}
}

func TestRamSpinsAndKnocksFirstCarHit(t *testing.T) {
	w := world(t, "rhino", "bolt")
	place(w, 0, 100, 0)
	place(w, 1, 104, 0.5)
	w.Cars[1].State.Speed = 20
	fire(w, 0)
	step(w, 10)
	if !w.Cars[1].Status.Spinning(w.Tick) && w.Cars[1].Status.HardCCReceived == 0 {
		t.Fatal("rammed car not spun out")
	}
	if math.Abs(w.Cars[1].State.D) < 2 {
		t.Fatalf("not knocked sideways: d=%.2f", w.Cars[1].State.D)
	}
}

func TestHardCCRules(t *testing.T) {
	w := world(t, "bolt", "rhino")
	if !w.Spinout(0, 1.0) {
		t.Fatal("first spinout refused")
	}
	w.Tick += w.Bal.Ticks(2.0) // spin over, still immune / within 4 s
	if w.Spinout(0, 1.0) {
		t.Fatal("hard CC allowed during immunity / 4 s gap")
	}
	w.Tick += w.Bal.Ticks(2.5)
	if !w.Spinout(0, 1.0) {
		t.Fatal("hard CC refused after 4.5 s")
	}
	// heavy cars spin shorter: rhino weight 5 → −10 %
	w.Tick += w.Bal.Ticks(10)
	start := w.Tick
	w.Spinout(1, 1.0)
	if got := w.Cars[1].Status; !got.Spinning(start+w.Bal.Ticks(0.85)) || got.Spinning(start+w.Bal.Ticks(0.95)) {
		t.Fatal("weight reduction not applied")
	}
}

func TestSlowsDontStackAndAreCapped(t *testing.T) {
	w := world(t, "glacier")
	top := w.Cars[0].Params.TopSpeed
	w.Cars[0].State.Speed = top
	w.Slow(0, 0.35, 5)
	w.Slow(0, 0.25, 5)
	step(w, 90)
	if v := w.Cars[0].State.Speed; math.Abs(v-top*0.65) > 0.5 {
		t.Fatalf("speed %.2f, want strongest slow only (%.2f)", v, top*0.65)
	}
	w.Slow(0, 0.9, 5)
	step(w, 90)
	if v := w.Cars[0].State.Speed; v < top*0.5-0.5 {
		t.Fatalf("slow not capped at 50 %%: %.2f", v)
	}
}

func TestEmpSlowsNearbyOnly(t *testing.T) {
	w := world(t, "volt", "bolt", "rhino")
	place(w, 0, 100, 0)
	place(w, 1, 110, 2) // in range
	place(w, 2, 160, 0) // out of range
	fire(w, 0)
	if events(w, "hit") != 1 {
		t.Fatalf("emp hits %d, want 1", events(w, "hit"))
	}
}

func TestGrappleNeedsTarget(t *testing.T) {
	w := world(t, "hook", "bolt")
	place(w, 0, 100, 0)
	place(w, 1, 300, 0) // 200 m ahead: out of range
	fire(w, 0)
	if w.Cars[0].UltUses != 0 {
		t.Fatal("grapple fired without a target")
	}
	place(w, 1, 140, 0)
	fire(w, 0)
	if w.Cars[0].UltUses != 1 || events(w, "hit") != 1 {
		t.Fatal("grapple did not hit the car ahead")
	}
}

func TestIceTrapSlidesOthersNotOwner(t *testing.T) {
	w := world(t, "glacier", "bolt")
	place(w, 0, 300, 0) // on the back straight
	place(w, 1, 250, 0)
	fire(w, 0)
	if len(w.Traps) != 1 {
		t.Fatal("no ice patch")
	}
	slid := false
	for range 90 {
		step(w, 1)
		slid = slid || w.Cars[1].Flags&sim.EffSlide != 0
		if w.Cars[0].Flags&sim.EffSlide != 0 {
			t.Fatal("owner slid on own ice")
		}
	}
	if !slid {
		t.Fatal("car behind never slid on the ice")
	}
}

func TestIceMaxTwoPatches(t *testing.T) {
	w := world(t, "glacier")
	for range 3 {
		fire(w, 0)
		w.Cars[0].UltLeft = 0
	}
	if len(w.Traps) != 2 {
		t.Fatalf("%d patches, want max 2", len(w.Traps))
	}
}

func TestGooPuddleSlowsWhileInside(t *testing.T) {
	w := world(t, "goo", "bolt")
	place(w, 0, 100, 0)
	place(w, 1, 120, 0)
	w.Cars[1].State.Speed = 30
	fire(w, 0) // lands 40 m ahead of goo → at 140
	slowed := false
	for range 60 {
		step(w, 1)
		slowed = slowed || w.Cars[1].Flags&sim.EffSlow != 0
	}
	if !slowed {
		t.Fatal("car never slowed in the goo")
	}
}

func TestPhaseGhostsAndIgnoresHardCC(t *testing.T) {
	w := world(t, "phantom", "rhino")
	fire(w, 0)
	if w.Spinout(0, 1) {
		t.Fatal("ghost was hard-CC'd")
	}
	place(w, 0, 100, 0)
	place(w, 1, 100.5, 0)
	step(w, 1)
	if events(w, "bump") != 0 {
		t.Fatal("ghost collided")
	}
}

func TestTornadoHomesAndSpins(t *testing.T) {
	w := world(t, "twister", "bolt")
	place(w, 0, 100, -3)
	place(w, 1, 130, 3)
	w.Cars[1].State.Speed = 15
	fire(w, 0)
	if len(w.Proj) != 1 {
		t.Fatal("no tornado")
	}
	hitIt := false
	for range 120 {
		step(w, 1)
		hitIt = hitIt || events(w, "hit") > 0
	}
	if !hitIt || w.Cars[1].Status.HardCCReceived != 1 {
		t.Fatal("tornado never hit the car ahead")
	}
	if len(w.Proj) != 0 {
		t.Fatal("tornado not consumed by the hit")
	}
}

func TestStartBoostOnlyForFreshPressInWindow(t *testing.T) {
	bal, _ := gamedata.LoadBalance()
	all, _ := gamedata.LoadVehicles()
	tr, _ := track.Load("sunny", bal.Track.ArcSamplesPerSegment)
	w := sim.NewWorld(tr, bal, all[:3], 3)
	w.Cars[0].PrevThrottle = 1 // held during countdown: no boost
	w.Cars[1].PrevThrottle = 0 // presses at GO: boost
	for _, c := range w.Cars {
		c.Input = sim.Input{Throttle: 1}
	}
	w.Cars[2].Input = sim.Input{} // presses too late
	w.Step()
	boosts := map[int]bool{}
	for _, e := range w.Events {
		if e.Kind == "startBoost" {
			boosts[e.Car] = true
		}
	}
	window := bal.Ticks(bal.Catchup.StartBoostWindowS)
	for range bal.Ticks(1) {
		if w.Tick > window+1 {
			w.Cars[2].Input = sim.Input{Throttle: 1} // presses after the window
		}
		w.Step()
		for _, e := range w.Events {
			if e.Kind == "startBoost" {
				boosts[e.Car] = true
			}
		}
	}
	if boosts[0] || !boosts[1] || boosts[2] {
		t.Fatalf("start boosts %v, want only car 1", boosts)
	}
}

func TestDraftingNeedsTimeBehind(t *testing.T) {
	w := world(t, "bolt", "rhino")
	place(w, 0, 100, 0)
	place(w, 1, 110, 0)
	for _, c := range w.Cars {
		c.State.Speed = 30
	}
	step(w, 10)
	if w.Cars[0].Flags&sim.EffDraft != 0 {
		t.Fatal("drafting before 0.7 s")
	}
	step(w, 20)
	if w.Cars[0].Flags&sim.EffDraft == 0 && w.Cars[0].Status.HardCCReceived == 0 {
		t.Fatal("no draft after 1 s behind")
	}
}
