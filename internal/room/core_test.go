package room

import (
	"encoding/json"
	"sync"
	"testing"
	"time"

	"github.com/m0xai/ultiRace/internal/protocol"
)

var (
	dataOnce sync.Once
	testData *Data
)

func data(t testing.TB) *Data {
	t.Helper()
	dataOnce.Do(func() {
		d, err := LoadData()
		if err != nil {
			panic(err)
		}
		testData = d
	})
	return testData
}

// inbox records everything sent to one fake client.
type inbox struct {
	mu   sync.Mutex
	json []map[string]any
	snap int
}

func (b *inbox) send(msg []byte) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if len(msg) > 0 && msg[0] == protocol.SnapKind {
		b.snap++
		return
	}
	var m map[string]any
	if err := json.Unmarshal(msg, &m); err != nil {
		panic(err)
	}
	b.json = append(b.json, m)
}

func (b *inbox) last(t string) map[string]any {
	b.mu.Lock()
	defer b.mu.Unlock()
	for i := len(b.json) - 1; i >= 0; i-- {
		if b.json[i]["t"] == t {
			return b.json[i]
		}
	}
	return nil
}

func (b *inbox) count(t string) int {
	b.mu.Lock()
	defer b.mu.Unlock()
	n := 0
	for _, m := range b.json {
		if m["t"] == t {
			n++
		}
	}
	return n
}

var fakeNow = time.Unix(1_700_000_000, 0)

func newCore(t testing.TB, vis string) *Core {
	return NewCore(data(t), Options{Code: "TEST", Visibility: vis, Seed: 1, Now: func() time.Time { return fakeNow }})
}

func join(c *Core, id string) *inbox {
	b := &inbox{}
	if r := c.Join(id, "Name "+id, "tok-"+id, nil, b.send); r.Err != "" {
		panic(r.Err)
	}
	return b
}

func steps(c *Core, n int) {
	for range n {
		c.Step()
	}
}

func secs(c *Core, s float64) int { return c.ticks(s) }

func TestPublicLobbySoloStartsAfter60s(t *testing.T) {
	c := newCore(t, protocol.Public)
	join(c, "a")
	steps(c, secs(c, 59))
	if c.State != Lobby {
		t.Fatalf("left lobby early: %s", c.State)
	}
	steps(c, secs(c, 1.1))
	if c.State != Select {
		t.Fatalf("state %s, want SELECT after 60 s with one human", c.State)
	}
}

func TestPublicLobbyTwoHumans30sAndLateJoinReset(t *testing.T) {
	c := newCore(t, protocol.Public)
	join(c, "a")
	steps(c, secs(c, 5))
	join(c, "b")
	steps(c, 1)
	if left := c.deadline - c.tick; left > secs(c, 30) || left < secs(c, 29) {
		t.Fatalf("deadline in %d ticks, want ≈30 s", left)
	}
	steps(c, secs(c, 25)) // 5 s left
	join(c, "c")          // late join → ≥ 10 s
	steps(c, 1)
	if left := c.deadline - c.tick; left < secs(c, 9.9) {
		t.Fatalf("late join did not reset timer: %d ticks left", left)
	}
}

func TestPublicAllReadyShortensTo5s(t *testing.T) {
	c := newCore(t, protocol.Public)
	join(c, "a")
	join(c, "b")
	steps(c, 1)
	c.Handle("a", &protocol.Ready{Ready: true})
	c.Handle("b", &protocol.Ready{Ready: true})
	steps(c, 1)
	if left := c.deadline - c.tick; left > secs(c, 5) {
		t.Fatalf("all ready: %d ticks left, want ≤ 5 s", left)
	}
}

func TestPrivateHostStartRequiresReady(t *testing.T) {
	c := newCore(t, protocol.Private)
	a := join(c, "a")
	join(c, "b")
	steps(c, secs(c, 120))
	if c.State != Lobby {
		t.Fatal("private room started on its own")
	}
	c.Handle("b", &protocol.Start{})
	if c.State != Lobby {
		t.Fatal("non-host started the race")
	}
	c.Handle("a", &protocol.Start{})
	if c.State != Lobby || a.last(protocol.TErr) == nil {
		t.Fatal("host started before others were ready")
	}
	c.Handle("b", &protocol.Ready{Ready: true})
	c.Handle("a", &protocol.Start{})
	if c.State != Select {
		t.Fatalf("state %s after host start", c.State)
	}
}

func TestPrivateAutoStart3sAfterAllReady(t *testing.T) {
	c := newCore(t, protocol.Private)
	join(c, "a")
	c.Handle("a", &protocol.Ready{Ready: true})
	steps(c, secs(c, 3)+2)
	if c.State != Select {
		t.Fatalf("state %s, want SELECT 3 s after all ready", c.State)
	}
}

func toSelect(t *testing.T, c *Core) {
	t.Helper()
	for _, p := range c.seatedHumans() {
		c.Handle(p.ID, &protocol.Ready{Ready: true})
	}
	c.Handle(c.hostID, &protocol.Start{})
	if c.State != Select {
		t.Fatalf("could not reach SELECT: %s", c.State)
	}
}

