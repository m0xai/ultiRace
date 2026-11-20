package sim

import "math"

// Effect bits (snapshot flags bits 1–7, GAME_PLAN §2.7). Clients only display them; the
// predicted own car (M7) applies them through Mods.
const (
	EffSpinout uint16 = 1 << 1
	EffSlow    uint16 = 1 << 2
	EffSlide   uint16 = 1 << 3
	EffBoost   uint16 = 1 << 4
	EffGhost   uint16 = 1 << 5
	EffImmune  uint16 = 1 << 6
	EffDraft   uint16 = 1 << 7
)

type timedMod struct {
	speed, accel, steer float64
	until               int
}

// Status holds a car's active effects (server only).
type Status struct {
	spinoutUntil int
	immuneUntil  int
	lastHardCC   int
	ghostUntil   int
	slows        []timedMod // speed = fraction removed
	slides       []timedMod // steer multiplier, speed = fraction removed
	boosts       []timedMod // speed/accel = fractions added
	draftTicks   int
	drafting     bool
	comeback     bool
	botBoost     float64 // bot catch-up speed bonus (fraction), see World.catchup
	onHazard     uint64  // bit i: car is on surface hazard i (slides trigger once per pass)

	HardCCTicks    int // ticks spent hard-CC'd (balance metrics)
	HardCCReceived int
}

func prune(ms []timedMod, tick int) []timedMod {
	out := ms[:0]
	for _, m := range ms {
		if m.until > tick {
			out = append(out, m)
		}
	}
	return out
}

// Spinning reports an active hard CC.
func (s *Status) Spinning(tick int) bool { return tick < s.spinoutUntil }

// Ghost reports an active Phase.
func (s *Status) Ghost(tick int) bool { return tick < s.ghostUntil }

// CanHardCC applies the anti-frustration rules: ghosts and recently-CC'd cars are immune,
// and a car is hard-CC'd at most once per hardCcMinGapS from any source.
func (w *World) CanHardCC(car int) bool {
	st := &w.Cars[car].Status
	gap := w.Bal.Ticks(w.Bal.Effects.HardCCMinGapS)
	return !st.Ghost(w.Tick) && w.Tick >= st.immuneUntil && (st.lastHardCC == 0 || w.Tick-st.lastHardCC >= gap)
}

// Spinout hard-CCs a car (if allowed) for seconds, scaled by weight (−5 % per point above 3).
// Returns true if it took effect.
func (w *World) Spinout(car int, seconds float64) bool {
	if !w.CanHardCC(car) {
		return false
	}
	c := w.Cars[car]
	if w2 := c.Weight - 3; w2 > 0 {
		seconds *= 1 - w.Bal.Stats.HardCCReductionPerWeightAbove3*float64(w2)
	}
	ticks := w.Bal.Ticks(seconds)
	st := &c.Status
	st.spinoutUntil = w.Tick + ticks
	st.immuneUntil = st.spinoutUntil + w.Bal.Ticks(w.Bal.Effects.CCImmunityS)
	st.lastHardCC = w.Tick
	st.HardCCReceived++
	c.State.Speed *= w.Bal.Effects.SpinoutSpeedFactor
	return true
}

// Slow adds a soft slow (slows don't stack: the strongest applies).
func (w *World) Slow(car int, fraction, seconds float64) {
	st := &w.Cars[car].Status
	if st.Ghost(w.Tick) {
		return
	}
	st.slows = append(st.slows, timedMod{speed: fraction, until: w.Tick + w.Bal.Ticks(seconds)})
}

// Slide adds a soft slide (reduced steering, small speed loss).
func (w *World) Slide(car int, steerMul, slow, seconds float64) {
	st := &w.Cars[car].Status
	if st.Ghost(w.Tick) {
		return
	}
	st.slides = append(st.slides, timedMod{steer: steerMul, speed: slow, until: w.Tick + w.Bal.Ticks(seconds)})
}

// Boost adds a buff (boosts stack additively, capped).
func (w *World) Boost(car int, speed, accel, seconds float64) {
	st := &w.Cars[car].Status
	st.boosts = append(st.boosts, timedMod{speed: speed, accel: accel, until: w.Tick + w.Bal.Ticks(seconds)})
}

// Ghostify starts Phase: CC immune, no car collisions, passes traps, clears effects.
func (w *World) Ghostify(car int, seconds float64) {
	st := &w.Cars[car].Status
	st.ghostUntil = w.Tick + w.Bal.Ticks(seconds)
	st.spinoutUntil = 0
	st.slows, st.slides = st.slows[:0], st.slides[:0]
}

// mods turns the active effects into this tick's physics multipliers.
func (w *World) mods(i int) (Mods, uint16) {
	c := w.Cars[i]
	st := &c.Status
	t := w.Tick
	st.slows = prune(st.slows, t)
	st.slides = prune(st.slides, t)
	st.boosts = prune(st.boosts, t)
	e := w.Bal.Effects
	m := NeutralMods
	var flags uint16

	slow := 0.0
	for _, s := range st.slows {
		slow = math.Max(slow, s.speed)
	}
	if slow > 0 {
		flags |= EffSlow
	}
	for _, s := range st.slides {
		m.SteerMul = math.Min(m.SteerMul, s.steer)
		slow = math.Max(slow, s.speed)
		flags |= EffSlide
	}
	slow = math.Min(slow, e.SlowCap)

	boost, accel := 0.0, 0.0
	for _, b := range st.boosts {
		boost += b.speed
		accel += b.accel
	}
	if boost > 0 || accel > 0 {
		flags |= EffBoost
	}
	if st.drafting {
		boost += w.Bal.Catchup.DraftBonus
		flags |= EffDraft
	}
	if st.comeback {
		boost += w.Bal.Catchup.ComebackBonus
	}
	boost += st.botBoost
	boost = math.Min(boost, e.BoostCap)
	accel = math.Min(accel, e.BoostCap*2)

	m.SpeedMul = (1 - slow) * (1 + boost)
	m.AccelMul = 1 + accel
	if st.Spinning(t) {
		m.NoInput = true
		flags |= EffSpinout
		st.HardCCTicks++
	} else if t < st.immuneUntil {
		flags |= EffImmune
	}
	if st.Ghost(t) {
		flags |= EffGhost
	}
	return m, flags
}
