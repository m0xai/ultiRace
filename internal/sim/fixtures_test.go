package sim

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"testing"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/track"
)

// Conformance fixtures for the GDScript mirror (GAME_PLAN §3.3). Regenerate with
// `make fixtures` (sets ULTIRACE_WRITE_FIXTURES=1); otherwise this test fails if the files
// on disk differ from what the current code produces.

const fixtureDir = "../../gamedata/fixtures"

type trackFixture struct {
	Map     string      `json:"map"`
	Length  float64     `json:"length"`
	Columns []string    `json:"columns"`
	Samples [][]float64 `json:"samples"`
}

type physicsFixture struct {
	Name    string      `json:"name"`
	Map     string      `json:"map"`
	Vehicle string      `json:"vehicle"`
	Dt      float64     `json:"dt"`
	Params  CarParams   `json:"params"`
	Mods    Mods        `json:"mods"`
	Start   []float64   `json:"start"`   // s, d, yawRel, y, vy, speed, lap
	Inputs  [][2]int    `json:"inputs"`  // [steer, throttle] per tick
	Columns []string    `json:"columns"` // per-tick state layout
	States  [][]float64 `json:"states"`
}

func stateRow(c CarState) []float64 {
	return []float64{c.S, c.D, c.YawRel, c.Y, c.Vy, c.Speed, float64(c.Lap)}
}

func b2f(b bool) float64 {
	if b {
		return 1
	}
	return 0
}

func buildTrackFixture(tr *track.Track, n int) trackFixture {
	f := trackFixture{
		Map: tr.ID, Length: tr.Length,
		Columns: []string{"s", "px", "py", "pz", "tx", "ty", "tz", "nx", "ny", "nz", "curvature", "halfWidth", "bank"},
	}
	// n evenly spaced samples plus a few off-range values to test wrapping
	ss := make([]float64, 0, n+3)
	for i := 0; i < n; i++ {
		ss = append(ss, tr.Length*float64(i)/float64(n)+0.37)
	}
	ss = append(ss, -12.5, tr.Length+33.3, 2*tr.Length+1)
	for _, s := range ss {
		m := tr.At(s)
		f.Samples = append(f.Samples, []float64{s, m.Pos.X, m.Pos.Y, m.Pos.Z, m.Tangent.X, m.Tangent.Y, m.Tangent.Z,
			m.Normal.X, m.Normal.Y, m.Normal.Z, m.Curvature, m.HalfWidth, m.Bank})
	}
	return f
}

type scenario struct {
	name, mapID, vehicle string
	start                CarState
	mods                 Mods
	inputs               func(i int, c *CarState, tr *track.Track, rng *mathx.Rng) Input
}