func TestFirstLockWins(t *testing.T) {
	c := newCore(t, protocol.Private)
	join(c, "a")
	b := join(c, "b")
	toSelect(t, c)
	c.Handle("a", &protocol.Lock{Vehicle: "bolt"})
	c.Handle("b", &protocol.Lock{Vehicle: "bolt"})
	if c.claims["bolt"] != "a" {
		t.Fatalf("bolt claimed by %q", c.claims["bolt"])
	}
	if e := b.last(protocol.TErr); e == nil || e["code"] != protocol.ErrTaken {
		t.Fatalf("b got %v, want taken error", e)
	}
	c.Handle("b", &protocol.Lock{Vehicle: "goo"})
	steps(c, 1) // all humans locked → race starts early
	if c.State != Countdown {
		t.Fatalf("state %s, want COUNTDOWN once every human locked", c.State)
	}
	if len(c.grid) != 8 {
		t.Fatalf("grid has %d cars, want 8 (bots fill)", len(c.grid))
	}
	seen := map[string]bool{}
	for _, p := range c.grid {
		if seen[p.vehicle] {
			t.Fatalf("vehicle %s used twice", p.vehicle)
		}
		seen[p.vehicle] = true
	}
}

func TestSelectTimeoutAssignsRandomVehicle(t *testing.T) {
	c := newCore(t, protocol.Private)
	join(c, "a")
	toSelect(t, c)
	steps(c, secs(c, 20)+1)
	if c.State != Countdown {
		t.Fatalf("state %s after select timeout", c.State)
	}
	if c.find("a").vehicle == "" {
		t.Fatal("unlocked human got no vehicle")
	}
}

func TestFullRaceToResultsAndBackToLobby(t *testing.T) {
	c := newCore(t, protocol.Public)
	a := join(c, "a")
	c.Laps = 1
	toSelect(t, c)
	c.Handle("a", &protocol.Lock{Vehicle: "volt"})
	steps(c, 1)
	if a.last(protocol.TRaceStart) == nil {
		t.Fatal("no raceStart")
	}
	if you := a.last(protocol.TRaceStart)["you"].(float64); you < 0 {
		t.Fatal("racer got you=-1")
	}
	// drive "a" with full throttle; AFK detection must not trigger (input changes)
	seq := uint32(0)
	for i := 0; i < 30*200 && c.State != Results; i++ {
		seq++
		c.Handle("a", &protocol.In{Seq: seq, Steer: []int{-1, 0, 1}[i%3], Thr: 1})
		c.Step()
	}
	if c.State != Results {
		t.Fatalf("race did not finish: %s", c.State)
	}
	res := a.last(protocol.TResults)
	if res == nil || len(res["rows"].([]any)) != 8 {
		t.Fatalf("results %v", res)
	}
	if a.snap < 100 {
		t.Fatalf("only %d snapshots", a.snap)
	}
	steps(c, secs(c, 10)+1)
	if c.State != Lobby || len(c.grid) != 0 {
		t.Fatalf("state %s after results", c.State)
	}
}

func TestDisconnectDuringRaceBotTakesOverAndReconnect(t *testing.T) {
	c := newCore(t, protocol.Private)
	join(c, "a")
	toSelect(t, c)
	steps(c, secs(c, 21)+secs(c, 3)+5)
	if c.State != Racing {
		t.Fatalf("state %s", c.State)
	}
	c.Disconnect("a")
	if c.find("a") == nil {
		t.Fatal("racing player removed on disconnect")
	}
	before := c.world.Cars[c.find("a").car].State.S
	steps(c, 30)
	if c.world.Cars[c.find("a").car].State.S == before {
		t.Fatal("nobody drives the disconnected car")
	}
	b := &inbox{}
	if _, ok := c.Reconnect("tok-a", b.send); !ok {
		t.Fatal("reconnect failed")
	}
	if b.last(protocol.TRaceStart) == nil {
		t.Fatal("reconnected player did not get raceStart")
	}
	c.Disconnect("a")
	steps(c, secs(c, 31))
	if _, ok := c.Reconnect("tok-a", (&inbox{}).send); ok {
		t.Fatal("reconnect allowed after the 30 s window")
	}
}

func TestHostMigrationAndKickBan(t *testing.T) {
	c := newCore(t, protocol.Public)
	join(c, "a")
	bIn := join(c, "b")
	join(c, "c")
	c.Leave("a")
	if c.hostID != "b" {
		t.Fatalf("host %q, want b", c.hostID)
	}
	cIn := &inbox{}
	_ = cIn
	c.Handle("b", &protocol.Kick{PlayerID: "c"})
	if c.find("c") != nil {
		t.Fatal("kicked player still in room")
	}
	if r := c.Join("c", "C", "tok-c", nil, (&inbox{}).send); r.Err != protocol.ErrBanned {
		t.Fatalf("rejoin after kick: %+v", r)
	}
	steps(c, secs(c, 600)+1)
	// lobby may have started a race by now; rejoin must at least not be banned
	if r := c.Join("c", "C", "tok-c", nil, (&inbox{}).send); r.Err != "" {
		t.Fatalf("still banned after 10 min: %+v", r)
	}
	_ = bIn
}

