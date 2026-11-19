// Package balance runs headless bot races and measures the GAME_PLAN §2.9 targets.
package balance

import (
	"fmt"
	"math"
	"runtime"
	"sort"
	"strings"
	"sync"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/abilities"
	"github.com/m0xai/ultiRace/internal/bots"
	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/room"
	"github.com/m0xai/ultiRace/internal/sim"
)

// Race is the outcome of one simulated race.
type Race struct {
	Map         string
	Positions   map[string]int     // vehicle → finishing position (1-based)
	CCShare     map[string]float64 // vehicle → share of race time hard-CC'd
	CCPerLap    map[string]float64 // vehicle → hard CCs received per lap
	UltUses     map[string]int
	LeadChanges int
	GapS        float64 // time gap first → last at the end (s)
	LapS        float64 // winner's average lap time (s)
	Ticks       int
}

// FormNoise is the spread of per-race bot line accuracy (m); 0 = identical deterministic bots.
var FormNoise = 3.0

// Drive applies bot input for every car (also used by rooms for bot seats).
func Drive(w *sim.World, ctrls []*bots.Controller, startDelay []int) {
	states := make([]*sim.CarState, len(w.Cars))
	for i, c := range w.Cars {
		states[i] = &c.State
	}
	for i, c := range w.Cars {
		others := make([]*sim.CarState, 0, len(states)-1)
		for j, s := range states {
			if j != i {
				others = append(others, s)
			}
		}
		in := ctrls[i].Decide(&c.State, others, w.Track)
		if w.Tick < startDelay[i] {
			in.Throttle = 0
		}
		in.Ability = w.UltReady(i) && bots.WantsUlt(w, i)
		c.Input = in
	}
}

// RunRace simulates one 8-bot race with a shuffled grid on mapID.
func RunRace(d *room.Data, mapID string, laps int, seed uint32) Race {
	rng := mathx.NewRng(seed)
	vs := append([]gamedata.Vehicle(nil), d.Vehicles...)
	for i := len(vs) - 1; i > 0; i-- {
		j := rng.Intn(i + 1)
		vs[i], vs[j] = vs[j], vs[i]
	}
	tr := d.Tracks[mapID]
	w := sim.NewWorld(tr, d.Bal, vs, laps)
	w.Ults = abilities.New(d.Bal)
	ctrls := make([]*bots.Controller, len(vs))
	delay := make([]int, len(vs))
	for i := range ctrls {
		// equal average skill, human-like race-to-race form: every vehicle draws from the same
		// distribution (line accuracy and reaction), so no vehicle is favoured
		form := bots.Difficulty{ReactionTicks: 3 + rng.Intn(7), LineNoise: 0.5 + rng.Float()*FormNoise}
		ctrls[i] = bots.NewController(d.Lines[mapID], form, rng.Uint32())
		ctrls[i].SetPhysics(w.Cars[i].Params, &d.Bal.Physics)
		delay[i] = 1 + rng.Intn(14) // human-like reaction at GO: some get a start boost
	}
	for !w.Over() && w.Tick < d.Bal.Ticks(600) {
		Drive(w, ctrls, delay)
		w.Step()
	}
	r := Race{Map: mapID, Positions: map[string]int{}, CCShare: map[string]float64{}, CCPerLap: map[string]float64{},
		UltUses: map[string]int{}, LeadChanges: w.LeadChanges, Ticks: w.Tick}
	for p, id := range w.Ranking() {
		r.Positions[w.Cars[id].Vehicle] = p + 1
	}
	first, last := math.Inf(1), 0.0
	L := tr.Length
	for _, c := range w.Cars {
		r.CCShare[c.Vehicle] = float64(c.Status.HardCCTicks) / float64(w.Tick)
		r.CCPerLap[c.Vehicle] = float64(c.Status.HardCCReceived) / float64(laps)
		r.UltUses[c.Vehicle] = c.UltUses
		t := float64(c.FinishTick) / float64(d.Bal.TickRate)
		if !c.Finished { // estimate: time to cover the rest at the car's lap pace so far
			done := math.Max(c.State.Progress(L), 1)
			t = float64(w.Tick) / float64(d.Bal.TickRate) * float64(laps) * L / done
		}
		first = math.Min(first, t)
		last = math.Max(last, t)
	}
	r.GapS = last - first
	r.LapS = first / float64(laps)
	return r
}

