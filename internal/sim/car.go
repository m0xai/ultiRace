// Package sim is the authoritative race simulation (GAME_PLAN §2.5, §3.3).
// physics.go (single-car step) is mirrored by godot/src/sim/Physics.gd; everything else
// (collisions, laps, ranking, effects) exists only on the server.
package sim

import "github.com/m0xai/ultiRace/gamedata"

// Input is one tick of player or bot input (protocol `in`).
type Input struct {
	Steer    int  // -1, 0, 1 (positive steers toward +d)
	Throttle int  // 0 or 1
	Ability  bool // ULT button (M6)
}

// CarParams are a vehicle's physical values derived from its stats and balance.json.
type CarParams struct {
	TopSpeed    float64 // m/s
	Accel       float64 // m/s², reaches TopSpeed in accelTime
	SteerRate   float64 // rad/s at standstill
	WallReflect float64 // fraction of yawRel kept (mirrored) after a wall hit
	Mass        float64
}

// ParamsFor maps 1–5 stats linearly to physical values (GAME_PLAN §2.6).
func ParamsFor(st gamedata.Stats, m gamedata.StatsMapping) CarParams {
	top := m.TopSpeedBase + m.TopSpeedPerStat*float64(st.Speed)
	accelTime := m.AccelTimeBase - m.AccelTimePerStat*float64(st.Accel)
	return CarParams{
		TopSpeed:    top,
		Accel:       top / accelTime,
		SteerRate:   m.SteerRateBase + m.SteerRatePerStat*float64(st.Handling),
		WallReflect: m.WallReflectBase - m.WallReflectPerStat*float64(st.Handling),
		Mass:        m.MassBase + m.MassPerStat*float64(st.Weight),
	}
}

// Mods are per-tick multipliers from status effects (M6). Neutral is {1,1,1,false}.
type Mods struct {
	SpeedMul float64
	AccelMul float64
	SteerMul float64
	NoInput  bool // hard CC: input ignored
}

// NeutralMods has no effect.
var NeutralMods = Mods{SpeedMul: 1, AccelMul: 1, SteerMul: 1}

// CarState is the mirrored physics state of one car in track space.
type CarState struct {
	S      float64 // arc length, [0, L)
	D      float64 // lateral offset, + along track Normal
	YawRel float64 // heading relative to tangent (rad), + turns toward +d
	Y      float64 // height above road
	Vy     float64 // vertical speed
	Speed  float64 // forward speed along heading (m/s), ≥ 0
	Lap    int     // -1 before first crossing of the start line
}

// StepEvents reports what happened during one physics step.
type StepEvents struct {
	WallHit      bool
	WallImpact   float64 // speed into the wall (m/s), for haptics/sparks
	Launched     bool
	Landed       bool
	CrossedStart int // +1 forward over the line, -1 backward
}

// Progress is the race-distance used for ranking: lap·L + s.
func (c *CarState) Progress(trackLen float64) float64 {
	return float64(c.Lap)*trackLen + c.S
}

// Airborne reports whether the car is in the air.
func (c *CarState) Airborne() bool { return c.Y > 0 || c.Vy > 0 }
