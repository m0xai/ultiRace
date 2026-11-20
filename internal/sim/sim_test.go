package sim

import (
	"math"
	"sync"
	"testing"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/track"
)

type fixture struct {
	bal      *gamedata.Balance
	vehicles []gamedata.Vehicle
	tracks   map[string]*track.Track
}

func load(t testing.TB) *fixture {
	t.Helper()
	bal, err := gamedata.LoadBalance()
	if err != nil {
		t.Fatal(err)
	}
	veh, err := gamedata.LoadVehicles()
	if err != nil {
		t.Fatal(err)
	}
	f := &fixture{bal: bal, vehicles: veh, tracks: map[string]*track.Track{}}
	for _, id := range gamedata.MapIDs() {
		tr, err := track.Load(id, bal.Track.ArcSamplesPerSegment)
		if err != nil {
			t.Fatal(err)
		}
		f.tracks[id] = tr
	}
	return f
}

func (f *fixture) vehicle(t testing.TB, id string) gamedata.Vehicle {
	for _, v := range f.vehicles {
		if v.ID == id {
			return v
		}
	}
	t.Fatalf("no vehicle %s", id)
	return gamedata.Vehicle{}
}

// autopilot is a minimal test driver: steer so the heading points back toward targetD.
// Real bots (racing line, avoidance, ULTs) live in internal/bots (M2).
func autopilot(c *CarState, tr *track.Track, targetD float64) Input {
	ahead := tr.At(c.S + 12)
	_ = ahead
	want := mathx.Clamp(-(c.D-targetD)*0.05, -0.3, 0.3)
	steer := 0
	if want-c.YawRel > 0.01 {
		steer = 1
	} else if want-c.YawRel < -0.01 {
		steer = -1
	}
	return Input{Steer: steer, Throttle: 1}
}

func TestVehicleStatsSumTo12(t *testing.T) {
	f := load(t)
	if len(f.vehicles) != 8 {
		t.Fatalf("want 8 vehicles, got %d", len(f.vehicles))
	}
	for _, v := range f.vehicles {
		s := v.Stats
		if s.Speed+s.Accel+s.Handling+s.Weight != 12 {
			t.Errorf("%s: stats sum %d", v.ID, s.Speed+s.Accel+s.Handling+s.Weight)
		}
		for _, x := range []int{s.Speed, s.Accel, s.Handling, s.Weight} {
			if x < 1 || x > 5 {
				t.Errorf("%s: stat %d out of 1–5", v.ID, x)
			}
		}
	}
}

func TestParamsMatchPlanFormulas(t *testing.T) {
	f := load(t)
	p := ParamsFor(f.vehicle(t, "bolt").Stats, f.bal.Stats)
	m := f.bal.Stats // linear mapping from balance.json (coefficients are tuned by cmd/balance)
	if math.Abs(p.TopSpeed-(m.TopSpeedBase+m.TopSpeedPerStat*5)) > 1e-12 {
		t.Errorf("bolt top speed %v", p.TopSpeed)
	}
	if math.Abs(p.TopSpeed/p.Accel-(m.AccelTimeBase-m.AccelTimePerStat*3)) > 1e-9 {
		t.Errorf("bolt accel time %v", p.TopSpeed/p.Accel)
	}
}

func TestAccelerationReachesTopSpeedOnTime(t *testing.T) {
	f := load(t)
	tr := f.tracks["sunny"]
	p := ParamsFor(f.vehicle(t, "glacier").Stats, f.bal.Stats)
	c := CarState{S: 0}
	dt := 1.0 / float64(f.bal.TickRate)
	accelTime := p.TopSpeed / p.Accel
	ticks := 0
	for c.Speed < p.TopSpeed && ticks < 1000 {
		StepCar(&c, Input{Throttle: 1}, p, NeutralMods, tr, &f.bal.Physics, dt)
		ticks++
	}
	got := float64(ticks) * dt
	if math.Abs(got-accelTime) > 2*dt {
		t.Fatalf("reached top speed after %.3fs, want %.3fs", got, accelTime)
	}
	if accelTime < 3 || accelTime > 4.2 {
		t.Fatalf("0→top %.2fs outside plan's ~3–4 s", accelTime)
	}
}

func TestCoastingSlowsDown(t *testing.T) {
	f := load(t)
	p := ParamsFor(f.vehicle(t, "glacier").Stats, f.bal.Stats)
	c := CarState{S: 10, Speed: 30}
	StepCar(&c, Input{}, p, NeutralMods, f.tracks["sunny"], &f.bal.Physics, 1.0/30)
	if c.Speed >= 30 {
		t.Fatalf("speed %v did not drop while coasting", c.Speed)
	}
}

