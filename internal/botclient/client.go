// Package botclient is a headless game client over the real WebSocket protocol, used for
// end-to-end tests and load/soak runs (cmd/botclient). It drives its own car from decoded
// snapshots with the same bot brain the server uses for empty seats.
package botclient

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"

	"github.com/m0xai/ultiRace/internal/bots"
	"github.com/m0xai/ultiRace/internal/protocol"
	"github.com/m0xai/ultiRace/internal/room"
	"github.com/m0xai/ultiRace/internal/sim"
	"github.com/m0xai/ultiRace/internal/track"
)

// Options configure one client.
type Options struct {
	URL      string // base URL, e.g. ws://127.0.0.1:8090
	Name     string
	Quick    bool
	Room     string
	Practice bool
	Races    int // stop after this many results (0 = 1)
	HostLaps int // if host, set laps (2 or 3) in the lobby; 0 = leave
	Data     *room.Data
}

// Result is what a client saw.
type Result struct {
	PlayerID  string
	Room      string
	Races     int
	Positions []int // our finishing position per race
	Finished  []bool
	Snapshots int
	Errors    []string
	Inputs    int
}

// Run connects, plays Races races and returns.
func Run(ctx context.Context, o Options) (*Result, error) {
	if o.Races == 0 {
		o.Races = 1
	}
	ws, _, err := websocket.Dial(ctx, strings.TrimRight(o.URL, "/")+"/ws", nil)
	if err != nil {
		return nil, err
	}
	defer ws.CloseNow()
	ws.SetReadLimit(1 << 20)
	c := &client{o: o, ws: ws, res: &Result{}, me: -1}
	hello := protocol.Hello{T: protocol.THello, V: protocol.Version, Name: o.Name, Quick: o.Quick, Room: o.Room, Practice: o.Practice,
		Auth: &protocol.Auth{Provider: "guest"}}
	if err := c.write(ctx, hello); err != nil {
		return nil, err
	}
	err = c.loop(ctx)
	return c.res, err
}

type client struct {
	o   Options
	ws  *websocket.Conn
	wmu sync.Mutex
	res *Result

	isHost   bool
	setLaps  bool
	ready    bool
	locked   bool
	me       int
	tr       *track.Track
	ctrl     *bots.Controller
	seq      uint32
	cars     []sim.CarState
	vehicles []string
}

func (c *client) write(ctx context.Context, v any) error {
	c.wmu.Lock()
	defer c.wmu.Unlock()
	wctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	return c.ws.Write(wctx, websocket.MessageText, protocol.Encode(v))
}

func (c *client) loop(ctx context.Context) error {
	for {
		typ, data, err := c.ws.Read(ctx)
		if err != nil {
			return err
		}
		if typ == websocket.MessageBinary {
			if err := c.onSnapshot(ctx, data); err != nil {
				return err
			}
			continue
		}
		var env protocol.Envelope
		if err := json.Unmarshal(data, &env); err != nil {
			return err
		}
		done, err := c.onJSON(ctx, env.T, data)
		if err != nil || done {
			return err
		}
	}
}