// Run simulates n races in parallel (deterministic per seed and race index).
func Run(d *room.Data, n, laps int, seed uint32) []Race {
	out := make([]Race, n)
	var wg sync.WaitGroup
	jobs := make(chan int)
	for range runtime.NumCPU() {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range jobs {
				m := d.MapIDs[i%len(d.MapIDs)]
				out[i] = RunRace(d, m, laps, seed+uint32(i)*7919)
			}
		}()
	}
	for i := range n {
		jobs <- i
	}
	close(jobs)
	wg.Wait()
	return out
}

// Target is one §2.9 check.
type Target struct {
	Name   string
	Value  string
	Target string
	OK     bool
}

// Summary aggregates races.
type Summary struct {
	Loss     float64 // weighted target violations (0 = all targets met), used by the tuner
	LapS     float64
	Races    int
	WinRate  map[string]float64
	AvgPos   map[string]float64
	UltPerR  map[string]float64
	Targets  []Target
	Vehicles []string
}

func median(xs []float64) float64 {
	s := append([]float64(nil), xs...)
	sort.Float64s(s)
	if len(s) == 0 {
		return 0
	}
	return s[len(s)/2]
}

// Summarize checks the §2.9 targets.
func Summarize(rs []Race) Summary {
	s := Summary{Races: len(rs), WinRate: map[string]float64{}, AvgPos: map[string]float64{}, UltPerR: map[string]float64{}}
	var ccShares, ccPerLap, gaps, leads []float64
	worstCC := 0.0
	for _, r := range rs {
		for v, p := range r.Positions {
			s.AvgPos[v] += float64(p)
			if p == 1 {
				s.WinRate[v]++
			}
			s.UltPerR[v] += float64(r.UltUses[v])
			ccShares = append(ccShares, r.CCShare[v])
			ccPerLap = append(ccPerLap, r.CCPerLap[v])
			worstCC = math.Max(worstCC, r.CCShare[v])
		}
		gaps = append(gaps, r.GapS)
		leads = append(leads, float64(r.LeadChanges))
	}
	for v := range s.AvgPos {
		s.Vehicles = append(s.Vehicles, v)
	}
	sort.Strings(s.Vehicles)
	n := float64(len(rs))
	winOK, posOK := true, true
	minW, maxW, minP, maxP := 1.0, 0.0, 9.0, 0.0
	for _, v := range s.Vehicles {
		s.WinRate[v] /= n
		s.AvgPos[v] /= n
		s.UltPerR[v] /= n
		winOK = winOK && math.Abs(s.WinRate[v]-0.125) <= 0.04
		posOK = posOK && math.Abs(s.AvgPos[v]-4.5) <= 0.6
		minW, maxW = math.Min(minW, s.WinRate[v]), math.Max(maxW, s.WinRate[v])
		minP, maxP = math.Min(minP, s.AvgPos[v]), math.Max(maxP, s.AvgPos[v])
	}
	avg := func(xs []float64) float64 {
		t := 0.0
		for _, x := range xs {
			t += x
		}
		return t / math.Max(1, float64(len(xs)))
	}
	ccAvg, ccLap, lead, gap := avg(ccShares), avg(ccPerLap), avg(leads), median(gaps)
	var laps []float64
	for _, r := range rs {
		laps = append(laps, r.LapS)
	}
	s.LapS = avg(laps)
	over := func(x float64) float64 { return math.Max(0, x) }
	for _, v := range s.Vehicles {
		s.Loss += 10*over(math.Abs(s.WinRate[v]-0.125)-0.035) + over(math.Abs(s.AvgPos[v]-4.5)-0.5)
	}
	s.Loss += 20*over(ccAvg-0.075) + 10*over(worstCC-0.14) + over(ccLap-1.4) + 0.5*over(3.3-lead) + 0.2*over(gap-11.5)
	s.Loss += 0.3*over(33-s.LapS) + 0.3*over(s.LapS-45)
	s.Targets = []Target{
		{"Win rate per vehicle", fmt.Sprintf("%.1f–%.1f %%", minW*100, maxW*100), "12.5 % ± 4 %", winOK},
		{"Average finish position per vehicle", fmt.Sprintf("%.2f–%.2f", minP, maxP), "4.5 ± 0.6", posOK},
		{"Share of race time hard-CC'd (avg)", fmt.Sprintf("%.1f %%", ccAvg*100), "≤ 8 %", ccAvg <= 0.08},
		{"Share of race time hard-CC'd (worst player)", fmt.Sprintf("%.1f %%", worstCC*100), "≤ 15 %", worstCC <= 0.15},
		{"Hard CCs received per player per lap", fmt.Sprintf("%.2f", ccLap), "≤ 1.5", ccLap <= 1.5},
		{"Lead changes per race (avg)", fmt.Sprintf("%.1f", lead), "≥ 3", lead >= 3},
		{"Gap 1st → last at the finish (median)", fmt.Sprintf("%.1f s", gap), "≤ 12 s", gap <= 12},
	}
	return s
}

