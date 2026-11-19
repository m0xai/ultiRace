// Package moderation filters player names and logs reports (GAME_PLAN §2.3.1, §6.3).
package moderation

import (
	"bufio"
	"fmt"
	"strings"
	"sync"
	"unicode"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/mathx"
)

const (
	MinNameLen = 2
	MaxNameLen = 16
)

var (
	loadOnce sync.Once
	blocked  []string
)

func words() []string {
	loadOnce.Do(func() {
		data, err := gamedata.FS.ReadFile("blocked_words.txt")
		if err != nil {
			panic("moderation: blocked_words.txt missing from gamedata: " + err.Error())
		}
		sc := bufio.NewScanner(strings.NewReader(string(data)))
		for sc.Scan() {
			w := strings.TrimSpace(sc.Text())
			if w != "" && !strings.HasPrefix(w, "#") {
				blocked = append(blocked, strings.ToLower(w))
			}
		}
	})
	return blocked
}

var leet = strings.NewReplacer("0", "o", "1", "i", "3", "e", "4", "a", "5", "s", "7", "t", "8", "b", "@", "a", "$", "s", "!", "i", "|", "l")

// normalise lowercases, undoes leetspeak and splits into letter-only tokens.
func normalise(s string) (joined string, tokens []string) {
	s = leet.Replace(strings.ToLower(s))
	var cur strings.Builder
	var all strings.Builder
	flush := func() {
		if cur.Len() > 0 {
			tokens = append(tokens, cur.String())
			cur.Reset()
		}
	}
	for _, r := range s {
		if r >= 'a' && r <= 'z' {
			cur.WriteRune(r)
			all.WriteRune(r)
		} else {
			flush()
		}
	}
	flush()
	return all.String(), tokens
}

// IsOffensive reports whether s contains a blocked word. Words of ≤ 3 letters only match
// whole tokens (avoids blocking "Cassandra" for "ass"); longer words match anywhere,
// including across separators ("f.u.c.k").
func IsOffensive(s string) bool {
	joined, tokens := normalise(s)
	for _, w := range words() {
		if len(w) <= 3 {
			for _, t := range tokens {
				if t == w {
					return true
				}
			}
			if joined == w {
				return true
			}
			continue
		}
		if strings.Contains(joined, w) {
			return true
		}
	}
	return false
}

// CleanName validates a requested player name. It returns the cleaned name and true, or a
// random fun name and false when the request is empty, too long, uses odd characters or
// contains a blocked word.
func CleanName(name string, rng *mathx.Rng) (string, bool) {
	n := strings.Join(strings.Fields(name), " ") // trim + collapse whitespace
	runes := []rune(n)
	ok := len(runes) >= MinNameLen && len(runes) <= MaxNameLen
	letters := 0
	for _, r := range runes {
		switch {
		case unicode.IsLetter(r):
			letters++
		case unicode.IsDigit(r), r == ' ', r == '_', r == '-', r == '.':
		default:
			ok = false
		}
	}
	if ok && letters > 0 && !IsOffensive(n) {
		return n, true
	}
	return RandomName(rng), false
}

var (
	adjectives = []string{"Speedy", "Turbo", "Zippy", "Lucky", "Sneaky", "Mighty", "Dizzy", "Swift", "Brave", "Jolly", "Rocket", "Fuzzy"}
	animals    = []string{"Otter", "Falcon", "Panda", "Gecko", "Badger", "Lynx", "Koala", "Moose", "Puffin", "Ferret", "Yak", "Fox"}
)

// RandomName returns a fun guest name like "Speedy Otter 42".
func RandomName(rng *mathx.Rng) string {
	return fmt.Sprintf("%s %s %d", adjectives[rng.Intn(len(adjectives))], animals[rng.Intn(len(animals))], 10+rng.Intn(90))
}
