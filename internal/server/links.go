package server

import (
	"encoding/json"
	"html/template"
	"net/http"
	"regexp"
	"strings"
)

// Universal Links (GAME_PLAN §3.4, §6.2): the AASA file and the /r/{code} landing page.

var codeRe = regexp.MustCompile(`^[A-HJ-KM-NP-Z]{4}$`)

// GET /.well-known/apple-app-site-association — 200, application/json, no redirect.
func (s *Server) handleAASA(w http.ResponseWriter, _ *http.Request) {
	if s.cfg.TeamID == "" || s.cfg.BundleID == "" {
		http.NotFound(w, nil)
		return
	}
	body := map[string]any{
		"applinks": map[string]any{
			"details": []any{map[string]any{
				"appIDs":     []string{s.cfg.TeamID + "." + s.cfg.BundleID},
				"components": []any{map[string]string{"/": "/r/*", "comment": "room links"}},
			}},
		},
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(body)
}

var landing = template.Must(template.New("landing").Parse(`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Join room {{.Code}} · UltiRace</title>
<style>body{margin:0;font-family:-apple-system,system-ui,sans-serif;background:#12141c;color:#f2f4f8;
display:flex;min-height:100vh;align-items:center;justify-content:center;text-align:center}
.card{padding:32px 24px;max-width:420px}h1{color:#ffcc1a;font-size:44px;margin:0 0 8px}
.code{font-size:56px;letter-spacing:.15em;font-weight:800;margin:16px 0}
a.btn{display:inline-block;margin-top:20px;padding:16px 28px;border-radius:16px;background:#ffcc1a;color:#111;
font-weight:700;text-decoration:none;font-size:20px}p{color:#9aa3b5}</style></head>
<body><div class="card"><h1>UltiRace</h1><p>You're invited to a race. Room code:</p>
<div class="code">{{.Code}}</div>
<p>Open this link on an iPhone with UltiRace installed to join, or enter the code in the app.</p>
{{if .StoreURL}}<a class="btn" href="{{.StoreURL}}">Get UltiRace</a>{{end}}
</div></body></html>`))

// GET /r/{code} — shown when the app is not installed (Universal Links open the app otherwise).
func (s *Server) handleRoomLink(w http.ResponseWriter, r *http.Request) {
	code := strings.ToUpper(r.PathValue("code"))
	if !codeRe.MatchString(code) {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	_ = landing.Execute(w, map[string]string{"Code": code, "StoreURL": s.cfg.StoreURL})
}