// AllOK reports whether every target passed.
func (s Summary) AllOK() bool {
	for _, t := range s.Targets {
		if !t.OK {
			return false
		}
	}
	return true
}

// Markdown renders docs/BALANCE_REPORT.md.
func (s Summary) Markdown(laps int) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# Balance report\n\nGenerated by `make balance` (`go run ./cmd/balance`): %d races, 8 equal-skill bots,\n", s.Races)
	fmt.Fprintf(&b, "shuffled grid (every vehicle every race), maps rotated, %d laps. Targets: GAME_PLAN §2.9.\n\n", laps)
	b.WriteString("| Metric | Value | Target | |\n|---|---|---|---|\n")
	for _, t := range s.Targets {
		mark := "✅"
		if !t.OK {
			mark = "❌"
		}
		fmt.Fprintf(&b, "| %s | %s | %s | %s |\n", t.Name, t.Value, t.Target, mark)
	}
	fmt.Fprintf(&b, "| Winner's lap time (plan: 35–45 s) | %.1f s | 33–45 s | %s |\n", s.LapS, map[bool]string{true: "✅", false: "❌"}[s.LapS >= 33 && s.LapS <= 45])
	b.WriteString("\n| Vehicle | Win rate | Avg position | ULT uses / race |\n|---|---|---|---|\n")
	for _, v := range s.Vehicles {
		fmt.Fprintf(&b, "| %s | %.1f %% | %.2f | %.1f |\n", v, s.WinRate[v]*100, s.AvgPos[v], s.UltPerR[v])
	}
	return b.String()
}

// TimeTrial returns each vehicle's solo lap time (s) per map with bot driving and no ULTs.
func TimeTrial(d *room.Data, laps int) map[string]map[string]float64 {
	out := map[string]map[string]float64{}
	for _, m := range d.MapIDs {
		out[m] = map[string]float64{}
		for _, v := range d.Vehicles {
			w := sim.NewWorld(d.Tracks[m], d.Bal, []gamedata.Vehicle{v}, laps)
			ctrl := bots.NewController(d.Lines[m], bots.Difficulty{ReactionTicks: 6}, 1)
			ctrl.SetPhysics(w.Cars[0].Params, &d.Bal.Physics)
			for !w.Over() && w.Tick < d.Bal.Ticks(600) {
				w.Cars[0].Input = ctrl.Decide(&w.Cars[0].State, nil, w.Track)
				w.Step()
			}
			c := w.Cars[0]
			out[m][v.ID] = float64(c.FinishTick) / float64(d.Bal.TickRate) / float64(laps)
		}
	}
	return out
}
