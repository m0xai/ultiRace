package server

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/m0xai/ultiRace/internal/botclient"
	"github.com/m0xai/ultiRace/internal/protocol"
	"github.com/m0xai/ultiRace/internal/room"
)

func startServer(t *testing.T, cfg Config) (*Server, *httptest.Server) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	srv, err := New(ctx, cfg, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(func() {
		ts.Close()
		cancel()
		srv.Rooms.Wait()
	})
	return srv, ts
}

func wsURL(ts *httptest.Server) string { return "ws" + strings.TrimPrefix(ts.URL, "http") }

// M2 "done when": Go bot clients Quick Play into rooms and finish races over WebSocket.
func TestE2EQuickPlayBotsFinishRace(t *testing.T) {
	if testing.Short() {
		t.Skip("e2e")
	}
	srv, ts := startServer(t, Config{TestMode: true, TimeScale: 10})
	data, _ := room.LoadData()
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	const n = 4
	results := make([]*botclient.Result, n)
	errs := make([]error, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			results[i], errs[i] = botclient.Run(ctx, botclient.Options{URL: wsURL(ts), Name: "Bot Client " + string(rune('A'+i)), Quick: true, HostLaps: 2, Data: data})
		}(i)
		time.Sleep(20 * time.Millisecond)
	}
	wg.Wait()
	rooms := map[string]bool{}
	for i, r := range results {
		if errs[i] != nil {
			t.Fatalf("client %d: %v", i, errs[i])
		}
		if r.Races != 1 || len(r.Finished) != 1 || !r.Finished[0] {
			t.Fatalf("client %d did not finish: %+v", i, r)
		}
		if r.Snapshots < 100 || r.Inputs < 100 {
			t.Fatalf("client %d: %d snapshots, %d inputs", i, r.Snapshots, r.Inputs)
		}
		for _, e := range r.Errors {
			if e == protocol.ErrRateLimited || e == protocol.ErrBadMessage {
				t.Fatalf("client %d got %s errors", i, e)
			}
		}
		rooms[r.Room] = true
		t.Logf("client %d: room %s pos %d errors %v", i, r.Room, r.Positions[0], r.Errors)
	}
	if len(rooms) != 1 {
		t.Fatalf("quick play spread %d clients over %d rooms, want 1", n, len(rooms))
	}
	_ = srv
}

func TestE2EPracticeRace(t *testing.T) {
	if testing.Short() {
		t.Skip("e2e")
	}
	_, ts := startServer(t, Config{TestMode: true, TimeScale: 10})
	data, _ := room.LoadData()
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	r, err := botclient.Run(ctx, botclient.Options{URL: wsURL(ts), Name: "Solo", Practice: true, HostLaps: 2, Data: data})
	if err != nil {
		t.Fatal(err)
	}
	if r.Races != 1 || !r.Finished[0] {
		t.Fatalf("practice race not finished: %+v", r)
	}
}

func TestWSRejectsOldVersionAndGarbage(t *testing.T) {
	_, ts := startServer(t, Config{})
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	for _, first := range []string{`{"t":"hello","v":0,"name":"x","quick":true}`, `{"t":"in","seq":1}`, `garbage`} {
		ws, _, err := websocket.Dial(ctx, wsURL(ts)+"/ws", nil)
		if err != nil {
			t.Fatal(err)
		}
		_ = ws.Write(ctx, websocket.MessageText, []byte(first))
		_, data, err := ws.Read(ctx)
		if err == nil {
			var e protocol.Err
			_ = json.Unmarshal(data, &e)
			if e.T != protocol.TErr {
				t.Fatalf("%s: got %s", first, data)
			}
		}
		ws.CloseNow()
	}
}

func TestRoomsAPIListsPublicRoomWithETag(t *testing.T) {
	srv, ts := startServer(t, Config{})
	if _, err := srv.Rooms.Create(protocol.Public, false); err != nil {
		t.Fatal(err)
	}
	if _, err := srv.Rooms.Create(protocol.Private, false); err != nil {
		t.Fatal(err)
	}
	time.Sleep(600 * time.Millisecond) // directory cache window
	res, err := http.Get(ts.URL + "/api/rooms")
	if err != nil {
		t.Fatal(err)
	}
	var list protocol.RoomList
	_ = json.NewDecoder(res.Body).Decode(&list)
	res.Body.Close()
	if len(list.Rooms) != 1 || list.Rooms[0].Visibility != protocol.Public {
		t.Fatalf("listing %+v", list)
	}
	req, _ := http.NewRequest("GET", ts.URL+"/api/rooms", nil)
	req.Header.Set("If-None-Match", res.Header.Get("ETag"))
	res2, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res2.Body.Close()
	if res2.StatusCode != http.StatusNotModified {
		t.Fatalf("status %d, want 304", res2.StatusCode)
	}
	res3, err := http.Post(ts.URL+"/api/quickplay", "application/json", strings.NewReader(`{"blocked":[]}`))
	if err != nil {
		t.Fatal(err)
	}
	var qp quickPlayResp
	_ = json.NewDecoder(res3.Body).Decode(&qp)
	res3.Body.Close()
	if qp.Room != list.Rooms[0].Code {
		t.Fatalf("quickplay picked %q, want the public lobby %q", qp.Room, list.Rooms[0].Code)
	}
}

func TestClientIPTrustsForwardedOnlyFromLoopback(t *testing.T) {
	r := httptest.NewRequest("GET", "/", nil)
	r.RemoteAddr = "127.0.0.1:5555"
	r.Header.Set("X-Forwarded-For", "6.6.6.6, 203.0.113.9")
	if ip := clientIP(r); ip != "203.0.113.9" {
		t.Fatalf("got %s", ip)
	}
	r.RemoteAddr = "198.51.100.7:5555"
	if ip := clientIP(r); ip != "198.51.100.7" {
		t.Fatalf("spoofed XFF trusted: %s", ip)
	}
}
