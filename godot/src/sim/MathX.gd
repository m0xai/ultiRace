class_name MathX
extends RefCounted

## Mirror of internal/mathx (Go). Plain 64-bit floats only: Vector3 is 32-bit in standard
## Godot builds and would break the 1e-4 conformance with the Go server.

const MASK32: int = 0xFFFFFFFF


static func clampf64(v: float, lo: float, hi: float) -> float:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v


## x wrapped into [0, m) using floor (Go: mathx.WrapPos).
static func wrap_pos(x: float, m: float) -> float:
	var r: float = x - m * floorf(x / m)
	if r >= m:
		r -= m
	return r


## b - a wrapped into [-m/2, m/2) (Go: mathx.WrapDelta).
static func wrap_delta(a: float, b: float, m: float) -> float:
	return wrap_pos(b - a + m / 2.0, m) - m / 2.0


static func catmull_rom(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func catmull_rom_d1(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	return 0.5 * ((-p0 + p2) + 2.0 * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t + 3.0 * (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t)


static func catmull_rom_d2(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	return 0.5 * (2.0 * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) + 6.0 * (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t)


## 32-bit multiply (Math.imul semantics) without relying on 64-bit overflow behaviour.
static func imul32(a: int, b: int) -> int:
	a &= MASK32
	b &= MASK32
	var a_hi: int = (a >> 16) & 0xFFFF
	var a_lo: int = a & 0xFFFF
	var b_hi: int = (b >> 16) & 0xFFFF
	var b_lo: int = b & 0xFFFF
	var cross: int = ((a_hi * b_lo + a_lo * b_hi) & 0xFFFF) << 16
	return (a_lo * b_lo + cross) & MASK32