func scenarios() []scenario {
	full := func(int, *CarState, *track.Track, *mathx.Rng) Input { return Input{Throttle: 1} }
	return []scenario{
		{"straight_full_throttle", "sunny", "bolt", CarState{S: 5}, NeutralMods, full},
		{"slalom", "sunny", "glacier", CarState{S: 5, Speed: 20}, NeutralMods,
			func(i int, _ *CarState, _ *track.Track, _ *mathx.Rng) Input {
				st := 1
				if (i/20)%2 == 1 {
					st = -1
				}
				return Input{Steer: st, Throttle: 1}
			}},
		{"wall_hits", "sunny", "rhino", CarState{S: 5, Speed: 25}, NeutralMods,
			func(i int, _ *CarState, _ *track.Track, _ *mathx.Rng) Input {
				st := 1
				if i >= 150 {
					st = -1
				}
				return Input{Steer: st, Throttle: 1}
			}},
		{"coast_and_lap_wrap", "neon", "twister", CarState{S: -40, Speed: 30, Lap: -1}, NeutralMods,
			func(i int, c *CarState, tr *track.Track, _ *mathx.Rng) Input {
				in := autopilot(c, tr, 2)
				if i > 150 {
					in.Throttle = 0
				}
				return in
			}},
		{"jumps", "frosty", "phantom", CarState{S: 120, Speed: 30}, NeutralMods,
			func(_ int, c *CarState, tr *track.Track, _ *mathx.Rng) Input { return autopilot(c, tr, 0) }},
		{"random_inputs_slowed", "neon", "goo", CarState{S: 600, D: 3, Speed: 15}, Mods{SpeedMul: 0.8, AccelMul: 1.2, SteerMul: 0.7},
			func(_ int, _ *CarState, _ *track.Track, rng *mathx.Rng) Input {
				return Input{Steer: rng.Intn(3) - 1, Throttle: boolInt(rng.Float() < 0.8)}
			}},
	}
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

func buildPhysicsFixture(t *testing.T, f *fixture, sc scenario) physicsFixture {
	tr := f.tracks[sc.mapID]
	v := f.vehicle(t, sc.vehicle)
	p := ParamsFor(v.Stats, f.bal.Stats)
	dt := 1.0 / float64(f.bal.TickRate)
	if sc.start.S < 0 { // negative start s = metres before the start line
		sc.start.S += tr.Length
	}
	out := physicsFixture{
		Name: sc.name, Map: sc.mapID, Vehicle: sc.vehicle, Dt: dt, Params: p, Mods: sc.mods,
		Start:   stateRow(sc.start),
		Columns: []string{"s", "d", "yawRel", "y", "vy", "speed", "lap", "wallHit", "launched", "landed", "crossedStart"},
	}
	c := sc.start
	rng := mathx.NewRng(7)
	for i := 0; i < 300; i++ {
		in := sc.inputs(i, &c, tr, rng)
		ev := StepCar(&c, in, p, sc.mods, tr, &f.bal.Physics, dt)
		out.Inputs = append(out.Inputs, [2]int{in.Steer, in.Throttle})
		row := append(stateRow(c), b2f(ev.WallHit), b2f(ev.Launched), b2f(ev.Landed), float64(ev.CrossedStart))
		out.States = append(out.States, row)
	}
	return out
}

func TestFixtures(t *testing.T) {
	f := load(t)
	files := map[string]any{}
	for _, id := range gamedata.MapIDs() {
		files["track_"+id+".json"] = buildTrackFixture(f.tracks[id], f.bal.Track.FixtureSamples)
	}
	for _, sc := range scenarios() {
		pf := buildPhysicsFixture(t, f, sc)
		files["physics_"+sc.name+".json"] = pf
		checkScenarioCoverage(t, pf)
	}

	write := os.Getenv("ULTIRACE_WRITE_FIXTURES") == "1"
	if write {
		if err := os.MkdirAll(fixtureDir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for name, v := range files {
		data, err := json.MarshalIndent(v, "", " ")
		if err != nil {
			t.Fatal(err)
		}
		data = append(data, '\n')
		path := filepath.Join(fixtureDir, name)
		if write {
			if err := os.WriteFile(path, data, 0o644); err != nil {
				t.Fatal(err)
			}
			continue
		}
		old, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("missing fixture %s: run make fixtures", name)
		}
		if bytes.Equal(old, data) {
			continue
		}
		// Byte equality fails across CPU architectures: Go may fuse x*y+z into FMA on arm64
		// but not on amd64, changing the last bits. Compare numerically instead.
		var a, b any
		if err := json.Unmarshal(old, &a); err != nil {
			t.Fatal(err)
		}
		if err := json.Unmarshal(data, &b); err != nil {
			t.Fatal(err)
		}
		if where := jsonDiff(a, b, ""); where != "" {
			t.Errorf("fixture %s is stale at %s: run make fixtures && make sync", name, where)
		}
	}
}

// jsonDiff returns the path of the first difference beyond 1e-7 (relative), or "".
func jsonDiff(a, b any, path string) string {
	switch av := a.(type) {
	case float64:
		bv, ok := b.(float64)
		if !ok || math.Abs(av-bv) > 1e-7*math.Max(1, math.Abs(av)) {
			return path
		}
	case []any:
		bv, ok := b.([]any)
		if !ok || len(av) != len(bv) {
			return path
		}
		for i := range av {
			if d := jsonDiff(av[i], bv[i], fmt.Sprintf("%s[%d]", path, i)); d != "" {
				return d
			}
		}
	case map[string]any:
		bv, ok := b.(map[string]any)
		if !ok || len(av) != len(bv) {
			return path
		}
		for k := range av {
			if d := jsonDiff(av[k], bv[k], path+"."+k); d != "" {
				return d
			}
		}
	default:
		if a != b {
			return path
		}
	}
	return ""
}

// checkScenarioCoverage makes sure each scenario exercises what its name promises.
func checkScenarioCoverage(t *testing.T, pf physicsFixture) {
	var walls, launches, lands, crossings float64
	for _, r := range pf.States {
		walls += r[7]
		launches += r[8]
		lands += r[9]
		crossings += math.Abs(r[10])
		for _, x := range r {
			if math.IsNaN(x) || math.IsInf(x, 0) {
				t.Fatalf("%s: non-finite state", pf.Name)
			}
		}
	}
	switch pf.Name {
	case "wall_hits":
		if walls < 2 {
			t.Errorf("wall_hits: only %v wall hits", walls)
		}
	case "jumps":
		if launches < 1 || lands < 1 {
			t.Errorf("jumps: launches=%v lands=%v", launches, lands)
		}
	case "coast_and_lap_wrap":
		if crossings < 1 {
			t.Errorf("coast_and_lap_wrap: never crossed the start line")
		}
	}
}
