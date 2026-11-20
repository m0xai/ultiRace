// Package gamedata embeds the shared JSON game data (balance, vehicles, maps) that Go and
// Godot both read. This directory is the single source of truth; `make sync` copies it into
// godot/gamedata.
package gamedata

import (
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path"
	"sort"
	"strings"
)

//go:embed *.json *.txt maps/*.json
var FS embed.FS

// Balance holds every tunable number. Only cmd/balance tuning may change balance.json.
type Balance struct {
	Version  int          `json:"version"`
	TickRate int          `json:"tickRate"`
	Stats    StatsMapping `json:"stats"`
	Physics  Physics      `json:"physics"`
	Race     Race         `json:"race"`
	Track    TrackParams  `json:"track"`
	Rooms    Rooms        `json:"rooms"`
	Effects  Effects      `json:"effects"`
	Catchup  Catchup      `json:"catchup"`
	// VehicleTrim is a small per-vehicle top-speed adjustment (fraction, e.g. 0.02 = +2 %) set by
	// the balance tuner; stats define character, trims fine-tune fairness.
	VehicleTrim map[string]float64 `json:"vehicleTrim"`
	// Ults holds each ULT's numbers by ult id (vehicles.json "ult"), e.g. Ults["nitro"]["cooldownS"].
	Ults map[string]map[string]float64 `json:"ults"`
}

// Effects holds status-effect rules (GAME_PLAN §2.7).
type Effects struct {
	SpinoutSpeedFactor float64 `json:"spinoutSpeedFactor"`
	CCImmunityS        float64 `json:"ccImmunityS"`
	HardCCMinGapS      float64 `json:"hardCcMinGapS"`
	SlowCap            float64 `json:"slowCap"`
	BoostCap           float64 `json:"boostCap"`
	UltLockS           float64 `json:"ultLockS"`
	RampKnockD         float64 `json:"rampKnockD"`
}

// Catchup holds the subtle catch-up mechanics (GAME_PLAN §2.8).
type Catchup struct {
	RechargeFirst     float64 `json:"rechargeFirst"`
	RechargeLast      float64 `json:"rechargeLast"`
	DraftDistM        float64 `json:"draftDistM"`
	DraftLateralM     float64 `json:"draftLateralM"`
	DraftTimeS        float64 `json:"draftTimeS"`
	DraftBonus        float64 `json:"draftBonus"`
	ComebackGapM      float64 `json:"comebackGapM"`
	ComebackBonus     float64 `json:"comebackBonus"`
	StartBoostWindowS float64 `json:"startBoostWindowS"`
	StartBoostSpeed   float64 `json:"startBoostSpeed"`
	StartBoostAccel   float64 `json:"startBoostAccel"`
	StartBoostS       float64 `json:"startBoostS"`
}

// Ult returns one number of a ULT; it panics on a missing key (caught by gamedata tests).
func (b *Balance) Ult(id, key string) float64 {
	v, ok := b.Ults[id][key]
	if !ok {
		panic("balance.json: ults." + id + "." + key + " missing")
	}
	return v
}

// Rooms holds lobby/room timing rules (GAME_PLAN §2.3, §2.3.1, §3.6). Durations in seconds.
type Rooms struct {
	MaxCars               int     `json:"maxCars"`
	PublicLobbyS          float64 `json:"publicLobbyS"`
	PublicLobbySoloS      float64 `json:"publicLobbySoloS"`
	LateJoinMinS          float64 `json:"lateJoinMinS"`
	AllReadyS             float64 `json:"allReadyS"`
	PrivateAutoStartS     float64 `json:"privateAutoStartS"`
	SelectS               float64 `json:"selectS"`
	ResultsS              float64 `json:"resultsS"`
	AfkS                  float64 `json:"afkS"`
	AfkRacesToKick        int     `json:"afkRacesToKick"`
	ReconnectS            float64 `json:"reconnectS"`
	KickBanS              float64 `json:"kickBanS"`
	EmptyRoomS            float64 `json:"emptyRoomS"`
	SeatReservationS      float64 `json:"seatReservationS"`
	QuickPlaySpectateMaxS float64 `json:"quickPlaySpectateMaxS"`
	// SnapshotEveryNth: a snapshot is sent on every tick except each Nth (2 of 3 → 20 Hz).
	SnapshotEveryNth int `json:"snapshotEveryNth"`
	// MaxListedRooms caps GET /api/rooms (best rooms first) to keep it ≤ 30 KB (GAME_PLAN §8).
	MaxListedRooms int `json:"maxListedRooms"`
}

// Ticks converts seconds to whole ticks at the sim rate.
func (b *Balance) Ticks(seconds float64) int {
	return int(seconds*float64(b.TickRate) + 0.5)
}

// StatsMapping turns 1–5 vehicle stats into physical values (linear, GAME_PLAN §2.6).
type StatsMapping struct {
	TopSpeedBase                   float64 `json:"topSpeedBase"`
	TopSpeedPerStat                float64 `json:"topSpeedPerStat"`
	AccelTimeBase                  float64 `json:"accelTimeBase"`
	AccelTimePerStat               float64 `json:"accelTimePerStat"`
	SteerRateBase                  float64 `json:"steerRateBase"`
	SteerRatePerStat               float64 `json:"steerRatePerStat"`
	WallReflectBase                float64 `json:"wallReflectBase"`
	WallReflectPerStat             float64 `json:"wallReflectPerStat"`
	MassBase                       float64 `json:"massBase"`
	MassPerStat                    float64 `json:"massPerStat"`
	HardCCReductionPerWeightAbove3 float64 `json:"hardCCReductionPerWeightAbove3"`
}

