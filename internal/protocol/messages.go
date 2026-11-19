// Package protocol is the source of truth for all client↔server message shapes
// (GAME_PLAN §3.7). godot/src/net/Protocol.gd mirrors it; fixtures/protocol/*.json keep the
// mirror honest. Bump Version for incompatible changes.
package protocol

import (
	"encoding/json"
	"errors"
	"fmt"
)

// Version is the protocol version; hello.v must match exactly.
const Version = 1

// Region of this server (RoomSummary.region); more regions later without a protocol change.
const DefaultRegion = "eu"

// Message type tags (`t` field).
const (
	// client → server
	THello    = "hello"
	TReady    = "ready"
	TSettings = "settings"
	TStart    = "start"
	TKick     = "kick"
	TPreview  = "preview"
	TLock     = "lock"
	TIn       = "in"
	TRematch  = "rematch"
	TReport   = "report"
	TPing     = "ping"
	TLeave    = "leave"

	// server → client
	TWelcome   = "welcome"
	TRoom      = "room"
	TSelect    = "select"
	TRaceStart = "raceStart"
	TEv        = "ev"
	TResults   = "results"
	TKicked    = "kicked"
	TPong      = "pong"
	TErr       = "err"
)

// Visibility of a room.
const (
	Public  = "public"
	Private = "private"
)

// Error codes in err{code}.
const (
	ErrVersion     = "version"
	ErrBadMessage  = "bad_message"
	ErrRoomFull    = "room_full"
	ErrNoRoom      = "no_room"
	ErrNotHost     = "not_host"
	ErrWrongState  = "wrong_state"
	ErrTaken       = "taken"
	ErrBanned      = "banned"
	ErrRateLimited = "rate_limited"
	ErrServer      = "server"
)

// Envelope reads only the type tag.
type Envelope struct {
	T string `json:"t"`
}

// ---------- client → server ----------

// Hello is the first message on a connection.
type Hello struct {
	T        string      `json:"t"`
	V        int         `json:"v"`
	Name     string      `json:"name"`
	Token    string      `json:"token,omitempty"`    // reconnect / session token
	Room     string      `json:"room,omitempty"`     // join by code
	Quick    bool        `json:"quick,omitempty"`    // Quick Play matchmaking
	Practice bool        `json:"practice,omitempty"` // private room with 7 bots
	Create   *CreateOpts `json:"create,omitempty"`
	Blocked  []string    `json:"blocked,omitempty"` // anonymous player IDs to avoid
	Auth     *Auth       `json:"auth,omitempty"`
}

// CreateOpts asks for a new room.
type CreateOpts struct {
	Visibility string `json:"visibility"`
}

// Auth names the identity provider (verification itself is an HTTP call, M10).
type Auth struct {
	Provider string `json:"provider"` // "gamecenter" | "guest"
}

// Ready toggles the player's ready flag in the lobby.
type Ready struct {
	T     string `json:"t"`
	Ready bool   `json:"ready"`
}

// Settings changes room settings (host only, LOBBY only).
type Settings struct {
	T          string `json:"t"`
	Map        string `json:"map"`
	Laps       int    `json:"laps"`
	Bots       bool   `json:"bots"`
	Visibility string `json:"visibility"`
}

// Start asks to start the race (host only).
type Start struct {
	T string `json:"t"`
}

// Kick removes a player (host only).
type Kick struct {
	T        string `json:"t"`
	PlayerID string `json:"playerId"`
}

// Preview shows which card the player is looking at during vehicle select.
type Preview struct {
	T       string `json:"t"`
	Vehicle string `json:"vehicle"`
}

// Lock claims a vehicle (first lock wins).
type Lock struct {
	T       string `json:"t"`
	Vehicle string `json:"vehicle"`
}

// In is one tick of input.
type In struct {
	T     string `json:"t"`
	Seq   uint32 `json:"seq"`
	Steer int    `json:"steer"` // -1, 0, 1
	Thr   int    `json:"thr"`   // 0, 1
	Ab    bool   `json:"ab"`
}

// Rematch asks to go back to the lobby after results.
type Rematch struct {
	T string `json:"t"`
}

// Report flags a player for review.
type Report struct {
	T        string `json:"t"`
	PlayerID string `json:"playerId"`
	Reason   string `json:"reason"`
}

// Ping measures round-trip time.
type Ping struct {
	T  string `json:"t"`
	Ts int64  `json:"ts"`
}

// Leave leaves the room cleanly.
type Leave struct {
	T string `json:"t"`
}

// ---------- server → client ----------

// Welcome confirms the session.
type Welcome struct {
	T        string `json:"t"`
	PlayerID string `json:"playerId"`
	Token    string `json:"token"`
	Room     string `json:"room"`
}

// PlayerInfo is one row of the lobby list.
type PlayerInfo struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Bot     bool   `json:"bot"`
	Ready   bool   `json:"ready"`
	Host    bool   `json:"host"`
	PingMs  int    `json:"pingMs"`
	Vehicle string `json:"vehicle,omitempty"`
	Spec    bool   `json:"spec,omitempty"` // spectating until the next lobby
}

// RoomState is the full room view sent on every change.
type RoomState struct {
	T          string       `json:"t"`
	Code       string       `json:"code"`
	Name       string       `json:"name"`
	State      string       `json:"state"` // LOBBY, SELECT, COUNTDOWN, RACING, RESULTS
	Visibility string       `json:"visibility"`
	Map        string       `json:"map"`
	Laps       int          `json:"laps"`
	Bots       bool         `json:"bots"`
	Players    []PlayerInfo `json:"players"`
	Deadline   int64        `json:"deadline"` // unix ms when the current timer ends (0 = none)
	Region     string       `json:"region"`
}

