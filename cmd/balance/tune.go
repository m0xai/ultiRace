package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/balance"
	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/room"
)

// knob is one tunable number in balance.json (path) with bounds.
type knob struct {
	path   []string
	lo, hi float64
}

// Stage-2 knobs: ULTs, catch-up and contact only (stage 1 owns pace: see paceKnobs).
var knobs = []knob{
	{[]string{"stats", "wallReflectPerStat"}, 0.0, 0.1},
	{[]string{"stats", "massPerStat"}, 0.1, 0.4},
	{[]string{"stats", "hardCCReductionPerWeightAbove3"}, 0.0, 0.12},
	{[]string{"catchup", "draftBonus"}, 0.04, 0.2},
	{[]string{"catchup", "comebackBonus"}, 0.02, 0.15},
	{[]string{"catchup", "comebackGapM"}, 40, 150},
	{[]string{"catchup", "rechargeLast"}, 1.1, 2.0},
	{[]string{"catchup", "rechargeFirst"}, 0.6, 1.0},
	{[]string{"ults", "nitro", "speed"}, 0.15, 0.35},
	{[]string{"ults", "nitro", "cooldownS"}, 8, 14},
	{[]string{"ults", "phase", "speed"}, 0.0, 0.15},
	{[]string{"ults", "grapple", "selfBoost"}, 0.2, 0.5},
	{[]string{"ults", "emp", "slow"}, 0.2, 0.4},
	{[]string{"ults", "goo", "slow"}, 0.25, 0.45},
	{[]string{"ults", "tornado", "spinS"}, 0.8, 1.8},
	{[]string{"ults", "ram", "spinS"}, 0.7, 1.6},
	{[]string{"ults", "ice", "steerMul"}, 0.2, 0.5},
	{[]string{"ults", "ram", "speed"}, 0.3, 0.6},
	{[]string{"ults", "goo", "aheadM"}, 25, 45},
	{[]string{"ults", "emp", "radiusM"}, 12, 22},
	{[]string{"ults", "tornado", "speedFactor"}, 1.15, 1.5},
	{[]string{"catchup", "startBoostSpeed"}, 0.1, 0.35},
}

func toMap(b *gamedata.Balance) map[string]any {
	data, _ := json.Marshal(b)
	var m map[string]any
	_ = json.Unmarshal(data, &m)
	return m
}

func fromMap(m map[string]any) *gamedata.Balance {
	data, _ := json.Marshal(m)
	var b gamedata.Balance
	_ = json.Unmarshal(data, &b)
	return &b
}

func get(m map[string]any, p []string) float64 {
	for _, k := range p[:len(p)-1] {
		m = m[k].(map[string]any)
	}
	return m[p[len(p)-1]].(float64)
}

func set(m map[string]any, p []string, v float64) {
	for _, k := range p[:len(p)-1] {
		m = m[k].(map[string]any)
	}
	m[p[len(p)-1]] = math.Round(v*1000) / 1000
}

func evaluate(bal *gamedata.Balance, races, laps int, seed uint32) balance.Summary {
	d, err := room.LoadDataWith(bal)
	if err != nil {
		panic(err)
	}
	return balance.Summarize(balance.Run(d, races, laps, seed))
}

// tune runs a (1+1) random search over the knobs and writes the best balance to path.
// withPace adds the stage-1 pace knobs (with their floors) to the search.
func tune(bal *gamedata.Balance, iters, races, laps int, path string, withPace bool) *gamedata.Balance {
	ks := knobs
	if withPace {
		ks = append(append([]knob(nil), knobs...), paceKnobs...)
	}
	rng := mathx.NewRng(12345)
	best := toMap(bal)
	bestS := evaluate(bal, races, laps, 1)
	fmt.Printf("start loss %.3f\n", bestS.Loss)
	for it := 0; it < iters && bestS.Loss > 0; it++ {
		cand := toMap(fromMap(best))
		n := 1 + rng.Intn(3)
		for range n {
			k := ks[rng.Intn(len(ks))]
			v := get(cand, k.path)
			step := (k.hi - k.lo) * 0.15 * (rng.Float()*2 - 1)
			set(cand, k.path, mathx.Clamp(v+step, k.lo, k.hi))
		}
		s := evaluate(fromMap(cand), races, laps, 1)
		if s.Loss < bestS.Loss {
			best, bestS = cand, s
			fmt.Printf("iter %d loss %.3f lap %.1fs\n", it, s.Loss, s.LapS)
		}
	}
	out := fromMap(best)
	data, _ := json.MarshalIndent(out, "", "  ")
	if err := os.WriteFile(path, append(data, '\n'), 0o644); err != nil {
		panic(err)
	}
	fmt.Printf("best loss %.3f written to %s\n", bestS.Loss, path)
	return out
}

// Floors keep every stat meaningful (vehicle identity): Speed ≥ 0.8 m/s per point, Accel
// ≥ 0.2 s per point; handling and corners do the balancing.
var paceKnobs = []knob{
	{[]string{"stats", "topSpeedPerStat"}, 0.8, 1.6},
	{[]string{"stats", "accelTimePerStat"}, 0.2, 0.6},
	{[]string{"stats", "steerRateBase"}, 0.4, 1.6},
	{[]string{"stats", "steerRatePerStat"}, 0.1, 0.6},
	{[]string{"physics", "steerHighSpeedFalloff"}, 0.15, 0.5},
	{[]string{"physics", "coastDecel"}, 5, 12},
}

// paceLoss: spread of solo lap times between vehicles per map, plus lap times outside 35–42 s.
func paceLoss(bal *gamedata.Balance) (float64, float64) {
	d, err := room.LoadDataWith(bal)
	if err != nil {
		panic(err)
	}
	tt := balance.TimeTrial(d, 2)
	loss, sum, n := 0.0, 0.0, 0.0
	for _, m := range d.MapIDs {
		lo, hi := math.Inf(1), 0.0
		for _, v := range tt[m] {
			lo, hi = math.Min(lo, v), math.Max(hi, v)
			sum += v
			n++
			loss += 0.5*math.Max(0, 35-v) + 0.5*math.Max(0, v-42)
		}
		loss += hi - lo
	}
	return loss, sum / n
}

// tunePace equalises solo pace across vehicles (stage 1 of tuning).
func tunePace(bal *gamedata.Balance, iters int, path string) *gamedata.Balance {
	rng := mathx.NewRng(777)
	best := toMap(bal)
	bestL, avg := paceLoss(bal)
	fmt.Printf("pace start loss %.3f avg lap %.2f\n", bestL, avg)
	for it := 0; it < iters; it++ {
		cand := toMap(fromMap(best))
		for range 1 + rng.Intn(2) {
			k := paceKnobs[rng.Intn(len(paceKnobs))]
			step := (k.hi - k.lo) * 0.12 * (rng.Float()*2 - 1)
			set(cand, k.path, mathx.Clamp(get(cand, k.path)+step, k.lo, k.hi))
		}
		l, a := paceLoss(fromMap(cand))
		if l < bestL {
			best, bestL, avg = cand, l, a
			fmt.Printf("iter %d pace loss %.3f avg lap %.2f\n", it, l, a)
		}
	}
	out := fromMap(best)
	data, _ := json.MarshalIndent(out, "", "  ")
	_ = os.WriteFile(path, append(data, '\n'), 0o644)
	return out
}
