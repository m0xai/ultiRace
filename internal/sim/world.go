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
	Ult      string
	Weight   int
	Params   CarParams
	State    CarState
	Input    Input
	Status   Status
	Flags    uint16  // effect bits of the last tick (snapshot)
	UltLeft  float64 // seconds of cooldown left (0 = ready)
	UltUses  int
	Finished bool
	// PrevThrottle/prevAbility detect rising edges (start boost, ULT button).
	PrevThrottle int
	prevAbility  bool
	// FinishTick is the tick on which the car completed its last lap (valid if Finished).
	FinishTick int
	// LapTicks holds the tick at which each lap was completed (index 0 = lap 1).
	LapTicks []int
}

// Event is something that happened during a tick (sent to clients as `ev`).
type Event struct {
	Tick  int
	Kind  string // "wallHit", "lap", "finished", "bump", "launch", "land", "abilityUsed", "hit", "startBoost"
	Car   int
	Other int     // second car for "bump" / source car for "hit"
	Value float64 // impact speed, lap number, …
	Ticks int     // lap/finish tick count since race start
	Ult   string  // ult id for "abilityUsed" / "hit"
}

// Trap is a ground hazard (ice, goo) in track space.
type Trap struct {
	Kind  string
	Owner int
	S     float64 // start of the patch
	D     float64
	Len   float64
	HalfW float64
	Until int
	Hit   map[int]bool // cars already affected (each car once per patch)
}

// Projectile is a moving hazard (tornado).
type Projectile struct {
	Kind   string
	Owner  int
	S, D   float64
	Speed  float64
	Until  int
	Target int
}

// UltSystem implements the eight ULTs (internal/abilities). It is an interface so that sim
// does not import abilities.
type UltSystem interface {
	// Activate fires car's ULT; returns false if it had no effect (e.g. no target in range).
	Activate(w *World, car int) bool
	// Tick updates traps and projectiles after movement.
	Tick(w *World)
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
	Traps   []*Trap
	Proj    []*Projectile
	Ults    UltSystem // nil = no ULTs (M1-style physics only)
	// LeadChanges counts changes of the leading car after the first seconds (balance metric).
	LeadChanges int
	lastLeader  int
	rank        []int
	dt          float64
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
			Ult:     v.Ult,
			Weight:  v.Stats.Weight,
			Params:  ParamsForVehicle(v, bal),
			State:   CarState{S: s, D: d, Lap: -1},
		})
	}
	w.lastLeader = -1
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
	if w.rank == nil {
		w.rank = w.Ranking()
	}
	for i, c := range w.Cars {
		in := c.Input
		if c.Finished {
			in = Input{Throttle: 1} // finished cars cruise on; they no longer race
		}
		w.startBoost(c, in)
		w.tryUlt(i, in)
		mods, flags := w.mods(i)
		c.Flags = flags
		ev := StepCar(&c.State, in, c.Params, mods, w.Track, ph, w.dt)
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
	if w.Ults != nil {
		w.Ults.Tick(w)
	}
	w.updateLaps()
	w.rank = w.Ranking()
	w.catchup()
}

// startBoost: a fresh throttle press within the window after GO gives a short boost.
func (w *World) startBoost(c *Car, in Input) {
	window := w.Bal.Ticks(w.Bal.Catchup.StartBoostWindowS)
	if w.Tick <= window+1 && in.Throttle == 1 && c.PrevThrottle == 0 {
		cu := w.Bal.Catchup
		w.Boost(c.ID, cu.StartBoostSpeed, cu.StartBoostAccel, cu.StartBoostS)
		w.Events = append(w.Events, Event{Tick: w.Tick, Kind: "startBoost", Car: c.ID})
	}
	c.PrevThrottle = in.Throttle
}

// tryUlt fires a ULT on the button's rising edge when charged and allowed.
func (w *World) tryUlt(i int, in Input) {
	c := w.Cars[i]
	pressed := in.Ability && !c.prevAbility
	c.prevAbility = in.Ability
	if !pressed || w.Ults == nil || c.Finished || c.UltLeft > 0 ||
		w.Tick < w.Bal.Ticks(w.Bal.Effects.UltLockS) || c.Status.Spinning(w.Tick) {
		return
	}
	if w.Ults.Activate(w, i) {
		c.UltLeft = w.Bal.Ult(c.Ult, "cooldownS")
		c.UltUses++
		w.Events = append(w.Events, Event{Tick: w.Tick, Kind: "abilityUsed", Car: i, Ult: c.Ult})
	}
}

// UltReady reports whether car i could fire its ULT now.
func (w *World) UltReady(i int) bool {
	c := w.Cars[i]
	return w.Ults != nil && c.UltLeft <= 0 && !c.Finished && w.Tick >= w.Bal.Ticks(w.Bal.Effects.UltLockS) && !c.Status.Spinning(w.Tick)
}

// UltCharge is 0–1 (1 = ready) for the HUD ring.
func (w *World) UltCharge(i int) float64 {
	c := w.Cars[i]
	cd := w.Bal.Ult(c.Ult, "cooldownS")
	if cd <= 0 {
		return 1
	}
	return math.Max(0, math.Min(1, 1-c.UltLeft/cd))
}

