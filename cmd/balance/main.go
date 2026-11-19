// Command balance runs headless bot races and writes docs/BALANCE_REPORT.md (GAME_PLAN §2.9).
package main

import (
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/balance"
	"github.com/m0xai/ultiRace/internal/room"
)

func main() {
	races := flag.Int("races", 500, "number of races")
	laps := flag.Int("laps", 3, "laps per race")
	seed := flag.Uint("seed", 1, "base seed")
	out := flag.String("out", "docs/BALANCE_REPORT.md", "report path ('' = stdout only)")
	balPath := flag.String("balance", "", "balance.json to use instead of the embedded one")
	tuneIters := flag.Int("tune", 0, "tune: random-search iterations (writes -tune-out)")
	tuneOut := flag.String("tune-out", "gamedata/balance.json", "where the tuner writes the best balance")
	withPace := flag.Bool("tune-all", false, "stage-2 tuning may also change the pace knobs")
	trial := flag.Bool("trial", false, "print solo lap times per vehicle and map, then exit")
	tuneTrimIters := flag.Int("tune-trim", 0, "per-vehicle top-speed trim feedback rounds (writes -tune-out)")
	tunePaceIters := flag.Int("tune-pace", 0, "stage-1 tuning: equalise solo pace (writes -tune-out)")
	flag.Parse()
	bal, err := gamedata.LoadBalance()
	if *balPath != "" {
		bal, err = gamedata.LoadBalanceFile(*balPath)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if *tunePaceIters > 0 {
		bal = tunePace(bal, *tunePaceIters, *tuneOut)
	}
	if *tuneTrimIters > 0 {
		bal = tuneTrim(bal, *tuneTrimIters, 1000, *laps, *tuneOut)
	}
	if *tuneIters > 0 {
		bal = tune(bal, *tuneIters, 120, *laps, *tuneOut, *withPace)
	}
	d, err := room.LoadDataWith(bal)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if *trial {
		tt := balance.TimeTrial(d, 2)
		for _, m := range d.MapIDs {
			fmt.Printf("%-7s", m)
			for _, v := range d.Vehicles {
				fmt.Printf(" %s=%.2f", v.ID, tt[m][v.ID])
			}
			fmt.Println()
		}
		return
	}
	start := time.Now()
	s := balance.Summarize(balance.Run(d, *races, *laps, uint32(*seed)))
	md := s.Markdown(*laps)
	fmt.Print(md)
	fmt.Printf("\n%d races in %s\n", *races, time.Since(start).Round(time.Millisecond))
	if *out != "" {
		if err := os.WriteFile(*out, []byte(md), 0o644); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	if !s.AllOK() {
		os.Exit(3)
	}
}
