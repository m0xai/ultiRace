package protocol

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"
)

func TestDecodeClientRoundTrip(t *testing.T) {
	for _, m := range clientExamples() {
		data := Encode(m)
		got, err := DecodeClient(data)
		if err != nil {
			t.Fatalf("%T: %v", m, err)
		}
		if !reflect.DeepEqual(reflect.ValueOf(got).Elem().Interface(), m) {
			t.Fatalf("%T: round trip mismatch\n got %+v\nwant %+v", m, got, m)
		}
	}
}

func TestDecodeClientRejectsBadInput(t *testing.T) {
	bad := [][]byte{
		[]byte(`not json`),
		[]byte(`{"t":"nope"}`),
		[]byte(`{"t":"in","seq":1,"steer":2,"thr":1}`),
		[]byte(`{"t":"in","seq":1,"steer":0,"thr":-1}`),
		[]byte(`{"t":"ready","ready":"yes"}`),
		bytes.Repeat([]byte("a"), MaxMessageBytes+1),
	}
	for _, b := range bad {
		if _, err := DecodeClient(b); err == nil {
			t.Errorf("accepted %q", b[:min(len(b), 40)])
		}
	}
	if _, err := DecodeClient([]byte(`{"t":"zzz"}`)); !errors.Is(err, ErrUnknownType) {
		t.Errorf("want ErrUnknownType, got %v", err)
	}
}

func TestSnapshotRoundTripWithinQuantisation(t *testing.T) {
	cars := []SnapCar{
		{ID: 0, S: 1234.5678, D: -9.876, YawRel: 0.4321, Y: 1.23, Speed: 39.99, Vy: -7.5, Lap: 2, Flags: FlagFinished},
		{ID: 7, S: 0, D: 10.99, YawRel: -0.85, Y: 0, Speed: 0, Vy: 0, Lap: -1},
	}
	b := PatchAck(EncodeSnapshot(4242, cars), 99)
	if len(b) != 10+2*18+2 {
		t.Fatalf("size %d", len(b))
	}
	s, err := DecodeSnapshot(b)
	if err != nil {
		t.Fatal(err)
	}
	if s.Ack != 99 || s.Tick != 4242 || len(s.Cars) != 2 {
		t.Fatalf("header %+v", s)
	}
	for i, c := range cars {
		g := s.Cars[i]
		if g.ID != c.ID || g.Lap != c.Lap || g.Flags != c.Flags ||
			math.Abs(g.S-c.S) > QS/2+1e-9 || math.Abs(g.D-c.D) > QS/2+1e-9 ||
			math.Abs(g.YawRel-c.YawRel) > QYaw/2+1e-9 || math.Abs(g.Speed-c.Speed) > QSpeed/2+1e-9 ||
			math.Abs(g.Vy-c.Vy) > QSpeed/2+1e-9 || math.Abs(g.Y-c.Y) > QS/2+1e-9 {
			t.Fatalf("car %d: got %+v want %+v", i, g, c)
		}
	}
	if _, err := DecodeSnapshot(b[:15]); err == nil {
		t.Fatal("accepted truncated snapshot")
	}
}

func TestPosInFlags(t *testing.T) {
	f := WithPos(FlagFinished, 7)
	if Pos(f) != 7 || f&FlagFinished == 0 {
		t.Fatalf("flags %b", f)
	}
	if Pos(WithPos(f, 3)) != 3 {
		t.Fatal("overwrite failed")
	}
}

func TestSnapshotBandwidthBudget(t *testing.T) {
	// 8 cars at 20 Hz must stay ≤ 4 KB/s (GAME_PLAN §8), leaving room for events.
	b := EncodeSnapshot(1, make([]SnapCar, 8))
	if perSec := len(b) * 20; perSec > 3500 {
		t.Fatalf("snapshots alone use %d B/s", perSec)
	}
}

// ---------- fixtures for Protocol.gd ----------

func clientExamples() []any {
	return []any{
		Hello{T: THello, V: Version, Name: "Speedy Otter", Token: "tok", Room: "ABCD", Quick: true, Blocked: []string{"p1"}, Auth: &Auth{Provider: "guest"}, Create: &CreateOpts{Visibility: Public}},
		Ready{T: TReady, Ready: true},
		Settings{T: TSettings, Map: "neon", Laps: 2, Bots: true, Visibility: Private},
		Start{T: TStart},
		Kick{T: TKick, PlayerID: "p2"},
		Preview{T: TPreview, Vehicle: "bolt"},
		Lock{T: TLock, Vehicle: "rhino"},
		In{T: TIn, Seq: 77, Steer: -1, Thr: 1, Ab: true},
		Rematch{T: TRematch},
		Report{T: TReport, PlayerID: "p3", Reason: "name"},
		Ping{T: TPing, Ts: 1700000000123},
		Leave{T: TLeave},
	}
}

