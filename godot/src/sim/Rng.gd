class_name Rng
extends RefCounted

## mulberry32, identical to internal/mathx.Rng (Go) and the canonical JS implementation.

var _state: int = 0


func _init(seed: int) -> void:
	_state = seed & MathX.MASK32


func next_u32() -> int:
	_state = (_state + 0x6D2B79F5) & MathX.MASK32
	var t: int = _state
	t = MathX.imul32(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + MathX.imul32(t ^ (t >> 7), t | 61)) & MathX.MASK32)) & MathX.MASK32
	return (t ^ (t >> 14)) & MathX.MASK32


## Value in [0, 1).
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


func next_int(n: int) -> int:
	return next_u32() % n
