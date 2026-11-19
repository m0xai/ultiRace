// Package bots drives cars with the same Input a human sends (GAME_PLAN §3.8): follow a
// racing line derived from curvature, dodge cars ahead, never get physics advantages.
// Difficulty only changes reaction delay and line noise. ULT heuristics arrive in M6.
package bots

import (
	"math"

	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/sim"
	"github.com/m0xai/ultiRace/internal/track"
)

const lineStep = 2.0 // m between racing-line samples

// RacingLine is a precomputed target lateral offset d(s) per track.
type RacingLine struct {
	tr *track.Track
	d  []float64
}

// NewRacingLine hugs the inside of upcoming corners: it averages curvature over a window
// ahead and maps it to a lateral target (κ > 0 means the corner's centre is on +d).
func NewRacingLine(tr *track.Track) *RacingLine {
	n := int(math.Ceil(tr.Length / lineStep))
	kappa := make([]float64, n)
	for i := range kappa {
		kappa[i] = tr.Curvature(float64(i) * lineStep)
	}
	const window = 30 // samples (60 m): start moving inside before the corner
	const gain = 35.0 // κ of 1/35 m → full inside
	rl := &RacingLine{tr: tr, d: make([]float64, n)}
	for i := 0; i < n; i++ {
		sum := 0.0
		for j := -window / 3; j < window; j++ {
			sum += kappa[(i+j+n)%n]
		}
		avg := sum / float64(window+window/3)
		hw := tr.HalfWidth(float64(i)*lineStep) - 3.0
		rl.d[i] = mathx.Clamp(avg*gain, -1, 1) * hw
	}
	return rl
}

// TargetD returns the racing-line offset at s.
func (rl *RacingLine) TargetD(s float64) float64 {
	s = mathx.WrapPos(s, rl.tr.Length)
	i := int(s / lineStep)
	f := s/lineStep - float64(i)
	n := len(rl.d)
	return rl.d[i%n]*(1-f) + rl.d[(i+1)%n]*f
}

// Difficulty tunes a bot without touching physics.
type Difficulty struct {
	ReactionTicks int     // how often the bot re-plans its target
	LineNoise     float64 // ± metres of random offset from the racing line
}

// Normal is the default bot difficulty.
var Normal = Difficulty{ReactionTicks: 6, LineNoise: 1.5}

// Controller is one bot's brain.
type Controller struct {
	line    *RacingLine
	diff    Difficulty
	rng     *mathx.Rng
	tick    int
	offset  float64 // current noise offset
	dodge   float64 // current avoidance offset
	planned float64
}

// NewController creates a bot; seed makes it deterministic.
func NewController(line *RacingLine, diff Difficulty, seed uint32) *Controller {
	return &Controller{line: line, diff: diff, rng: mathx.NewRng(seed)}
}

// Decide returns this tick's input. others are the other cars' states (any order).
func (c *Controller) Decide(self *sim.CarState, others []*sim.CarState, tr *track.Track) sim.Input {
	if c.tick%max(c.diff.ReactionTicks, 1) == 0 {
		if c.tick%(max(c.diff.ReactionTicks, 1)*10) == 0 {
			c.offset = (c.rng.Float()*2 - 1) * c.diff.LineNoise
		}
		c.dodge = c.avoid(self, others, tr)
		look := self.S + math.Max(self.Speed*0.45, 6)
		c.planned = c.line.TargetD(look) + c.offset + c.dodge
		hw := tr.HalfWidth(look) - 2
		c.planned = mathx.Clamp(c.planned, -hw, hw)
	}
	c.tick++
	return Steer(self, c.planned)
}

// avoid shifts the target when a car is close ahead in our lane.
func (c *Controller) avoid(self *sim.CarState, others []*sim.CarState, tr *track.Track) float64 {
	best := math.Inf(1)
	var blocker *sim.CarState
	for _, o := range others {
		ds := mathx.WrapDelta(self.S, o.S, tr.Length)
		if ds > 0 && ds < 18 && math.Abs(o.D-self.D) < 3 && o.Speed < self.Speed+2 && ds < best {
			best, blocker = ds, o
		}
	}
	if blocker == nil {
		return 0
	}
	// pass on the side with more room
	hw := tr.HalfWidth(self.S)
	if blocker.D > 0 {
		if blocker.D-(-hw) > 5 {
			return -3.5
		}
		return 3.5
	}
	if hw-blocker.D > 5 {
		return 3.5
	}
	return -3.5
}

// Steer is the low-level lane keeper: aim the heading back toward targetD.
func Steer(self *sim.CarState, targetD float64) sim.Input {
	want := mathx.Clamp(-(self.D-targetD)*0.06, -0.3, 0.3)
	steer := 0
	if e := want - self.YawRel; e > 0.012 {
		steer = 1
	} else if e < -0.012 {
		steer = -1
	}
	return sim.Input{Steer: steer, Throttle: 1}
}