// Rank returns the race position (1-based) of car i from the last tick.
func (w *World) Rank(i int) int {
	for p, id := range w.rank {
		if id == i {
			return p + 1
		}
	}
	return len(w.Cars)
}

// catchup: position-based ULT recharge, drafting, comeback boost, lead-change metric.
func (w *World) catchup() {
	cu := w.Bal.Catchup
	n := len(w.Cars)
	L := w.Track.Length
	leader := w.Cars[w.rank[0]]
	for p, id := range w.rank {
		c := w.Cars[id]
		f := 0.0
		if n > 1 {
			f = float64(p) / float64(n-1)
		}
		if c.UltLeft > 0 {
			c.UltLeft = math.Max(0, c.UltLeft-w.dt*(cu.RechargeFirst+(cu.RechargeLast-cu.RechargeFirst)*f))
		}
		// drafting: close behind another car in the same lane for draftTimeS
		behind := false
		for _, o := range w.Cars {
			if o == c {
				continue
			}
			ds := mathx.WrapDelta(c.State.S, o.State.S, L)
			if ds > 0 && ds < cu.DraftDistM && math.Abs(o.State.D-c.State.D) < cu.DraftLateralM {
				behind = true
				break
			}
		}
		st := &c.Status
		if behind {
			st.draftTicks++
		} else {
			st.draftTicks = 0
		}
		st.drafting = st.draftTicks >= w.Bal.Ticks(cu.DraftTimeS)
		st.comeback = leader.State.Progress(L)-c.State.Progress(L) > cu.ComebackGapM
	}
	if w.Tick > w.Bal.Ticks(5) && w.EndTick == 0 && w.rank[0] != w.lastLeader {
		if w.lastLeader >= 0 {
			w.LeadChanges++
		}
	}
	if w.Tick > w.Bal.Ticks(5) {
		w.lastLeader = w.rank[0]
	}
}

// collide resolves car–car contact (GAME_PLAN §2.5 step 5) with car-sized boxes in (s, d)
// space: cars never overlap. A contact is resolved along the axis of least penetration:
// rear-end hits separate the cars and exchange speed (mass-weighted, restitution); side
// contacts push the cars apart, kick their headings away from each other and scrub a little
// speed. Two passes settle three-car pile-ups. Server only (collisions are not mirrored).
func (w *World) collide() {
	for pass := 0; pass < 2; pass++ {
		for i := 0; i < len(w.Cars); i++ {
			for j := i + 1; j < len(w.Cars); j++ {
				w.contact(i, j, pass == 0)
			}
		}
	}
}

func (w *World) contact(i, j int, emit bool) {
	ph := &w.Bal.Physics
	ci, cj := w.Cars[i], w.Cars[j]
	a, b := &ci.State, &cj.State
	if math.Abs(a.Y-b.Y) > ph.CarCollisionMaxDy || ci.Status.Ghost(w.Tick) || cj.Status.Ghost(w.Tick) {
		return
	}
	ds := mathx.WrapDelta(a.S, b.S, w.Track.Length) // + means b is ahead of a
	dd := b.D - a.D
	ox := 2*ph.CarHalfLength - math.Abs(ds) // penetration along the track
	oy := 2*ph.CarHalfWidth - math.Abs(dd)  // penetration sideways
	if ox <= 0 || oy <= 0 {
		return
	}
	ma, mb := ci.Params.Mass, cj.Params.Mass
	wa, wb := mb/(ma+mb), ma/(ma+mb) // the lighter car moves more
	impact := 0.0
	if ox/(2*ph.CarHalfLength) < oy/(2*ph.CarHalfWidth) {
		// rear-end: separate along s, 1D impact with restitution
		dir := 1.0
		if ds < 0 {
			dir = -1
		}
		a.S -= dir * ox * wa
		b.S += dir * ox * wb
		rear, front, mr, mf := a, b, ma, mb
		if ds < 0 {
			rear, front, mr, mf = b, a, mb, ma
		}
		if rel := rear.Speed - front.Speed; rel > 0 {
			e := ph.CollisionRestitution
			vr := (mr*rear.Speed + mf*front.Speed - mf*e*rel) / (mr + mf)
			vf := (mr*rear.Speed + mf*front.Speed + mr*e*rel) / (mr + mf)
			rear.Speed, front.Speed = math.Max(vr, 0), vf
			impact = rel
		}
	} else {
		// side contact: push apart sideways, bounce headings away, scrub speed
		dir := 1.0
		if dd < 0 {
			dir = -1
		}
		if dd == 0 {
			dir = float64(i - j) // deterministic tie-break
		}
		a.D -= dir * oy * wa
		b.D += dir * oy * wb
		closing := (a.Speed*math.Sin(a.YawRel) - b.Speed*math.Sin(b.YawRel)) * dir // > 0 when moving together
		if closing > 0 {
			a.YawRel -= dir * ph.SideBounceYaw * wa * 2
			b.YawRel += dir * ph.SideBounceYaw * wb * 2
			a.Speed *= 1 - ph.SideScrub
			b.Speed *= 1 - ph.SideScrub
			impact = closing
		}
	}
	if emit {
		w.Events = append(w.Events, Event{Tick: w.Tick, Kind: "bump", Car: ci.ID, Other: cj.ID, Value: impact})
	}
	w.fixup(a)
	w.fixup(b)
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
