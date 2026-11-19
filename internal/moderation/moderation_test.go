package moderation

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/m0xai/ultiRace/internal/mathx"
)

func TestCleanName(t *testing.T) {
	rng := mathx.NewRng(1)
	good := map[string]string{
		"Kerem":             "Kerem",
		"  Speedy   Otter ": "Speedy Otter",
		"Cassandra":         "Cassandra", // contains "ass" but is not a whole token
		"Bass_Player-7":     "Bass_Player-7",
		"Ömer":              "Ömer",
		"Scunthorpe Fan":    "", // contains a long blocked word: rejected (documented trade-off)
	}
	for in, want := range good {
		got, ok := CleanName(in, rng)
		if want == "" {
			if ok {
				t.Errorf("%q accepted as %q", in, got)
			}
			continue
		}
		if !ok || got != want {
			t.Errorf("%q → %q (%v), want %q", in, got, ok, want)
		}
	}
	bad := []string{"", "a", "ThisNameIsWayTooLong", "f.u.c.k", "Sh1t Driver", "ass", "x<script>", "1234", "n4zi", "😀😀😀"}
	for _, in := range bad {
		got, ok := CleanName(in, rng)
		if ok {
			t.Errorf("%q accepted", in)
		}
		if !strings.Contains(got, " ") || len(got) < 5 {
			t.Errorf("%q: fallback name %q looks wrong", in, got)
		}
	}
}

func TestRandomNameIsClean(t *testing.T) {
	rng := mathx.NewRng(5)
	for range 500 {
		n := RandomName(rng)
		if _, ok := CleanName(n, rng); !ok {
			t.Fatalf("generated name %q fails the filter", n)
		}
	}
}

func TestReportLogAppendsJSONLines(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", "reports.jsonl")
	l := NewReportLog(path)
	for _, reason := range []string{"name", "WEIRD"} {
		if err := l.Add(Report{Time: time.Unix(1, 0), Room: "ABCD", Reporter: "p1", Target: "p2", Reason: reason}); err != nil {
			t.Fatal(err)
		}
	}
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	var reasons []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		var r Report
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			t.Fatal(err)
		}
		reasons = append(reasons, r.Reason)
	}
	if strings.Join(reasons, ",") != "name,other" {
		t.Fatalf("reasons %v", reasons)
	}
}

func TestBanListReload(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bans.json")
	b, err := NewBanList(path) // missing file: no bans
	if err != nil || b.Banned("p1") {
		t.Fatalf("missing file: %v %v", err, b.Banned("p1"))
	}
	if err := os.WriteFile(path, []byte(`{"players":["p1","p2"]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := b.Reload(); err != nil || !b.Banned("p2") || b.Banned("p3") || b.Count() != 2 {
		t.Fatalf("reload: %v count %d", err, b.Count())
	}
	_ = os.WriteFile(path, []byte(`not json`), 0o644)
	if err := b.Reload(); err == nil || !b.Banned("p1") {
		t.Fatal("bad file must fail and keep the old list")
	}
}