func serverExamples() []any {
	return []any{
		Welcome{T: TWelcome, PlayerID: "p1", Token: "tok", Room: "ABCD"},
		RoomState{T: TRoom, Code: "ABCD", Name: "Sunny Circuit · 3 laps · #ABCD Turbo", State: "LOBBY", Visibility: Public, Map: "sunny", Laps: 3, Bots: true,
			Players: []PlayerInfo{{ID: "p1", Name: "A", Host: true, Ready: true, PingMs: 40}, {ID: "b1", Name: "Bot Bolt", Bot: true}}, Deadline: 1700000030000, Region: DefaultRegion},
		Select{T: TSelect, Claims: []Claim{{Vehicle: "bolt", PlayerID: "p1"}}, Previews: map[string]string{"p2": "goo"}, Deadline: 1700000020000},
		RaceStart{T: TRaceStart, Seed: 42, Map: "neon", Laps: 3, Grid: []GridSlot{{Car: 0, PlayerID: "p1", Vehicle: "bolt", Name: "A"}}, StartAt: 1700000003000, Tick: 90, You: 0},
		Ev{T: TEv, Kind: "lap", Tick: 1200, Car: 3, Value: 2},
		Results{T: TResults, Rows: []ResultRow{{Pos: 1, Car: 0, PlayerID: "p1", Name: "A", Vehicle: "bolt", Finished: true, TimeMs: 110000, BestLap: 35000}},
			Verified: []Verified{{PlayerID: "p1", BestLap: 35000, TimeMs: 110000, Won: true}}},
		Kicked{T: TKicked, Reason: "host"},
		Pong{T: TPong, Ts: 1700000000123},
		Err{T: TErr, Code: ErrVersion, Msg: "please update"},
	}
}

type protocolFixture struct {
	Version  int               `json:"version"`
	Client   []json.RawMessage `json:"client"`
	Server   []json.RawMessage `json:"server"`
	Snapshot struct {
		Base64 string    `json:"base64"`
		Ack    uint32    `json:"ack"`
		Tick   uint32    `json:"tick"`
		Cars   []SnapCar `json:"cars"` // exact decoded (quantised) values
	} `json:"snapshot"`
}

func TestProtocolFixture(t *testing.T) {
	var f protocolFixture
	f.Version = Version
	for _, m := range clientExamples() {
		f.Client = append(f.Client, Encode(m))
	}
	for _, m := range serverExamples() {
		f.Server = append(f.Server, Encode(m))
	}
	cars := []SnapCar{
		{ID: 0, S: 1234.5678, D: -9.876, YawRel: 0.4321, Y: 1.23, Speed: 39.99, Vy: -7.5, Lap: 2, Flags: WithPos(FlagFinished, 1)},
		{ID: 5, S: 17.04, D: 3.3, YawRel: -0.2, Speed: 21.5, Lap: -1, Flags: WithPos(0, 6)},
	}
	b := PatchAck(EncodeSnapshot(4242, cars), 99)
	dec, _ := DecodeSnapshot(b)
	f.Snapshot.Base64 = base64.StdEncoding.EncodeToString(b)
	f.Snapshot.Ack, f.Snapshot.Tick, f.Snapshot.Cars = dec.Ack, dec.Tick, dec.Cars
	data, err := json.MarshalIndent(f, "", " ")
	if err != nil {
		t.Fatal(err)
	}
	data = append(data, '\n')
	path := filepath.Join("..", "..", "gamedata", "fixtures", "protocol", "messages.json")
	if os.Getenv("ULTIRACE_WRITE_FIXTURES") == "1" {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, data, 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	old, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(old, data) {
		t.Fatalf("protocol fixture stale or missing: run make fixtures && make sync")
	}
}

func TestEveryClientTypeHasAnExample(t *testing.T) {
	seen := map[string]bool{}
	for _, m := range clientExamples() {
		var env Envelope
		_ = json.Unmarshal(Encode(m), &env)
		seen[env.T] = true
	}
	want := []string{THello, TReady, TSettings, TStart, TKick, TPreview, TLock, TIn, TRematch, TReport, TPing, TLeave}
	var missing []string
	for _, w := range want {
		if !seen[w] {
			missing = append(missing, w)
		}
	}
	sort.Strings(missing)
	if len(missing) > 0 {
		t.Fatalf("no fixture example for %v", missing)
	}
}
