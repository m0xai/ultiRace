// Package mathx has the small deterministic math helpers shared by track and sim.
// Everything here is mirrored in godot/src/sim (GDScript); keep the arithmetic identical.
package mathx

import "math"

// Vec3 is a 3D vector (y is up, like Godot).
type Vec3 struct{ X, Y, Z float64 }

func (a Vec3) Add(b Vec3) Vec3      { return Vec3{a.X + b.X, a.Y + b.Y, a.Z + b.Z} }
func (a Vec3) Sub(b Vec3) Vec3      { return Vec3{a.X - b.X, a.Y - b.Y, a.Z - b.Z} }
func (a Vec3) Scale(k float64) Vec3 { return Vec3{a.X * k, a.Y * k, a.Z * k} }
func (a Vec3) Dot(b Vec3) float64   { return a.X*b.X + a.Y*b.Y + a.Z*b.Z }
func (a Vec3) Len() float64         { return math.Sqrt(a.X*a.X + a.Y*a.Y + a.Z*a.Z) }

// Normalized returns a unit vector, or the zero vector for a zero input.
func (a Vec3) Normalized() Vec3 {
	l := a.Len()
	if l == 0 {
		return Vec3{}
	}
	return Vec3{a.X / l, a.Y / l, a.Z / l}
}

// Clamp limits v to [lo, hi].
func Clamp(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// WrapPos returns x wrapped into [0, m) using floor (same as GDScript fposmod).
func WrapPos(x, m float64) float64 {
	r := x - m*math.Floor(x/m)
	if r >= m { // guard rounding at the upper edge
		r -= m
	}
	return r
}

// WrapDelta returns b-a wrapped into [-m/2, m/2) (shortest signed distance on a loop).
func WrapDelta(a, b, m float64) float64 {
	return WrapPos(b-a+m/2, m) - m/2
}

// Rng is mulberry32: tiny, fast, identical in Go and GDScript (32-bit unsigned arithmetic).
type Rng struct{ state uint32 }

// NewRng seeds a generator.
func NewRng(seed uint32) *Rng { return &Rng{state: seed} }

// Uint32 returns the next 32-bit value.
func (r *Rng) Uint32() uint32 {
	r.state += 0x6D2B79F5
	t := r.state
	t = (t ^ (t >> 15)) * (t | 1)
	t ^= t + (t^(t>>7))*(t|61)
	return t ^ (t >> 14)
}

// Float returns a value in [0, 1).
func (r *Rng) Float() float64 { return float64(r.Uint32()) / 4294967296.0 }

// Intn returns a value in [0, n).
func (r *Rng) Intn(n int) int { return int(r.Uint32() % uint32(n)) }

// CatmullRom evaluates a uniform Catmull-Rom segment between p1 and p2 at t ∈ [0,1].
func CatmullRom(p0, p1, p2, p3, t float64) float64 {
	t2 := t * t
	t3 := t2 * t
	return 0.5 * ((2 * p1) + (-p0+p2)*t + (2*p0-5*p1+4*p2-p3)*t2 + (-p0+3*p1-3*p2+p3)*t3)
}

// CatmullRomD1 is the first derivative d/dt.
func CatmullRomD1(p0, p1, p2, p3, t float64) float64 {
	return 0.5 * ((-p0 + p2) + 2*(2*p0-5*p1+4*p2-p3)*t + 3*(-p0+3*p1-3*p2+p3)*t*t)
}

// CatmullRomD2 is the second derivative d²/dt².
func CatmullRomD2(p0, p1, p2, p3, t float64) float64 {
	return 0.5 * (2*(2*p0-5*p1+4*p2-p3) + 6*(-p0+3*p1-3*p2+p3)*t)
}