func TestLateJoinerSpectatesThenGetsSeat(t *testing.T) {
	c := newCore(t, protocol.Private)
	join(c, "a")
	c.Laps = 1
	toSelect(t, c)
	steps(c, secs(c, 21))
	s := join(c, "late")
	if !c.find("late").spec {
		t.Fatal("late joiner not spectating")
	}
	if rs := s.last(protocol.TRaceStart); rs == nil || rs["you"].(float64) != -1 {
		t.Fatalf("spectator raceStart %v", rs)
	}
	for i := 0; i < 30*200 && c.State != Lobby; i++ {
		c.Step()
	}
	if c.State != Lobby || c.find("late").spec {
		t.Fatalf("state %s, spec %v", c.State, c.find("late").spec)
	}
}

func TestAfkHandedToBotAndKickedAfterTwoPublicRaces(t *testing.T) {
	c := newCore(t, protocol.Public)
	a := join(c, "a")
	c.Laps = 1
	for race := 0; race < 2; race++ {
		for i := 0; i < 30*400 && c.State != Racing; i++ {
			c.Step()
		}
		for i := 0; i < 30*300 && c.State == Racing; i++ {
			c.Step() // never sends input → AFK after 20 s, bot drives
		}
		if c.State != Results && c.State != Lobby {
			t.Fatalf("race %d did not end: %s", race, c.State)
		}
	}
	if k := a.last(protocol.TKicked); k == nil || k["reason"] != "afk" {
		t.Fatalf("not kicked for AFK: %v", k)
	}
}

func TestRoomNameIsGenerated(t *testing.T) {
	c := newCore(t, protocol.Public)
	join(c, "a")
	c.Handle("a", &protocol.Settings{Map: "neon", Laps: 2, Bots: true, Visibility: protocol.Public})
	if c.Name[:len("Neon Overpass · 2 laps · #TEST ")] != "Neon Overpass · 2 laps · #TEST " {
		t.Fatalf("name %q", c.Name)
	}
	c.Handle("a", &protocol.Settings{Map: "nope", Laps: 2, Visibility: protocol.Public})
	if c.Map != "neon" {
		t.Fatal("accepted unknown map")
	}
}

func BenchmarkRoomRacingTick(b *testing.B) {
	c := NewCore(data(b), Options{Code: "BNCH", Visibility: protocol.Private, Seed: 1})
	c.Join("a", "A", "t", nil, func([]byte) {})
	c.Handle("a", &protocol.Ready{Ready: true})
	c.Handle("a", &protocol.Start{})
	for c.State != Racing {
		c.Step()
	}
	b.ResetTimer()
	for b.Loop() {
		c.Step()
		if c.State != Racing {
			b.StopTimer()
			for c.State != Racing {
				if c.State == Lobby {
					c.Handle("a", &protocol.Ready{Ready: true})
					c.Handle("a", &protocol.Start{})
				}
				c.Step()
			}
			b.StartTimer()
		}
	}
}

// M7: racing inputs are applied one per tick in order, and the snapshot ack is the seq of the
// input the simulation used last (the client replays everything after it).
func TestRacingInputsQueuedOnePerTick(t *testing.T) {
	c := newCore(t, protocol.Private)
	join(c, "a")
	toSelect(t, c)
	for c.State != Racing {
		c.Step()
	}
	p := c.find("a")
	for seq := uint32(1); seq <= 3; seq++ { // a burst of three inputs in one tick
		c.Handle("a", &protocol.In{Seq: seq, Steer: int(seq%3) - 1, Thr: 1})
	}
	for want := uint32(1); want <= 3; want++ {
		c.Step()
		if p.ack != want {
			t.Fatalf("after step: ack %d, want %d", p.ack, want)
		}
	}
	c.Step() // queue empty: last input repeats, ack unchanged
	if p.ack != 3 {
		t.Fatalf("ack moved without input: %d", p.ack)
	}
	// late burst after a gap: inputs covering the starved ticks are acked, not applied later
	c.Step() // second starved tick (one more above)
	for seq := uint32(4); seq <= 6; seq++ {
		c.Handle("a", &protocol.In{Seq: seq, Thr: 1})
	}
	c.Step()
	if p.ack != 6 || len(p.queue) != 0 {
		t.Fatalf("after gap of 2 ticks + burst of 3: ack %d queue %d, want ack 6 queue 0", p.ack, len(p.queue))
	}
	for seq := uint32(7); seq <= 20; seq++ { // flood: queue stays bounded
		c.Handle("a", &protocol.In{Seq: seq, Thr: 1})
	}
	if len(p.queue) > maxInputQueue {
		t.Fatalf("queue %d > %d", len(p.queue), maxInputQueue)
	}
}
