package room

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/m0xai/ultiRace/internal/protocol"
)

func entry(code, vis, state string, humans int, created int64, players ...string) Entry {
	return Entry{
		Summary:   protocol.RoomSummary{Code: code, Visibility: vis, State: state, Humans: humans, MaxCars: 8, CreatedAt: created, Map: "sunny", Laps: 3},
		PlayerIDs: players, FreeSeats: 8 - humans, ConnectedHumans: humans,
	}
}

func TestDirectoryListingRules(t *testing.T) {
	d := NewDirectory(nil)
	d.Update(entry("PRIV", protocol.Private, "LOBBY", 3, 1))
	d.Update(entry("FULL", protocol.Public, "LOBBY", 8, 1))
	d.Update(entry("RACE", protocol.Public, "RACING", 6, 1))
	d.Update(entry("OLD1", protocol.Public, "LOBBY", 2, 1))
	d.Update(entry("NEW1", protocol.Public, "LOBBY", 2, 5))
	d.Update(entry("MOST", protocol.Public, "LOBBY", 4, 1))
	l := d.List("", 0)
	var got []string
	for _, r := range l.Rooms {
		got = append(got, r.Code)
	}
	want := "[MOST NEW1 OLD1 RACE]"
	if fmt.Sprint(got) != want {
		t.Fatalf("order %v, want %s (private and full rooms hidden)", got, want)
	}
	if l.Online != 3+8+6+2+2+4 {
		t.Fatalf("online %d", l.Online)
	}
	if n := len(d.List("neon", 0).Rooms); n != 0 {
		t.Fatalf("map filter returned %d rooms", n)
	}
}

func TestDirectoryCacheAndETag(t *testing.T) {
	now := time.Unix(0, 0)
	d := NewDirectory(func() time.Time { return now })
	d.Update(entry("AAAA", protocol.Public, "LOBBY", 1, 1))
	b1, e1 := d.ListJSON("", 0)
	d.Update(entry("BBBB", protocol.Public, "LOBBY", 1, 2))
	b2, e2 := d.ListJSON("", 0)
	if e1 != e2 || string(b1) != string(b2) {
		t.Fatal("cache rebuilt within 500 ms")
	}
	now = now.Add(600 * time.Millisecond)
	_, e3 := d.ListJSON("", 0)
	if e3 == e1 {
		t.Fatal("cache not rebuilt after 500 ms")
	}
}

func TestDirectoryConcurrentUpdates(t *testing.T) {
	d := NewDirectory(nil)
	var wg sync.WaitGroup
	for w := 0; w < 8; w++ {
		wg.Add(1)
		go func(w int) {
			defer wg.Done()
			for i := 0; i < 500; i++ {
				code := fmt.Sprintf("R%03d", (w*500+i)%50)
				if i%3 == 0 {
					d.Remove(code)
				} else {
					d.Update(entry(code, protocol.Public, "LOBBY", i%8, int64(i)))
				}
				d.List("", 0)
				d.ListJSON("", 0)
			}
		}(w)
	}
	wg.Wait()
	for _, r := range d.List("", 0).Rooms {
		if r.Humans >= 8 || r.Visibility != protocol.Public {
			t.Fatalf("bad listing row %+v", r)
		}
	}
}

func newTestManager(t *testing.T) (*Manager, *Matchmaker, context.CancelFunc) {
	ctx, cancel := context.WithCancel(context.Background())
	mgr := NewManager(ctx, data(t), NewDirectory(nil), nil, time.Millisecond)
	t.Cleanup(func() { cancel(); mgr.Wait() })
	return mgr, NewMatchmaker(mgr), cancel
}

func TestQuickPlayLastSeatOnlyOnce(t *testing.T) {
	mgr, mm, _ := newTestManager(t)
	d := mgr.Dir
	d.Update(Entry{Summary: protocol.RoomSummary{Code: "LAST", Visibility: protocol.Public, State: "LOBBY", Humans: 7, MaxCars: 8}, FreeSeats: 1})
	var wg sync.WaitGroup
	got := make([]string, 2)
	for i := range got {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			code, err := mm.Pick(nil, nil)
			if err != nil {
				t.Error(err)
			}
			got[i] = code
		}(i)
	}
	wg.Wait()
	last := 0
	for _, c := range got {
		if c == "LAST" {
			last++
		}
	}
	if last != 1 {
		t.Fatalf("last seat given %d times: %v", last, got)
	}
}

func TestQuickPlayPrefersMoreHumansAndAvoidsBlocked(t *testing.T) {
	mgr, mm, _ := newTestManager(t)
	d := mgr.Dir
	d.Update(entry("FEW1", protocol.Public, "LOBBY", 1, 1, "x"))
	d.Update(entry("MANY", protocol.Public, "LOBBY", 5, 1, "troll"))
	d.Update(entry("PRIV", protocol.Private, "LOBBY", 7, 1))
	if code, _ := mm.Pick(nil, nil); code != "MANY" {
		t.Fatalf("picked %s, want MANY", code)
	}
	if code, _ := mm.Pick([]string{"troll"}, nil); code != "FEW1" {
		t.Fatalf("picked %s, want FEW1 (MANY has a blocked player)", code)
	}
}

func TestQuickPlayCreatesRoomWhenNoneFits(t *testing.T) {
	mgr, mm, _ := newTestManager(t)
	code, err := mm.Pick(nil, nil)
	if err != nil || mgr.Get(code) == nil {
		t.Fatalf("no room created: %q %v", code, err)
	}
	var vis string
	mgr.Get(code).Do(func(c *Core) { vis = c.Visibility })
	if vis != protocol.Public {
		t.Fatalf("quick play room is %s", vis)
	}
}

func TestEmptyRoomIsDestroyed(t *testing.T) {
	mgr, _, _ := newTestManager(t)
	r, err := mgr.Create(protocol.Public, false)
	if err != nil {
		t.Fatal(err)
	}
	r.Do(func(c *Core) { c.Join("a", "A", "t", nil, func([]byte) {}) })
	r.Do(func(c *Core) { c.Leave("a") })
	select {
	case <-r.Done():
	case <-time.After(10 * time.Second): // 60 s of ticks at 1 ms/tick ≈ 1.8 s
		t.Fatal("empty room not destroyed")
	}
	time.Sleep(10 * time.Millisecond)
	if mgr.Get(r.Code) != nil || len(mgr.Dir.Snapshot()) != 0 {
		t.Fatal("destroyed room still registered")
	}
}

func TestRoomCodesAreClean(t *testing.T) {
	mgr, _, _ := newTestManager(t)
	for i := 0; i < 200; i++ {
		code := mgr.newCode()
		for _, ch := range code {
			if ch == 'I' || ch == 'O' || ch == 'L' {
				t.Fatalf("ambiguous letter in %s", code)
			}
		}
	}
}
