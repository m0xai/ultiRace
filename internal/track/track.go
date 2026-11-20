// Package track builds a closed Catmull-Rom track and answers track-space queries
// (GAME_PLAN §2.4). Mirrored by godot/src/sim/Track.gd; fixtures keep them equal.
//
// Conventions:
//   - s ∈ [0, Length) is the arc length along the 3D centreline, wrapping at Length.
//   - Tangent is the unit 3D derivative direction.
//   - Normal is the horizontal lateral unit vector (tz, 0, -tx)/|…|; d > 0 is on this side.
//   - Curvature κ is the signed horizontal curvature with dT/ds = κ·Normal, so
//     d/ds (P + d·N) = T·(1 − d·κ) (Frenet frame used by the car physics).
//   - Width and bank are linearly interpolated between control points.
package track

import (
	"fmt"
	"math"
	"sort"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/mathx"
)

// Track is an immutable, sampled closed spline.
type Track struct {
	ID     string
	Length float64
	Ramps  []gamedata.Ramp
	// Hazards are the map's fixed hazards; Blocks the solid ones among them (physics).
	Hazards []gamedata.Hazard
	Blocks  []gamedata.Hazard

	pts     [][5]float64
	k       int       // arc samples per segment
	sampleS []float64 // len n*k+1, cumulative arc length at each sample; last == Length
}

// Sample is everything known about the track at one s.
type Sample struct {
	S         float64
	Pos       mathx.Vec3
	Tangent   mathx.Vec3
	Normal    mathx.Vec3
	Curvature float64
	HalfWidth float64
	Bank      float64
}

// New builds a track from a map and the sampling resolution in balance.json.
func New(m *gamedata.Map, samplesPerSegment int) (*Track, error) {
	n := len(m.Points)
	if n < 4 {
		return nil, fmt.Errorf("track %s: need ≥ 4 control points, got %d", m.ID, n)
	}
	if samplesPerSegment < 2 {
		return nil, fmt.Errorf("track %s: samplesPerSegment must be ≥ 2", m.ID)
	}
	t := &Track{ID: m.ID, Ramps: m.Ramps, Hazards: m.Hazards, pts: m.Points, k: samplesPerSegment}
	t.sampleS = make([]float64, n*samplesPerSegment+1)
	acc := 0.0
	prev := t.posAt(0, 0)
	for seg := 0; seg < n; seg++ {
		for j := 0; j < samplesPerSegment; j++ {
			idx := seg*samplesPerSegment + j
			if idx > 0 {
				p := t.posAt(seg, float64(j)/float64(samplesPerSegment))
				acc += p.Sub(prev).Len()
				prev = p
			}
			t.sampleS[idx] = acc
		}
	}
	// closing sample: end of last segment == start of segment 0
	p := t.posAt(0, 0)
	acc += p.Sub(prev).Len()
	t.sampleS[n*samplesPerSegment] = acc
	t.Length = acc
	for _, r := range m.Ramps {
		if r.S < 0 || r.S+r.Length >= acc || r.Length <= 0 || r.Height <= 0 {
			return nil, fmt.Errorf("track %s: ramp at s=%v len=%v outside track length %.1f", m.ID, r.S, r.Length, acc)
		}
	}
	for _, h := range m.Hazards {
		switch h.Kind {
		case gamedata.HazardIce, gamedata.HazardOil, gamedata.HazardWater, gamedata.HazardBlock:
		default:
			return nil, fmt.Errorf("track %s: unknown hazard kind %q", m.ID, h.Kind)
		}
		if h.S < 0 || h.S+h.Len >= acc || h.Len <= 0 || h.HalfW <= 0 {
			return nil, fmt.Errorf("track %s: hazard %s at s=%v outside the track", m.ID, h.Kind, h.S)
		}
		if h.Kind == gamedata.HazardBlock {
			// a block must leave a lane free: ≥ 4.5 m between it and one of the walls
			hw := t.HalfWidth(h.S + h.Len/2)
			if math.Max(hw-(h.D+h.HalfW), (h.D-h.HalfW)+hw) < 4.5 {
				return nil, fmt.Errorf("track %s: block at s=%v leaves no lane free", m.ID, h.S)
			}
			t.Blocks = append(t.Blocks, h)
		}
	}
	return t, nil
}

// Load builds the track for a map id from embedded gamedata.
func Load(id string, samplesPerSegment int) (*Track, error) {
	m, err := gamedata.LoadMap(id)
	if err != nil {
		return nil, err
	}
	return New(m, samplesPerSegment)
}

