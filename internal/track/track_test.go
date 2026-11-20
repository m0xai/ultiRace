package track

import (
	"math"
	"testing"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/mathx"
)

func loadAll(t *testing.T) (map[string]*Track, *gamedata.Balance) {
	t.Helper()
	b, err := gamedata.LoadBalance()
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]*Track{}
	for _, id := range gamedata.MapIDs() {
		tr, err := Load(id, b.Track.ArcSamplesPerSegment)
		if err != nil {
			t.Fatal(err)
		}
		out[id] = tr
	}
	if len(out) != 3 {
		t.Fatalf("want 3 maps, got %d", len(out))
	}
	return out, b
}

// Plan §2.10 / §2.5: closed loops 1100–1500 m, width 18–22 m.
func TestMapsWithinPlanBounds(t *testing.T) {
	tracks, _ := loadAll(t)
	for id, tr := range tracks {
		if tr.Length < 1100 || tr.Length > 1500 {
			t.Errorf("%s: length %.1f m outside 1100–1500", id, tr.Length)
		}
		minR, maxGrade := math.Inf(1), 0.0
		for i := 0; i < 2000; i++ {
			s := tr.Length * float64(i) / 2000
			smp := tr.At(s)
			if w := smp.HalfWidth * 2; w < 18-1e-9 || w > 22+1e-9 {
				t.Errorf("%s: width %.2f at s=%.1f", id, w, s)
			}
			if k := math.Abs(smp.Curvature); k > 0 {
				minR = math.Min(minR, 1/k)
			}
			maxGrade = math.Max(maxGrade, math.Abs(smp.Tangent.Y))
			if math.IsNaN(smp.Pos.X) || math.IsNaN(smp.Curvature) {
				t.Fatalf("%s: NaN at s=%.1f", id, s)
			}
		}
		if minR < 20 {
			t.Errorf("%s: min corner radius %.1f m < 20 m (too tight for cars ~1.4 m radius)", id, minR)
		}
		t.Logf("%s: length %.1f m, min radius %.1f m, max grade %.1f%%", id, tr.Length, minR, maxGrade*100)
		for i := range tr.pts {
			t.Logf("  ctrl %2d at s=%7.1f", i, tr.sampleS[i*tr.k])
		}
	}
}

// Frenet identity: moving along s at lateral offset d advances the world point by (1 − dκ).
func TestCurvatureMatchesGeometry(t *testing.T) {
	tracks, _ := loadAll(t)
	for id, tr := range tracks {
		for _, s := range []float64{37, 211, 503, 777, 1001} {
			const h, d = 0.05, 4.0
			smp := tr.At(s)
			if smp.Bank != 0 { // banked lateral axis isn't horizontal; check flat spots only
				continue
			}
			a, b := tr.World(s-h, d, 0), tr.World(s+h, d, 0)
			a0, b0 := tr.World(s-h, 0, 0), tr.World(s+h, 0, 0)
			got := math.Hypot(b.X-a.X, b.Z-a.Z) / math.Hypot(b0.X-a0.X, b0.Z-a0.Z)
			want := 1 - d*smp.Curvature
			if math.Abs(got-want) > 2e-3 {
				t.Errorf("%s s=%v: lateral path ratio %.5f, want 1−dκ = %.5f", id, s, got, want)
			}
		}
	}
}

func TestFrameIsOrthonormal(t *testing.T) {
	tracks, _ := loadAll(t)
	for id, tr := range tracks {
		for i := 0; i < 500; i++ {
			smp := tr.At(tr.Length * float64(i) / 500)
			if math.Abs(smp.Tangent.Len()-1) > 1e-9 || math.Abs(smp.Normal.Len()-1) > 1e-9 {
				t.Fatalf("%s: non-unit frame", id)
			}
			h := mathx.Vec3{X: smp.Tangent.X, Z: smp.Tangent.Z}
			if math.Abs(h.Dot(smp.Normal)) > 1e-9 {
				t.Fatalf("%s: normal not perpendicular to tangent", id)
			}
		}
	}
}

func TestWrapAndContinuity(t *testing.T) {
	tracks, _ := loadAll(t)
	for id, tr := range tracks {
		a := tr.At(-1)
		b := tr.At(tr.Length - 1)
		if a.Pos.Sub(b.Pos).Len() > 1e-9 {
			t.Errorf("%s: s=-1 and s=L-1 differ", id)
		}
		// seam continuity: positions just before and after s=0 are close
		p0 := tr.At(tr.Length - 0.01).Pos
		p1 := tr.At(0.01).Pos
		if d := p0.Sub(p1).Len(); d > 0.05 {
			t.Errorf("%s: seam gap %.4f m", id, d)
		}
		// arc length table is consistent: walking 1 m moves ~1 m
		for _, s := range []float64{10, 400, tr.Length - 5} {
			d := tr.At(s + 1).Pos.Sub(tr.At(s).Pos).Len()
			if math.Abs(d-1) > 0.01 {
				t.Errorf("%s: 1 m step at s=%.0f moved %.4f m", id, s, d)
			}
		}
	}
}

// Neon is a figure-8: the two passes over the crossing must be ≥ 8 m apart vertically.
func TestNeonBridgeClearance(t *testing.T) {
	tracks, _ := loadAll(t)
	tr := tracks["neon"]
	const n = 4000
	minClear := math.Inf(1)
	for i := 0; i < n; i++ {
		a := tr.At(tr.Length * float64(i) / n)
		for j := i + n/8; j < i+n-n/8; j += 1 {
			b := tr.At(tr.Length * float64(j%n) / n)
			if math.Hypot(a.Pos.X-b.Pos.X, a.Pos.Z-b.Pos.Z) < 12 {
				minClear = math.Min(minClear, math.Abs(a.Pos.Y-b.Pos.Y))
			}
		}
		i += 3
	}
	if minClear < 8 {
		t.Errorf("neon: bridge clearance %.2f m < 8 m", minClear)
	}
	t.Logf("neon bridge clearance %.2f m", minClear)
}

// A road block must leave a lane free.
func TestBlockMustLeaveALane(t *testing.T) {
	b, _ := gamedata.LoadBalance()
	m, _ := gamedata.LoadMap("sunny")
	m.Hazards = []gamedata.Hazard{{Kind: gamedata.HazardBlock, S: 300, D: 0, Len: 3, HalfW: 7}}
	if _, err := New(m, b.Track.ArcSamplesPerSegment); err == nil {
		t.Fatal("accepted a block across the whole road")
	}
	m.Hazards = []gamedata.Hazard{{Kind: "lava", S: 300, Len: 3, HalfW: 2}}
	if _, err := New(m, b.Track.ArcSamplesPerSegment); err == nil {
		t.Fatal("accepted an unknown hazard kind")
	}
}
