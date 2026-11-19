package mathx

import (
	"math"
	"testing"
)

func TestRngKnownSequence(t *testing.T) {
	// Reference values of mulberry32(seed=1) from the canonical JS implementation (Math.imul).
	r := NewRng(1)
	want := []uint32{2693262067, 11749833, 2265367787}
	for i, w := range want {
		if got := r.Uint32(); got != w {
			t.Fatalf("value %d: got %d want %d", i, got, w)
		}
	}
}

func TestRngFloatRange(t *testing.T) {
	r := NewRng(42)
	for range 10000 {
		f := r.Float()
		if f < 0 || f >= 1 {
			t.Fatalf("out of range: %v", f)
		}
	}
}

func TestWrap(t *testing.T) {
	cases := []struct{ x, m, want float64 }{
		{5, 10, 5}, {10, 10, 0}, {-1, 10, 9}, {25, 10, 5}, {-10, 10, 0},
	}
	for _, c := range cases {
		if got := WrapPos(c.x, c.m); math.Abs(got-c.want) > 1e-12 {
			t.Errorf("WrapPos(%v,%v)=%v want %v", c.x, c.m, got, c.want)
		}
	}
	if d := WrapDelta(990, 10, 1000); math.Abs(d-20) > 1e-12 {
		t.Errorf("WrapDelta forward over seam = %v", d)
	}
	if d := WrapDelta(10, 990, 1000); math.Abs(d+20) > 1e-12 {
		t.Errorf("WrapDelta backward over seam = %v", d)
	}
}

func TestCatmullRomEndpointsAndDerivatives(t *testing.T) {
	p0, p1, p2, p3 := 0.0, 1.0, 3.0, 4.0
	if v := CatmullRom(p0, p1, p2, p3, 0); v != p1 {
		t.Fatalf("t=0: %v", v)
	}
	if v := CatmullRom(p0, p1, p2, p3, 1); v != p2 {
		t.Fatalf("t=1: %v", v)
	}
	const h = 1e-6
	for _, tt := range []float64{0.1, 0.5, 0.9} {
		num := (CatmullRom(p0, p1, p2, p3, tt+h) - CatmullRom(p0, p1, p2, p3, tt-h)) / (2 * h)
		if math.Abs(num-CatmullRomD1(p0, p1, p2, p3, tt)) > 1e-6 {
			t.Fatalf("D1 mismatch at %v", tt)
		}
		num2 := (CatmullRomD1(p0, p1, p2, p3, tt+h) - CatmullRomD1(p0, p1, p2, p3, tt-h)) / (2 * h)
		if math.Abs(num2-CatmullRomD2(p0, p1, p2, p3, tt)) > 1e-5 {
			t.Fatalf("D2 mismatch at %v", tt)
		}
	}
}
