package room

import (
	"context"
	"time"
)

// Room runs one Core on its own goroutine (GAME_PLAN §3.4): every access to game state
// happens inside that goroutine, so there are no mutexes on game state.
type Room struct {
	Code string
	core *Core
	in   chan func(*Core)
	done chan struct{}
	dir  *Directory
	tick time.Duration
}

func newRoom(core *Core, dir *Directory, tick time.Duration) *Room {
	return &Room{Code: core.Code, core: core, in: make(chan func(*Core), 256), done: make(chan struct{}), dir: dir, tick: tick}
}

// Do runs f on the room goroutine and waits for it. Returns false if the room is closed.
func (r *Room) Do(f func(*Core)) bool {
	ack := make(chan struct{})
	select {
	case r.in <- func(c *Core) { f(c); close(ack) }:
	case <-r.done:
		return false
	}
	select {
	case <-ack:
		return true
	case <-r.done:
		return false
	}
}

// Post queues f without waiting (used for client messages on the hot path).
func (r *Room) Post(f func(*Core)) bool {
	select {
	case r.in <- f:
		return true
	case <-r.done:
		return false
	}
}

// Done is closed when the room has stopped.
func (r *Room) Done() <-chan struct{} { return r.done }

// run is the room loop: drain inbound work, step at the tick rate, publish the summary.
func (r *Room) run(ctx context.Context, onClose func(*Room)) {
	defer func() {
		close(r.done)
		onClose(r)
	}()
	t := time.NewTicker(r.tick)
	defer t.Stop()
	lastVer := -1
	for {
		select {
		case <-ctx.Done():
			return
		case f := <-r.in:
			f(r.core)
		case <-t.C:
			r.core.Step()
			if v := r.core.SummaryVersion(); v != lastVer {
				lastVer = v
				r.dir.Update(r.entry())
			}
			if r.core.ShouldClose() {
				return
			}
		}
	}
}

func (r *Room) entry() Entry {
	return Entry{Summary: r.core.Summary(), PlayerIDs: r.core.PlayerIDs(), FreeSeats: r.core.FreeSeats(), RacingHumans: r.core.RacingHumans(), ConnectedHumans: r.core.connectedHumans()}
}