// Claim is a locked vehicle.
type Claim struct {
	Vehicle  string `json:"vehicle"`
	PlayerID string `json:"playerId"`
}

// Select is the vehicle-select state.
type Select struct {
	T        string            `json:"t"`
	Claims   []Claim           `json:"claims"`
	Previews map[string]string `json:"previews"` // playerId → vehicle being looked at
	Deadline int64             `json:"deadline"`
}

// GridSlot is one car on the starting grid.
type GridSlot struct {
	Car      int    `json:"car"` // car index used in snapshots
	PlayerID string `json:"playerId"`
	Vehicle  string `json:"vehicle"`
	Name     string `json:"name"`
	Bot      bool   `json:"bot"`
}

// RaceStart begins the countdown.
type RaceStart struct {
	T       string     `json:"t"`
	Seed    uint32     `json:"seed"`
	Map     string     `json:"map"`
	Laps    int        `json:"laps"`
	Grid    []GridSlot `json:"grid"`
	StartAt int64      `json:"startAt"` // unix ms of GO
	Tick    int        `json:"tick"`    // server tick at which the race starts (GO)
	You     int        `json:"you"`     // your car index, -1 if spectating
}

// Ev is a game event.
type Ev struct {
	T     string  `json:"t"`
	Kind  string  `json:"kind"` // wallHit, lap, finished, bump, launch, land, state
	Tick  int     `json:"tick"`
	Car   int     `json:"car"`
	Other int     `json:"other,omitempty"`
	Value float64 `json:"value,omitempty"`
	State string  `json:"state,omitempty"`
}

// ResultRow is one line of the results table.
type ResultRow struct {
	Pos      int    `json:"pos"`
	Car      int    `json:"car"`
	PlayerID string `json:"playerId"`
	Name     string `json:"name"`
	Vehicle  string `json:"vehicle"`
	Bot      bool   `json:"bot"`
	Finished bool   `json:"finished"`
	TimeMs   int64  `json:"timeMs"`    // race time, 0 if not finished
	BestLap  int64  `json:"bestLapMs"` // 0 if no lap completed
}

// Verified holds server-confirmed values the client may submit to Game Center.
type Verified struct {
	PlayerID string `json:"playerId"`
	BestLap  int64  `json:"bestLapMs"`
	TimeMs   int64  `json:"timeMs"`
	Won      bool   `json:"won"`
}

// Results ends the race.
type Results struct {
	T        string      `json:"t"`
	Rows     []ResultRow `json:"rows"`
	Verified []Verified  `json:"verified"`
}

// Kicked tells a client it was removed.
type Kicked struct {
	T      string `json:"t"`
	Reason string `json:"reason"`
}

// Pong answers Ping.
type Pong struct {
	T  string `json:"t"`
	Ts int64  `json:"ts"`
}

// Err reports an error.
type Err struct {
	T    string `json:"t"`
	Code string `json:"code"`
	Msg  string `json:"msg"`
}

// RoomSummary is one row of the public room listing (GET /api/rooms).
type RoomSummary struct {
	Code       string `json:"code"`
	Name       string `json:"name"`
	Host       string `json:"host"`
	Map        string `json:"map"`
	Laps       int    `json:"laps"`
	Humans     int    `json:"humans"`
	Bots       int    `json:"bots"`
	MaxCars    int    `json:"maxCars"`
	State      string `json:"state"`
	Deadline   int64  `json:"deadline"`
	Visibility string `json:"visibility"`
	Region     string `json:"region"`
	CreatedAt  int64  `json:"createdAt"`
}

// RoomList is the body of GET /api/rooms.
type RoomList struct {
	Online int           `json:"online"`
	Rooms  []RoomSummary `json:"rooms"`
}

// Stats is the body of GET /api/stats.
type Stats struct {
	Online int `json:"online"`
	Racing int `json:"racing"`
}

// ---------- decoding ----------

// MaxMessageBytes bounds inbound JSON messages.
const MaxMessageBytes = 2048

var ErrUnknownType = errors.New("unknown message type")

// DecodeClient parses a client message into its concrete type (pointer).
func DecodeClient(data []byte) (any, error) {
	if len(data) > MaxMessageBytes {
		return nil, fmt.Errorf("message too large: %d bytes", len(data))
	}
	var env Envelope
	if err := json.Unmarshal(data, &env); err != nil {
		return nil, err
	}
	var v any
	switch env.T {
	case THello:
		v = &Hello{}
	case TReady:
		v = &Ready{}
	case TSettings:
		v = &Settings{}
	case TStart:
		v = &Start{}
	case TKick:
		v = &Kick{}
	case TPreview:
		v = &Preview{}
	case TLock:
		v = &Lock{}
	case TIn:
		v = &In{}
	case TRematch:
		v = &Rematch{}
	case TReport:
		v = &Report{}
	case TPing:
		v = &Ping{}
	case TLeave:
		v = &Leave{}
	default:
		return nil, fmt.Errorf("%w: %q", ErrUnknownType, env.T)
	}
	if err := json.Unmarshal(data, v); err != nil {
		return nil, err
	}
	if in, ok := v.(*In); ok {
		if in.Steer < -1 || in.Steer > 1 || in.Thr < 0 || in.Thr > 1 {
			return nil, fmt.Errorf("in: steer/thr out of range")
		}
	}
	return v, nil
}

// Encode marshals any server message (they all carry their own T).
func Encode(v any) []byte {
	b, err := json.Marshal(v)
	if err != nil {
		panic(fmt.Sprintf("protocol: encode %T: %v", v, err)) // programmer error: all types are plain data
	}
	return b
}
