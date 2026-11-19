package moderation

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// Report is one line of the append-only reports log reviewed by the human.
type Report struct {
	Time     time.Time `json:"time"`
	Room     string    `json:"room"`
	Reporter string    `json:"reporter"`
	Target   string    `json:"target"`
	Name     string    `json:"targetName"`
	Reason   string    `json:"reason"`
}

// Reasons a client may send; anything else becomes "other".
var validReasons = map[string]bool{"name": true, "cheating": true, "afk": true, "griefing": true, "other": true}

// ReportLog appends reports as JSON lines (GAME_PLAN §3.4: /data/reports.jsonl).
type ReportLog struct {
	mu   sync.Mutex
	path string
}

// NewReportLog writes to path (directories are created). An empty path discards reports.
func NewReportLog(path string) *ReportLog { return &ReportLog{path: path} }

// Add appends one report.
func (l *ReportLog) Add(r Report) error {
	if l == nil || l.path == "" {
		return nil
	}
	r.Reason = strings.ToLower(r.Reason)
	if !validReasons[r.Reason] {
		r.Reason = "other"
	}
	line, err := json.Marshal(r)
	if err != nil {
		return err
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	if err := os.MkdirAll(filepath.Dir(l.path), 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(l.path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.Write(append(line, '\n'))
	return err
}
