package moderation

import (
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"sync"
)

// BanList is /data/bans.json: {"players": ["p1a2b3c4d5e6", ...]} (anonymous player ids, GAME_PLAN
// §6.3). Reloaded on SIGHUP. A missing file means no bans.
type BanList struct {
	path string
	mu   sync.RWMutex
	ids  map[string]bool
}

// NewBanList loads path (if it exists).
func NewBanList(path string) (*BanList, error) {
	b := &BanList{path: path, ids: map[string]bool{}}
	return b, b.Reload()
}

// Reload re-reads the file.
func (b *BanList) Reload() error {
	if b == nil || b.path == "" {
		return nil
	}
	data, err := os.ReadFile(b.path)
	if errors.Is(err, fs.ErrNotExist) {
		b.mu.Lock()
		b.ids = map[string]bool{}
		b.mu.Unlock()
		return nil
	}
	if err != nil {
		return err
	}
	var f struct {
		Players []string `json:"players"`
	}
	if err := json.Unmarshal(data, &f); err != nil {
		return err
	}
	ids := make(map[string]bool, len(f.Players))
	for _, p := range f.Players {
		ids[p] = true
	}
	b.mu.Lock()
	b.ids = ids
	b.mu.Unlock()
	return nil
}

// Banned reports whether a player id is banned.
func (b *BanList) Banned(id string) bool {
	if b == nil {
		return false
	}
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.ids[id]
}

// Count returns the number of banned players.
func (b *BanList) Count() int {
	if b == nil {
		return 0
	}
	b.mu.RLock()
	defer b.mu.RUnlock()
	return len(b.ids)
}
