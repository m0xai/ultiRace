// Package gamedata embeds the shared JSON game data (balance, vehicles, maps) that Go and
// Godot both read. This directory is the single source of truth; `make sync` copies it into
// godot/gamedata.
package gamedata

import (
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"path"
	"sort"
	"strings"
)

//go:embed *.json maps/*.json
var FS embed.FS

// Balance holds every tunable number. Only cmd/balance tuning may change balance.json.
type Balance struct {
	Version  int          `json:"version"`
	TickRate int          `json:"tickRate"`
	Stats    StatsMapping `json:"stats"`
	Physics  Physics      `json:"physics"`
	Race     Race         `json:"race"`
	Track    TrackParams  `json:"track"`
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
