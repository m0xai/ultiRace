package room

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"sort"
	"sync"
	"time"

	"github.com/m0xai/ultiRace/internal/protocol"
)

// Entry is what a room publishes to the directory on every change.
type Entry struct {
	Summary         protocol.RoomSummary
	PlayerIDs       []string // humans, for Quick Play block checks (never exposed)
	FreeSeats       int
	RacingHumans    int
	ConnectedHumans int
}

// Directory is the public room listing (GAME_PLAN §3.4): rooms push summaries, readers get
// a cached JSON body rebuilt at most twice per second, served with an ETag.
type Directory struct {
	mu      sync.RWMutex
	entries map[string]Entry
	dirty   bool

	cacheMu   sync.Mutex
	cacheAt   time.Time
	cacheKey  string
	cacheBody []byte
	cacheETag string
	now       func() time.Time

	// MaxListed caps the listing (0 = unlimited); set from balance.json rooms.maxListedRooms.
	MaxListed int
}

// NewDirectory creates an empty directory.
func NewDirectory(now func() time.Time) *Directory {
	if now == nil {
		now = time.Now
	}
	return &Directory{entries: map[string]Entry{}, now: now}
}

// Update stores a room's latest entry.
func (d *Directory) Update(e Entry) {
	d.mu.Lock()
	d.entries[e.Summary.Code] = e
	d.dirty = true
	d.mu.Unlock()
}

// Remove deletes a room (public rooms disappear from the listing immediately).
func (d *Directory) Remove(code string) {
	d.mu.Lock()
	delete(d.entries, code)
	d.dirty = true
	d.mu.Unlock()
}

// Snapshot returns a copy of all entries.
func (d *Directory) Snapshot() []Entry {
	d.mu.RLock()
	defer d.mu.RUnlock()
	out := make([]Entry, 0, len(d.entries))
	for _, e := range d.entries {
		out = append(out, e)
	}
	return out
}

// Stats counts connected humans across all rooms.
func (d *Directory) Stats() protocol.Stats {
	var s protocol.Stats
	for _, e := range d.Snapshot() {
		s.Online += e.ConnectedHumans
		s.Racing += e.RacingHumans
	}
	return s
}

// stateOrder: rooms in LOBBY first.
func stateOrder(s string) int {
	if s == string(Lobby) {
		return 0
	}
	return 1
}

// List returns the public, not-full rooms matching the filters, sorted by: LOBBY first,
// then most humans, then newest (GAME_PLAN §2.3.1).
func (d *Directory) List(mapID string, laps int) protocol.RoomList {
	var rooms []protocol.RoomSummary
	online := 0
	for _, e := range d.Snapshot() {
		online += e.ConnectedHumans
		s := e.Summary
		if s.Visibility != protocol.Public || s.Humans >= s.MaxCars {
			continue
		}
		if (mapID != "" && s.Map != mapID) || (laps != 0 && s.Laps != laps) {
			continue
		}
		rooms = append(rooms, s)
	}
	sort.Slice(rooms, func(i, j int) bool {
		a, b := rooms[i], rooms[j]
		if stateOrder(a.State) != stateOrder(b.State) {
			return stateOrder(a.State) < stateOrder(b.State)
		}
		if a.Humans != b.Humans {
			return a.Humans > b.Humans
		}
		if a.CreatedAt != b.CreatedAt {
			return a.CreatedAt > b.CreatedAt
		}
		return a.Code < b.Code
	})
	if d.MaxListed > 0 && len(rooms) > d.MaxListed {
		rooms = rooms[:d.MaxListed]
	}
	if rooms == nil {
		rooms = []protocol.RoomSummary{}
	}
	return protocol.RoomList{Online: online, Rooms: rooms}
}

// ListJSON returns the cached body and ETag for a filter, rebuilt at most every 500 ms.
func (d *Directory) ListJSON(mapID string, laps int) (body []byte, etag string) {
	key := mapID + "|" + string(rune('0'+laps))
	d.cacheMu.Lock()
	defer d.cacheMu.Unlock()
	if key == d.cacheKey && d.now().Sub(d.cacheAt) < 500*time.Millisecond {
		return d.cacheBody, d.cacheETag
	}
	b, _ := json.Marshal(d.List(mapID, laps))
	sum := sha256.Sum256(b)
	d.cacheKey, d.cacheAt, d.cacheBody = key, d.now(), b
	d.cacheETag = `"` + hex.EncodeToString(sum[:8]) + `"`
	return d.cacheBody, d.cacheETag
}