func TestSpeedModsCapAndBleed(t *testing.T) {
	f := load(t)
	p := ParamsFor(f.vehicle(t, "glacier").Stats, f.bal.Stats)
	c := CarState{S: 10, Speed: p.TopSpeed}
	slow := Mods{SpeedMul: 0.5, AccelMul: 1, SteerMul: 1}
	for i := 0; i < 90; i++ {
		StepCar(&c, Input{Throttle: 1}, p, slow, f.tracks["sunny"], &f.bal.Physics, 1.0/30)
	}
	if math.Abs(c.Speed-p.TopSpeed*0.5) > 1e-9 {
		t.Fatalf("speed %v, want capped at %v", c.Speed, p.TopSpeed*0.5)
	}
}

func TestWallHitClampsSlowsAndReflects(t *testing.T) {
	f := load(t)
	tr := f.tracks["sunny"]
	p := ParamsFor(f.vehicle(t, "rhino").Stats, f.bal.Stats)
	c := CarState{S: 20, Speed: 30}
	hit := false
	for i := 0; i < 300 && !hit; i++ {
		before := c
		ev := StepCar(&c, Input{Steer: 1, Throttle: 1}, p, NeutralMods, tr, &f.bal.Physics, 1.0/30)
		if ev.WallHit {
			hit = true
			if c.YawRel >= 0 {
				t.Errorf("yaw %v not reflected away from the +d wall", c.YawRel)
			}
			if c.Speed > before.Speed*f.bal.Physics.WallSpeedFactor+p.Accel/30+1e-9 {
				t.Errorf("speed %v not reduced (before %v)", c.Speed, before.Speed)
			}
			if lim := tr.HalfWidth(c.S) - f.bal.Physics.CarHalfWidth; math.Abs(c.D-lim) > 1e-9 {
				t.Errorf("d %v not clamped to %v", c.D, lim)
			}
		}
	}
	if !hit {
		t.Fatal("never hit the wall while steering right")
	}
}

func TestRampLaunchAndLanding(t *testing.T) {
	f := load(t)
	tr := f.tracks["frosty"]
	if len(tr.Ramps) != 2 {
		t.Fatalf("frosty needs 2 ramps, has %d", len(tr.Ramps))
	}
	p := ParamsFor(f.vehicle(t, "bolt").Stats, f.bal.Stats)
	r := tr.Ramps[0]
	c := CarState{S: r.S - 30, Speed: 36}
	var launched, landed bool
	maxY := 0.0
	for i := 0; i < 120; i++ {
		ev := StepCar(&c, autopilot(&c, tr, 0), p, NeutralMods, tr, &f.bal.Physics, 1.0/30)
		launched = launched || ev.Launched
		if ev.Landed {
			landed = true
			break
		}
		maxY = math.Max(maxY, c.Y)
	}
	if !launched || !landed {
		t.Fatalf("launched=%v landed=%v", launched, landed)
	}
	wantPeak := r.Height + r.Vy*r.Vy/(2*f.bal.Physics.Gravity) // leaves from the lip
	if math.Abs(maxY-wantPeak) > 0.25 {
		t.Errorf("peak height %.2f, want ≈ %.2f", maxY, wantPeak)
	}
}

func TestCurvatureDriftRequiresSteering(t *testing.T) {
	// Going straight (no steering) through a corner must drift toward the outside wall.
	f := load(t)
	tr := f.tracks["neon"]
	p := ParamsFor(f.vehicle(t, "glacier").Stats, f.bal.Stats)
	// find the tightest corner
	bestS, bestK := 0.0, 0.0
	for i := 0; i < 2000; i++ {
		s := tr.Length * float64(i) / 2000
		if k := tr.Curvature(s); math.Abs(k) > math.Abs(bestK) {
			bestS, bestK = s, k
		}
	}
	c := CarState{S: bestS - 20, Speed: 30}
	walls := 0
	for i := 0; i < 60; i++ {
		if StepCar(&c, Input{Throttle: 1}, p, NeutralMods, tr, &f.bal.Physics, 1.0/30).WallHit {
			walls++
		}
	}
	// outside of the corner is the side opposite to the curvature sign
	if walls == 0 || math.Signbit(c.D) == math.Signbit(-bestK) && math.Abs(c.D) < 1 {
		t.Fatalf("no outward drift: walls=%d d=%.2f κ=%.4f", walls, c.D, bestK)
	}
}

