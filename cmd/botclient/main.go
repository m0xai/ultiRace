// Command botclient runs headless WebSocket clients against a server for e2e, load and soak
// tests (GAME_PLAN §9): go run ./cmd/botclient -url ws://127.0.0.1:8090 -clients 8 -races 1
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/m0xai/ultiRace/internal/botclient"
	"github.com/m0xai/ultiRace/internal/room"
)

func main() {
	url := flag.String("url", "ws://127.0.0.1:8090", "server base URL")
	clients := flag.Int("clients", 4, "number of concurrent clients")
	races := flag.Int("races", 1, "races per client")
	laps := flag.Int("laps", 2, "laps when a client becomes host (2 or 3)")
	practice := flag.Bool("practice", false, "each client plays a private practice room (load test: one room per client)")
	timeout := flag.Duration("timeout", 10*time.Minute, "overall timeout")
	stagger := flag.Duration("stagger", 50*time.Millisecond, "delay between client starts")
	flag.Parse()

	data, err := room.LoadData()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	start := time.Now()
	results := make([]*botclient.Result, *clients)
	errs := make([]error, *clients)
	var wg sync.WaitGroup
	for i := 0; i < *clients; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			results[i], errs[i] = botclient.Run(ctx, botclient.Options{
				URL: *url, Name: fmt.Sprintf("Load Bot %d", i), Quick: !*practice, Practice: *practice,
				Races: *races, HostLaps: *laps, Data: data,
			})
		}(i)
		time.Sleep(*stagger)
	}
	wg.Wait()

	rooms := map[string]int{}
	failed, finished := 0, 0
	for i, r := range results {
		if errs[i] != nil || r == nil || r.Races < *races {
			failed++
			fmt.Fprintf(os.Stderr, "client %d: err=%v result=%+v\n", i, errs[i], r)
			continue
		}
		rooms[r.Room]++
		for _, f := range r.Finished {
			if f {
				finished++
			}
		}
	}
	fmt.Printf("clients=%d failed=%d rooms=%d racesFinished=%d elapsed=%s\n", *clients, failed, len(rooms), finished, time.Since(start).Round(time.Millisecond))
	if failed > 0 {
		os.Exit(1)
	}
}