func (t *Track) ctrl(i int) [5]float64 {
	n := len(t.pts)
	return t.pts[((i%n)+n)%n]
}

// posAt evaluates the centreline position of segment seg at parameter u ∈ [0,1].
func (t *Track) posAt(seg int, u float64) mathx.Vec3 {
	p0, p1, p2, p3 := t.ctrl(seg-1), t.ctrl(seg), t.ctrl(seg+1), t.ctrl(seg+2)
	return mathx.Vec3{
		X: mathx.CatmullRom(p0[0], p1[0], p2[0], p3[0], u),
		Y: mathx.CatmullRom(p0[1], p1[1], p2[1], p3[1], u),
		Z: mathx.CatmullRom(p0[2], p1[2], p2[2], p3[2], u),
	}
}

// locate maps s (any real) to a segment index and parameter u.
func (t *Track) locate(s float64) (seg int, u float64) {
	s = mathx.WrapPos(s, t.Length)
	// largest idx with sampleS[idx] <= s
	idx := sort.Search(len(t.sampleS), func(i int) bool { return t.sampleS[i] > s }) - 1
	last := len(t.sampleS) - 2
	if idx < 0 {
		idx = 0
	} else if idx > last {
		idx = last
	}
	s0, s1 := t.sampleS[idx], t.sampleS[idx+1]
	frac := 0.0
	if s1 > s0 {
		frac = (s - s0) / (s1 - s0)
	}
	seg = idx / t.k
	u = (float64(idx%t.k) + frac) / float64(t.k)
	return seg, u
}

// At returns the full track sample at s.
func (t *Track) At(s float64) Sample {
	seg, u := t.locate(s)
	p0, p1, p2, p3 := t.ctrl(seg-1), t.ctrl(seg), t.ctrl(seg+1), t.ctrl(seg+2)
	pos := mathx.Vec3{
		X: mathx.CatmullRom(p0[0], p1[0], p2[0], p3[0], u),
		Y: mathx.CatmullRom(p0[1], p1[1], p2[1], p3[1], u),
		Z: mathx.CatmullRom(p0[2], p1[2], p2[2], p3[2], u),
	}
	d1 := mathx.Vec3{
		X: mathx.CatmullRomD1(p0[0], p1[0], p2[0], p3[0], u),
		Y: mathx.CatmullRomD1(p0[1], p1[1], p2[1], p3[1], u),
		Z: mathx.CatmullRomD1(p0[2], p1[2], p2[2], p3[2], u),
	}
	ddx := mathx.CatmullRomD2(p0[0], p1[0], p2[0], p3[0], u)
	ddz := mathx.CatmullRomD2(p0[2], p1[2], p2[2], p3[2], u)
	tan := d1.Normalized()
	hl := math.Sqrt(d1.X*d1.X + d1.Z*d1.Z)
	normal := mathx.Vec3{X: d1.Z / hl, Y: 0, Z: -d1.X / hl}
	curv := (ddx*d1.Z - ddz*d1.X) / (hl * hl * hl)
	width := p1[3] + (p2[3]-p1[3])*u
	bank := p1[4] + (p2[4]-p1[4])*u
	return Sample{
		S: mathx.WrapPos(s, t.Length), Pos: pos, Tangent: tan, Normal: normal,
		Curvature: curv, HalfWidth: width / 2, Bank: bank,
	}
}

// Curvature returns κ at s (hot path for physics).
func (t *Track) Curvature(s float64) float64 { return t.At(s).Curvature }

// HalfWidth returns half the road width at s.
func (t *Track) HalfWidth(s float64) float64 {
	seg, u := t.locate(s)
	p1, p2 := t.ctrl(seg), t.ctrl(seg+1)
	return (p1[3] + (p2[3]-p1[3])*u) / 2
}

// World converts track-space (s, d, y above road) to a world position. Bank tilts the
// lateral axis around the tangent (rendering only; physics ignores bank).
func (t *Track) World(s, d, y float64) mathx.Vec3 {
	smp := t.At(s)
	up := mathx.Vec3{Y: 1}
	cb, sb := math.Cos(smp.Bank), math.Sin(smp.Bank)
	lat := smp.Normal.Scale(cb).Add(up.Scale(sb))
	return smp.Pos.Add(lat.Scale(d)).Add(up.Scale(y))
}