func TestEveryVehicleFinishesEveryMap(t *testing.T) {
	f := load(t)
	for _, id := range gamedata.MapIDs() {
		tr := f.tracks[id]
		for _, v := range f.vehicles {
			w := NewWorld(tr, f.bal, []gamedata.Vehicle{v}, 3)
			for !w.Over() && w.Tick < 30*300 {
				c := w.Cars[0]
				c.Input = autopilot(&c.State, tr, 0)
				w.Step()
			}
			c := w.Cars[0]
			if !c.Finished {
				t.Errorf("%s/%s: not finished after %d ticks (lap %d)", id, v.ID, w.Tick, c.State.Lap)
				continue
			}
			lap2 := float64(c.LapTicks[1]-c.LapTicks[0]) / 30
			if lap2 < 25 || lap2 > 50 {
				t.Errorf("%s/%s: lap time %.1fs outside 25–50 s", id, v.ID, lap2)
			}
			if v.ID == "glacier" {
				t.Logf("%s/%s: lap 2 %.2fs", id, v.ID, lap2)
			}
		}
	}
}

func TestCollisionsSeparateCars(t *testing.T) {
	f := load(t)
	tr := f.tracks["sunny"]
	w := NewWorld(tr, f.bal, []gamedata.Vehicle{f.vehicle(t, "rhino"), f.vehicle(t, "bolt")}, 3)
	w.Cars[0].State = CarState{S: 100, D: 0, Speed: 20}
	w.Cars[1].State = CarState{S: 101, D: 0.5, Speed: 20}
	w.Step()
	a, b := w.Cars[0].State, w.Cars[1].State
	ph := f.bal.Physics
	ox := 2*ph.CarHalfLength - math.Abs(mathx.WrapDelta(a.S, b.S, tr.Length))
	oy := 2*ph.CarHalfWidth - math.Abs(b.D-a.D)
	if ox > 1e-6 && oy > 1e-6 {
		t.Fatalf("car boxes still overlap: ox=%.3f oy=%.3f", ox, oy)
	}
	bumps := 0
	for _, e := range w.Events {
		if e.Kind == "bump" {
			bumps++
		}
	}
	if bumps != 1 {
		t.Fatalf("want 1 bump event, got %d", bumps)
	}
}

func TestHeavierCarIsPushedLess(t *testing.T) {
	f := load(t)
	tr := f.tracks["sunny"]
	w := NewWorld(tr, f.bal, []gamedata.Vehicle{f.vehicle(t, "rhino"), f.vehicle(t, "bolt")}, 3)
	w.Cars[0].State = CarState{S: 100, D: -0.5}
	w.Cars[1].State = CarState{S: 100, D: 0.5}
	w.collide()
	moveRhino := math.Abs(w.Cars[0].State.D + 0.5)
	moveBolt := math.Abs(w.Cars[1].State.D - 0.5)
	if moveRhino >= moveBolt {
		t.Fatalf("rhino (heavy) moved %.3f, bolt moved %.3f", moveRhino, moveBolt)
	}
}

func TestLapsCountOnceAcrossBackAndForth(t *testing.T) {
	f := load(t)
	tr := f.tracks["sunny"]
	w := NewWorld(tr, f.bal, []gamedata.Vehicle{f.vehicle(t, "glacier")}, 3)
	c := w.Cars[0]
	c.State = CarState{S: 1, Lap: 1}
	w.updateLaps()
	c.State.Lap = 0 // pushed back over the line
	w.updateLaps()
	c.State.Lap = 1 // and forward again
	w.updateLaps()
	if len(c.LapTicks) != 1 {
		t.Fatalf("lap counted %d times", len(c.LapTicks))
	}
}

func TestRankingFinishedThenProgress(t *testing.T) {
	f := load(t)
	tr := f.tracks["sunny"]
	vs := []gamedata.Vehicle{f.vehicle(t, "bolt"), f.vehicle(t, "rhino"), f.vehicle(t, "goo"), f.vehicle(t, "hook")}
	w := NewWorld(tr, f.bal, vs, 3)
	w.Cars[0].State = CarState{S: 500, Lap: 2}
	w.Cars[1].State = CarState{S: 10, Lap: 3}
	w.Cars[1].Finished, w.Cars[1].FinishTick = true, 900
	w.Cars[2].State = CarState{S: 20, Lap: 3}
	w.Cars[2].Finished, w.Cars[2].FinishTick = true, 850
	w.Cars[3].State = CarState{S: 600, Lap: 2}
	got := w.Ranking()
	want := []int{2, 1, 3, 0}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("ranking %v, want %v", got, want)
		}
	}
}

