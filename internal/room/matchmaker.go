package room

import (
	"sort"
	"sync"
	"time"

	"github.com/m0xai/ultiRace/internal/protocol"
)

// Matchmaker implements Quick Play (GAME_PLAN §2.3.1, §3.4): pick the public LOBBY room with
// a free seat, more humans and less time left, avoiding blocked players; reserve the seat for
// a few seconds; otherwise create a new public room with bots.
type Matchmaker struct {
	mgr *Manager
	now func() time.Time

	mu       sync.Mutex
	reserved map[string][]time.Time // room code → reservation expiries
}

// NewMatchmaker creates a matchmaker.
func NewMatchmaker(mgr *Manager) *Matchmaker {
	return &Matchmaker{mgr: mgr, now: mgr.Now, reserved: map[string][]time.Time{}}
}

func (mm *Matchmaker) activeReservations(code string, now time.Time) int {
	kept := mm.reserved[code][:0]
	for _, t := range mm.reserved[code] {
		if t.After(now) {
			kept = append(kept, t)
		}
	}
	if len(kept) == 0 {
		delete(mm.reserved, code)
	} else {
		mm.reserved[code] = kept
	}
	return len(kept)
}

// Pick returns a room code and reserves a seat in it, creating a room when none fits.
// exclude lists room codes that already refused this player (e.g. full after a race).
func (mm *Matchmaker) Pick(blocked []string, exclude map[string]bool) (string, error) {
	bl := map[string]bool{}
	for _, b := range blocked {
		bl[b] = true
	}
	now := mm.now()
	nowMs := now.UnixMilli()
	mm.mu.Lock()
	defer mm.mu.Unlock()

	type cand struct {
		e    Entry
		left int64
	}
	var cands []cand
	for _, e := range mm.mgr.Dir.Snapshot() {
		s := e.Summary
		if s.Visibility != protocol.Public || s.State != string(Lobby) || exclude[s.Code] {
			continue
		}
		if e.FreeSeats-mm.activeReservations(s.Code, now) <= 0 {
			continue
		}
		hasBlocked := false
		for _, id := range e.PlayerIDs {
			if bl[id] {
				hasBlocked = true
				break
			}
		}
		if hasBlocked {
			continue
		}
		left := int64(1 << 62)
		if s.Deadline > 0 {
			left = s.Deadline - nowMs
		}
		cands = append(cands, cand{e, left})
	}
	sort.Slice(cands, func(i, j int) bool {
		a, b := cands[i], cands[j]
		if a.e.Summary.Humans != b.e.Summary.Humans {
			return a.e.Summary.Humans > b.e.Summary.Humans
		}
		if a.left != b.left {
			return a.left < b.left
		}
		return a.e.Summary.Code < b.e.Summary.Code
	})
	if len(cands) > 0 {
		code := cands[0].e.Summary.Code
		mm.reserve(code, now)
		return code, nil
	}
	r, err := mm.mgr.Create(protocol.Public, false)
	if err != nil {
		return "", err
	}
	mm.reserve(r.Code, now)
	return r.Code, nil
}

func (mm *Matchmaker) reserve(code string, now time.Time) {
	d := time.Duration(mm.mgr.Data.Bal.Rooms.SeatReservationS * float64(time.Second))
	mm.reserved[code] = append(mm.reserved[code], now.Add(d))
}

// Release drops one reservation for a room (the player joined or gave up).
func (mm *Matchmaker) Release(code string) {
	mm.mu.Lock()
	defer mm.mu.Unlock()
	if rs := mm.reserved[code]; len(rs) > 0 {
		mm.reserved[code] = rs[1:]
	}
}