// Physics holds the car physics constants (GAME_PLAN §2.5).
type Physics struct {
	CoastDecel              float64 `json:"coastDecel"`
	OverspeedDecel          float64 `json:"overspeedDecel"`
	SteerHighSpeedFalloff   float64 `json:"steerHighSpeedFalloff"`
	SteerRefSpeed           float64 `json:"steerRefSpeed"` // falloff is relative to this absolute speed
	AutoAlign               float64 `json:"autoAlign"`
	MaxYawRel               float64 `json:"maxYawRel"`
	AirSteerFactor          float64 `json:"airSteerFactor"`
	Gravity                 float64 `json:"gravity"`
	CarHalfWidth            float64 `json:"carHalfWidth"`
	WallSpeedFactor         float64 `json:"wallSpeedFactor"`
	WallMinYawOut           float64 `json:"wallMinYawOut"`
	MinCurvatureDenominator float64 `json:"minCurvatureDenominator"`
	LandingSpeedFactor      float64 `json:"landingSpeedFactor"`
	CarRadius               float64 `json:"carRadius"`
	CarCollisionMaxDy       float64 `json:"carCollisionMaxDy"`
	CollisionSpeedExchange  float64 `json:"collisionSpeedExchange"`
	CarHalfLength           float64 `json:"carHalfLength"`        // car footprint for car–car contact
	CollisionRestitution    float64 `json:"collisionRestitution"` // bounciness of rear-end hits (0–1)
	SideBounceYaw           float64 `json:"sideBounceYaw"`        // heading kick away on side contact (rad)
	SideScrub               float64 `json:"sideScrub"`            // speed lost on side contact (fraction)
}

// Race holds race-flow numbers.
type Race struct {
	DefaultLaps      int     `json:"defaultLaps"`
	CountdownS       float64 `json:"countdownS"`
	FinishWindowS    float64 `json:"finishWindowS"`
	GridRowSpacing   float64 `json:"gridRowSpacing"`
	GridColumnOffset float64 `json:"gridColumnOffset"`
	GridStartGap     float64 `json:"gridStartGap"`
}

// TrackParams controls track sampling (must match the GDScript mirror).
type TrackParams struct {
	ArcSamplesPerSegment int `json:"arcSamplesPerSegment"`
	FixtureSamples       int `json:"fixtureSamples"`
}

// Stats are a vehicle's 1–5 ratings; they sum to 12.
type Stats struct {
	Speed    int `json:"speed"`
	Accel    int `json:"accel"`
	Handling int `json:"handling"`
	Weight   int `json:"weight"`
}

// Vehicle is one of the 8 cars.
type Vehicle struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Color string `json:"color"`
	Ult   string `json:"ult"`
	Stats Stats  `json:"stats"`
}

// Ramp launches cars upward when they leave its end (GAME_PLAN §2.5 step 6).
type Ramp struct {
	S      float64 `json:"s"`      // start of the ramp along the centreline (m)
	Length float64 `json:"length"` // ramp length (m); launch happens at S+Length
	Vy     float64 `json:"vy"`     // launch vertical speed (m/s)
	Height float64 `json:"height"` // height of the ramp lip (m): cars drive up the wedge and leave it from there
}

// Map is one track file in maps/.
type Map struct {
	ID     string       `json:"id"`
	Name   string       `json:"name"`
	Theme  string       `json:"theme"`
	Points [][5]float64 `json:"points"` // [x, y, z, width, bank(rad)]
	Ramps  []Ramp       `json:"ramps"`
}

// LoadBalance parses balance.json.
func LoadBalance() (*Balance, error) {
	var b Balance
	if err := readJSON("balance.json", &b); err != nil {
		return nil, err
	}
	return &b, nil
}

// LoadBalanceFile parses a balance.json from disk (used by the balance tuner).
func LoadBalanceFile(path string) (*Balance, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var b Balance
	dec := json.NewDecoder(strings.NewReader(string(data)))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&b); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return &b, nil
}

// LoadVehicles parses vehicles.json.
func LoadVehicles() ([]Vehicle, error) {
	var v struct {
		Vehicles []Vehicle `json:"vehicles"`
	}
	if err := readJSON("vehicles.json", &v); err != nil {
		return nil, err
	}
	return v.Vehicles, nil
}

// LoadMap parses maps/<id>.json.
func LoadMap(id string) (*Map, error) {
	var m Map
	if err := readJSON(path.Join("maps", id+".json"), &m); err != nil {
		return nil, err
	}
	if m.ID != id {
		return nil, fmt.Errorf("gamedata: maps/%s.json has id %q", id, m.ID)
	}
	return &m, nil
}

// MapIDs lists the available maps, sorted.
func MapIDs() []string {
	entries, _ := fs.ReadDir(FS, "maps")
	ids := make([]string, 0, len(entries))
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".json") {
			ids = append(ids, strings.TrimSuffix(e.Name(), ".json"))
		}
	}
	sort.Strings(ids)
	return ids
}

func readJSON(name string, v any) error {
	data, err := FS.ReadFile(name)
	if err != nil {
		return fmt.Errorf("gamedata: %w", err)
	}
	dec := json.NewDecoder(strings.NewReader(string(data)))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return fmt.Errorf("gamedata: %s: %w", name, err)
	}
	return nil
}