func TestRaceEndsAfterFinishWindow(t *testing.T) {
	f := load(t)
	tr := f.tracks["sunny"]
	w := NewWorld(tr, f.bal, []gamedata.Vehicle{f.vehicle(t, "bolt"), f.vehicle(t, "rhino")}, 1)
	for !w.Over() && w.Tick < 30*200 {
		w.Cars[0].Input = autopilot(&w.Cars[0].State, tr, -4)
		w.Cars[1].Input = Input{} // never moves
		w.Step()
	}
	if !w.Cars[0].Finished || w.Cars[1].Finished {
		t.Fatalf("finished: %v %v", w.Cars[0].Finished, w.Cars[1].Finished)
	}
	window := int(f.bal.Race.FinishWindowS * 30)
	if w.EndTick != w.Cars[0].FinishTick+window {
		t.Fatalf("end tick %d, want %d", w.EndTick, w.Cars[0].FinishTick+window)
	}
}

// runRace drives 8 cars with the autopilot plus seeded noise and returns the final hash.
func runRace(f *fixture, mapID string, seed uint32, ticks int) string {
	tr := f.tracks[mapID]
	w := NewWorld(tr, f.bal, f.vehicles, 3)
	rng := mathx.NewRng(seed)
	targets := make([]float64, len(w.Cars))
	for i := 0; i < ticks && !w.Over(); i++ {
		for j, c := range w.Cars {
			if i%45 == 0 {
				targets[j] = (rng.Float()*2 - 1) * 6
			}
			c.Input = autopilot(&c.State, tr, targets[j])
			if rng.Float() < 0.05 {
				c.Input.Steer = rng.Intn(3) - 1
			}
		}
		w.Step()
	}
	return w.Hash()
}

func TestDeterminism(t *testing.T) {
	f := load(t)
	for _, id := range gamedata.MapIDs() {
		want := runRace(f, id, 1234, 3000)
		var wg sync.WaitGroup
		got := make([]string, 4)
		for k := range got {
			wg.Add(1)
			go func(k int) {
				defer wg.Done()
				got[k] = runRace(f, id, 1234, 3000)
			}(k)
		}
		wg.Wait()
		for _, g := range got {
			if g != want {
				t.Fatalf("%s: hash %s != %s", id, g, want)
			}
		}
		if other := runRace(f, id, 999, 3000); other == want {
			t.Fatalf("%s: different seeds gave the same hash", id)
		}
	}
}

func BenchmarkWorldStep8Cars(b *testing.B) {
	f := load(b)
	tr := f.tracks["neon"]
	w := NewWorld(tr, f.bal, f.vehicles, 3)
	for i := 0; i < b.N; i++ {
		for _, c := range w.Cars {
			c.Input = autopilot(&c.State, tr, 0)
		}
		w.Step()
		if w.Over() {
			w = NewWorld(tr, f.bal, f.vehicles, 3)
		}
	}
}

// Rear-end hit: the faster car behind slows, the car ahead is shoved forward; nobody overlaps.
func TestRearEndImpactExchangesSpeed(t *testing.T) {
	f := load(t)
	tr := f.tracks["sunny"]
	w := NewWorld(tr, f.bal, []gamedata.Vehicle{f.vehicle(t, "bolt"), f.vehicle(t, "glacier")}, 3)
	w.Cars[0].State = CarState{S: 100, D: 0, Speed: 35}
	w.Cars[1].State = CarState{S: 103.5, D: 0.2, Speed: 20}
	w.collide()
	a, b := w.Cars[0].State, w.Cars[1].State
	if a.Speed >= 35 || b.Speed <= 20 {
		t.Fatalf("no impact: rear %.1f front %.1f", a.Speed, b.Speed)
	}
	if gap := mathx.WrapDelta(a.S, b.S, tr.Length); gap < 2*f.bal.Physics.CarHalfLength-1e-6 {
		t.Fatalf("still overlapping lengthwise: gap %.3f", gap)
	}
}

// Side contact: cars bounce apart sideways and their headings turn away from each other.
func TestSideContactBouncesApart(t *testing.T) {
	f := load(t)
	tr := f.tracks["sunny"]
	w := NewWorld(tr, f.bal, []gamedata.Vehicle{f.vehicle(t, "bolt"), f.vehicle(t, "rhino")}, 3)
	w.Cars[0].State = CarState{S: 100, D: -0.8, Speed: 30, YawRel: 0.2}   // steering into car 1
	w.Cars[1].State = CarState{S: 100.5, D: 0.8, Speed: 30, YawRel: -0.1} // steering into car 0
	w.collide()
	a, b := w.Cars[0].State, w.Cars[1].State
	if b.D-a.D < 2*f.bal.Physics.CarHalfWidth-1e-6 {
		t.Fatalf("still overlapping sideways: %.3f", b.D-a.D)
	}
	if a.YawRel >= 0.2 || b.YawRel <= -0.1 {
		t.Fatalf("headings not deflected: %.3f %.3f", a.YawRel, b.YawRel)
	}
	if math.Abs(a.D+0.8) <= math.Abs(b.D-0.8) {
		t.Fatalf("heavy rhino moved more than light bolt")
	}
}