func (c *client) onJSON(ctx context.Context, t string, data []byte) (bool, error) {
	switch t {
	case protocol.TWelcome:
		var m protocol.Welcome
		_ = json.Unmarshal(data, &m)
		c.res.PlayerID, c.res.Room = m.PlayerID, m.Room
	case protocol.TRoom:
		var m protocol.RoomState
		_ = json.Unmarshal(data, &m)
		for _, p := range m.Players {
			if p.ID == c.res.PlayerID {
				c.isHost = p.Host
				c.ready = p.Ready
			}
		}
		if m.State == string(room.Lobby) {
			c.locked = false
			if c.isHost && c.o.HostLaps != 0 && !c.setLaps {
				c.setLaps = true
				if err := c.write(ctx, protocol.Settings{T: protocol.TSettings, Map: m.Map, Laps: c.o.HostLaps, Bots: true, Visibility: m.Visibility}); err != nil {
					return false, err
				}
			}
			if !c.ready {
				c.ready = true
				if err := c.write(ctx, protocol.Ready{T: protocol.TReady, Ready: true}); err != nil {
					return false, err
				}
				if c.isHost && m.Visibility == protocol.Private {
					return false, c.write(ctx, protocol.Start{T: protocol.TStart})
				}
			}
		}
	case protocol.TSelect:
		var m protocol.Select
		_ = json.Unmarshal(data, &m)
		return false, c.lockFree(ctx, m)
	case protocol.TRaceStart:
		var m protocol.RaceStart
		_ = json.Unmarshal(data, &m)
		c.me = m.You
		c.tr = c.o.Data.Tracks[m.Map]
		c.ctrl = bots.NewController(c.o.Data.Lines[m.Map], bots.Normal, m.Seed+uint32(m.You)+99)
		c.cars = make([]sim.CarState, len(m.Grid))
	case protocol.TResults:
		var m protocol.Results
		_ = json.Unmarshal(data, &m)
		for _, r := range m.Rows {
			if r.PlayerID == c.res.PlayerID {
				c.res.Positions = append(c.res.Positions, r.Pos)
				c.res.Finished = append(c.res.Finished, r.Finished)
			}
		}
		c.res.Races++
		c.me = -1
		if c.res.Races >= c.o.Races {
			_ = c.write(ctx, protocol.Leave{T: protocol.TLeave})
			return true, nil
		}
		return false, c.write(ctx, protocol.Rematch{T: protocol.TRematch})
	case protocol.TErr:
		var m protocol.Err
		_ = json.Unmarshal(data, &m)
		c.res.Errors = append(c.res.Errors, m.Code)
		if m.Code == protocol.ErrTaken {
			c.locked = false
		}
		if m.Code == protocol.ErrVersion || m.Code == protocol.ErrNoRoom || m.Code == protocol.ErrBanned {
			return true, fmt.Errorf("server error %s: %s", m.Code, m.Msg)
		}
	case protocol.TKicked:
		return true, fmt.Errorf("kicked")
	}
	return false, nil
}

func (c *client) lockFree(ctx context.Context, m protocol.Select) error {
	taken := map[string]bool{}
	for _, cl := range m.Claims {
		taken[cl.Vehicle] = true
		if cl.PlayerID == c.res.PlayerID {
			c.locked = true
		}
	}
	if c.locked {
		return nil
	}
	// spread choices: start at a name-dependent offset so clients rarely collide
	vs := c.o.Data.Vehicles
	off := len(c.o.Name) + int(c.o.Name[len(c.o.Name)-1])
	for i := range vs {
		v := vs[(i+off)%len(vs)]
		if !taken[v.ID] {
			c.locked = true
			return c.write(ctx, protocol.Lock{T: protocol.TLock, Vehicle: v.ID})
		}
	}
	return nil
}

func (c *client) onSnapshot(ctx context.Context, data []byte) error {
	s, err := protocol.DecodeSnapshot(data)
	if err != nil {
		return err
	}
	c.res.Snapshots++
	if c.me < 0 || c.tr == nil {
		return nil
	}
	for _, car := range s.Cars {
		if int(car.ID) < len(c.cars) {
			c.cars[car.ID] = sim.CarState{S: car.S, D: car.D, YawRel: car.YawRel, Y: car.Y, Vy: car.Vy, Speed: car.Speed, Lap: int(car.Lap)}
		}
	}
	others := make([]*sim.CarState, 0, len(c.cars))
	for i := range c.cars {
		if i != c.me {
			others = append(others, &c.cars[i])
		}
	}
	in := c.ctrl.Decide(&c.cars[c.me], others, c.tr)
	c.seq++
	c.res.Inputs++
	return c.write(ctx, protocol.In{T: protocol.TIn, Seq: c.seq, Steer: in.Steer, Thr: in.Throttle})
}
