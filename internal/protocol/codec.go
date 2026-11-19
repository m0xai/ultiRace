package protocol

import (
	"encoding/binary"
	"errors"
	"math"
)

// Binary snapshot (GAME_PLAN §3.5), little endian. Encoded once per room per tick; the
// per-client ack lives in a fixed prefix that is patched per recipient.
//
//	offset size  field
//	0      1     kind (SnapKind = 1)
//	1      4     ack: last input seq applied for the recipient (u32)
//	5      4     tick (u32)
//	9      1     car count N
//	10     N*18  cars
//	...    1     projectile count (0 until M6)
//	...    1     trap count (0 until M6)
//
// car (18 bytes):
//
//	id u8 | s u32 (cm) | d i16 (cm) | yawRel i16 (1e-4 rad) | y u16 (cm) | speed u16 (cm/s)
//	| vy i16 (cm/s) | lap i8 | flags u16 (bit0 finished, bits 1–11 effects from M6,
//	  bits 12–15 race position 1–8, 0 = unknown; ranking is computed only by the server)
const (
	SnapKind     byte = 1
	snapHeader        = 10
	snapCarBytes      = 18
	AckOffset         = 1
)

// Quantisation steps (also used by Snapshot.gd).
const (
	QS     = 0.01   // m per unit for s, d, y
	QYaw   = 0.0001 // rad per unit
	QSpeed = 0.01   // m/s per unit for speed, vy
)

// Car flags.
const (
	FlagFinished uint16 = 1 << 0
	PosShift            = 12
	PosMask      uint16 = 0xF << PosShift
)

// WithPos stores a 1-based race position (1–15) in the flags.
func WithPos(flags uint16, pos int) uint16 {
	return flags&^PosMask | uint16(pos&0xF)<<PosShift
}

// Pos extracts the race position from flags (0 = unknown).
func Pos(flags uint16) int { return int(flags&PosMask) >> PosShift }

// SnapCar is one car's quantised state.
type SnapCar struct {
	ID     uint8
	S      float64
	D      float64
	YawRel float64
	Y      float64
	Speed  float64
	Vy     float64
	Lap    int8
	Flags  uint16
}

// Snapshot is the decoded binary snapshot.
type Snapshot struct {
	Ack   uint32
	Tick  uint32
	Cars  []SnapCar
	Proj  int
	Traps int
}

func q(x, step float64) float64 { return math.Round(x / step) }

func clampI16(x float64) int16 {
	return int16(math.Max(math.MinInt16, math.Min(math.MaxInt16, x)))
}

func clampU16(x float64) uint16 { return uint16(math.Max(0, math.Min(math.MaxUint16, x))) }

// EncodeSnapshot writes the snapshot with ack=0; use PatchAck per recipient.
func EncodeSnapshot(tick uint32, cars []SnapCar) []byte {
	b := make([]byte, snapHeader+len(cars)*snapCarBytes+2)
	b[0] = SnapKind
	binary.LittleEndian.PutUint32(b[5:], tick)
	b[9] = byte(len(cars))
	o := snapHeader
	for _, c := range cars {
		b[o] = c.ID
		binary.LittleEndian.PutUint32(b[o+1:], uint32(math.Max(0, q(c.S, QS))))
		binary.LittleEndian.PutUint16(b[o+5:], uint16(clampI16(q(c.D, QS))))
		binary.LittleEndian.PutUint16(b[o+7:], uint16(clampI16(q(c.YawRel, QYaw))))
		binary.LittleEndian.PutUint16(b[o+9:], clampU16(q(c.Y, QS)))
		binary.LittleEndian.PutUint16(b[o+11:], clampU16(q(c.Speed, QSpeed)))
		binary.LittleEndian.PutUint16(b[o+13:], uint16(clampI16(q(c.Vy, QSpeed))))
		b[o+15] = byte(c.Lap)
		binary.LittleEndian.PutUint16(b[o+16:], c.Flags)
		o += snapCarBytes
	}
	b[o] = 0   // projectiles (M6)
	b[o+1] = 0 // traps (M6)
	return b
}

// PatchAck returns a copy of the snapshot with the recipient's ack.
func PatchAck(snap []byte, ack uint32) []byte {
	out := make([]byte, len(snap))
	copy(out, snap)
	binary.LittleEndian.PutUint32(out[AckOffset:], ack)
	return out
}

var ErrShortSnapshot = errors.New("snapshot too short")

// DecodeSnapshot parses a binary snapshot.
func DecodeSnapshot(b []byte) (*Snapshot, error) {
	if len(b) < snapHeader+2 || b[0] != SnapKind {
		return nil, ErrShortSnapshot
	}
	n := int(b[9])
	if len(b) < snapHeader+n*snapCarBytes+2 {
		return nil, ErrShortSnapshot
	}
	s := &Snapshot{
		Ack:  binary.LittleEndian.Uint32(b[1:]),
		Tick: binary.LittleEndian.Uint32(b[5:]),
		Cars: make([]SnapCar, n),
	}
	o := snapHeader
	for i := 0; i < n; i++ {
		s.Cars[i] = SnapCar{
			ID:     b[o],
			S:      float64(binary.LittleEndian.Uint32(b[o+1:])) * QS,
			D:      float64(int16(binary.LittleEndian.Uint16(b[o+5:]))) * QS,
			YawRel: float64(int16(binary.LittleEndian.Uint16(b[o+7:]))) * QYaw,
			Y:      float64(binary.LittleEndian.Uint16(b[o+9:])) * QS,
			Speed:  float64(binary.LittleEndian.Uint16(b[o+11:])) * QSpeed,
			Vy:     float64(int16(binary.LittleEndian.Uint16(b[o+13:]))) * QSpeed,
			Lap:    int8(b[o+15]),
			Flags:  binary.LittleEndian.Uint16(b[o+16:]),
		}
		o += snapCarBytes
	}
	s.Proj = int(b[o])
	s.Traps = int(b[o+1])
	return s, nil
}
