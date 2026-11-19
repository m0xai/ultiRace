package room

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"sync"
	"time"

	"github.com/m0xai/ultiRace/internal/moderation"
)

// Room codes avoid ambiguous letters (I, O, L, 0, 1) and blocked words (GAME_PLAN §3.6).
const codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ"

// ErrTooManyRooms is returned when MaxRooms is reached.
var ErrTooManyRooms = errors.New("too many rooms")

// Manager owns the set of rooms: create, look up, delete (GAME_PLAN §3.4).
type Manager struct {
	Data     *Data
	Dir      *Directory
	Reports  *moderation.ReportLog
	MaxRooms int
	TickDur  time.Duration
	Now      func() time.Time

	ctx   context.Context
	mu    sync.Mutex
	rooms map[string]*Room
	wg    sync.WaitGroup
}

// NewManager creates a manager; rooms stop when ctx is cancelled.
func NewManager(ctx context.Context, data *Data, dir *Directory, reports *moderation.ReportLog, tickDur time.Duration) *Manager {
	if tickDur == 0 {
		tickDur = time.Second / time.Duration(data.Bal.TickRate)
	}
	return &Manager{Data: data, Dir: dir, Reports: reports, MaxRooms: 2000, TickDur: tickDur, Now: time.Now, ctx: ctx, rooms: map[string]*Room{}}
}

func randUint32() uint32 {
	var b [4]byte
	_, _ = rand.Read(b[:])
	return binary.LittleEndian.Uint32(b[:])
}

func (m *Manager) newCode() string {
	for {
		var b [4]byte
		for i := range b {
			b[i] = codeAlphabet[randUint32()%uint32(len(codeAlphabet))]
		}
		code := string(b[:])
		if _, taken := m.rooms[code]; !taken && !moderation.IsOffensive(code) {
			return code
		}
	}
}

// Create starts a new room goroutine.
func (m *Manager) Create(visibility string, practice bool) (*Room, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if len(m.rooms) >= m.MaxRooms {
		return nil, ErrTooManyRooms
	}
	code := m.newCode()
	core := NewCore(m.Data, Options{Code: code, Visibility: visibility, Practice: practice, Seed: randUint32(), Now: m.Now, TickDur: m.TickDur, Reports: m.Reports})
	r := newRoom(core, m.Dir, m.TickDur)
	m.rooms[code] = r
	m.Dir.Update(r.entry())
	m.wg.Add(1)
	go func() {
		defer m.wg.Done()
		r.run(m.ctx, m.remove)
	}()
	return r, nil
}

func (m *Manager) remove(r *Room) {
	m.mu.Lock()
	delete(m.rooms, r.Code)
	m.mu.Unlock()
	m.Dir.Remove(r.Code)
}

// Get returns a running room by code.
func (m *Manager) Get(code string) *Room {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.rooms[code]
}

// Count returns the number of rooms.
func (m *Manager) Count() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.rooms)
}

// Wait blocks until all room goroutines have stopped (after ctx is cancelled).
func (m *Manager) Wait() { m.wg.Wait() }
