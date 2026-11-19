// Package room runs one race room: lobby → vehicle select → countdown → race → results
// (GAME_PLAN §2.3, §3.4, §3.6). Core is a pure, tick-driven state machine (no goroutines,
// no wall clock), so tests drive it directly; Room (room.go) runs it on its own goroutine.
package room

import (
	"fmt"
	"sort"
	"time"

	"github.com/m0xai/ultiRace/gamedata"
	"github.com/m0xai/ultiRace/internal/bots"
	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/moderation"
	"github.com/m0xai/ultiRace/internal/protocol"
	"github.com/m0xai/ultiRace/internal/sim"
	"github.com/m0xai/ultiRace/internal/track"
)

// State of a room.
type State string

const (
	Lobby     State = "LOBBY"
	Select    State = "SELECT"
	Countdown State = "COUNTDOWN"
	Racing    State = "RACING"
	Results   State = "RESULTS"
)

// Data is the shared, read-only game data every room uses.
type Data struct {
	Bal      *gamedata.Balance
	Vehicles []gamedata.Vehicle
	Tracks   map[string]*track.Track
	Lines    map[string]*bots.RacingLine
	MapIDs   []string
}

// LoadData loads balance, vehicles and all tracks from embedded gamedata.
func LoadData() (*Data, error) {
	bal, err := gamedata.LoadBalance()
	if err != nil {
		return nil, err
	}
	veh, err := gamedata.LoadVehicles()
	if err != nil {
		return nil, err
	}
	d := &Data{Bal: bal, Vehicles: veh, Tracks: map[string]*track.Track{}, Lines: map[string]*bots.RacingLine{}, MapIDs: gamedata.MapIDs()}
	for _, id := range d.MapIDs {
		tr, err := track.Load(id, bal.Track.ArcSamplesPerSegment)
		if err != nil {
			return nil, err
		}
		d.Tracks[id] = tr
		d.Lines[id] = bots.NewRacingLine(tr)
	}
	return d, nil
}

func (d *Data) vehicle(id string) (gamedata.Vehicle, bool) {
	for _, v := range d.Vehicles {
		if v.ID == id {
			return v, true
		}
	}
	return gamedata.Vehicle{}, false
}

// Sender delivers one encoded message to a client. It must not block.
type Sender func([]byte)

// Player is a human (connected or not) or a bot in this room.
type Player struct {
	ID    string
	Name  string
	Token string
	Bot   bool

	send           Sender
	ready          bool
	spec           bool // spectating until the next lobby
	vehicle        string
	car            int // index in the world, -1 if not racing
	blocked        map[string]bool
	input          sim.Input
	ack            uint32
	lastInputTick  int
	afk            bool
	wasAfk         bool
	afkRaces       int
	disconnectedAt int // tick, -1 when connected
	left           bool
	ctrl           *bots.Controller
	pingMs         int
}

func (p *Player) connected() bool { return p.send != nil && !p.left }

// Options configure a new room.
type Options struct {
	Code       string
	Visibility string
	Practice   bool
	Seed       uint32
	Now        func() time.Time // wall clock for deadline timestamps (unix ms)
	TickDur    time.Duration    // real duration of one tick (1/30 s, shorter with timeScale)
	Reports    *moderation.ReportLog
}

// Core is the room state machine. Not safe for concurrent use.
type Core struct {
	data *Data
	opt  Options
	cfg  gamedata.Rooms

	Code       string
	Name       string
	Visibility string
	Map        string
	Laps       int
	BotsOn     bool
	Practice   bool
	State      State
	CreatedAt  time.Time

	tick     int
	deadline int // tick at which the current phase timer fires (0 = none)
	players  []*Player
	hostID   string
	claims   map[string]string // vehicle → player id
	previews map[string]string // player id → vehicle
	world    *sim.World
	grid     []*Player // car index → player (humans and bots)
	goTick   int
	lastRank []string // player ids in last race's finishing order
	kicked   map[string]int
	rng      *mathx.Rng
	tag      string

	roomDirty   bool
	selectDirty bool
	summaryVer  int
	emptySince  int
}

// NewCore creates a room in LOBBY.
func NewCore(data *Data, opt Options) *Core {
	if opt.Now == nil {
		opt.Now = time.Now
	}
	if opt.TickDur == 0 {
		opt.TickDur = time.Second / time.Duration(data.Bal.TickRate)
	}
	if opt.Visibility != protocol.Private {
		opt.Visibility = protocol.Public
	}
	c := &Core{
		data: data, opt: opt, cfg: data.Bal.Rooms,
		Code: opt.Code, Visibility: opt.Visibility, Practice: opt.Practice,
		Laps: data.Bal.Race.DefaultLaps, BotsOn: true, State: Lobby,
		CreatedAt: opt.Now(), claims: map[string]string{}, previews: map[string]string{},
		kicked: map[string]int{}, rng: mathx.NewRng(opt.Seed), emptySince: 0,
	}
	if opt.Practice {
		c.Visibility = protocol.Private
	}
	c.Map = data.MapIDs[c.rng.Intn(len(data.MapIDs))]
	c.tag = roomTags[c.rng.Intn(len(roomTags))]
	c.rename()
	c.roomDirty = true
	return c
}

// Fixed word list for generated room names (no free text, D10).
var roomTags = []string{"Turbo", "Slippery", "Zoomy", "Wild", "Chill", "Spicy", "Bumpy", "Lucky", "Nitro", "Sunny", "Frosty", "Neon"}

func (c *Core) rename() {
	mapName := c.Map
	if m, err := gamedata.LoadMap(c.Map); err == nil {
		mapName = m.Name
	}
	c.Name = fmt.Sprintf("%s · %d laps · #%s %s", mapName, c.Laps, c.Code, c.tag)
}

func (c *Core) ticks(s float64) int { return c.data.Bal.Ticks(s) }

// Tick returns the current tick (for tests and the room loop).
func (c *Core) Tick() int { return c.tick }

// ---------- membership ----------

func (c *Core) seatedHumans() []*Player {
	var out []*Player
	for _, p := range c.players {
		if !p.spec && !p.left {
			out = append(out, p)
		}
	}
	return out
}

func (c *Core) connectedHumans() int {
	n := 0
	for _, p := range c.players {
		if p.connected() {
			n++
		}
	}
	return n
}

func (c *Core) find(id string) *Player {
	for _, p := range c.players {
		if p.ID == id && !p.left {
			return p
		}
	}
	return nil
}

// HasPlayer reports whether a human with this id is in the room (for Quick Play blocks).
func (c *Core) HasPlayer(id string) bool { return c.find(id) != nil }

// PlayerIDs lists the humans in the room.
func (c *Core) PlayerIDs() []string {
	var ids []string
	for _, p := range c.players {
		if !p.left {
			ids = append(ids, p.ID)
		}
	}
	return ids
}

// FreeSeats is how many more humans can race in the next race.
func (c *Core) FreeSeats() int { return c.cfg.MaxCars - len(c.seatedHumans()) }

// JoinResult tells the caller what happened.
type JoinResult struct {
	Err       string // protocol error code, "" on success
	Spectator bool
}

// Join adds a connected human. Humans replace bots in LOBBY; outside LOBBY or when all 8
// seats are taken they spectate until the next lobby.
func (c *Core) Join(id, name, token string, blocked []string, send Sender) JoinResult {
	if until, ok := c.kicked[id]; ok && c.tick < until {
		return JoinResult{Err: protocol.ErrBanned}
	}
	if p := c.find(id); p != nil { // same player again: treat as reconnect
		c.attach(p, send)
		return JoinResult{Spectator: p.spec}
	}
	p := &Player{ID: id, Name: name, Token: token, send: send, car: -1, disconnectedAt: -1, lastInputTick: c.tick, blocked: map[string]bool{}}
	for _, b := range blocked {
		p.blocked[b] = true
	}
	p.spec = c.State != Lobby || c.FreeSeats() <= 0
	c.players = append(c.players, p)
	if c.hostID == "" || c.find(c.hostID) == nil {
		c.hostID = id
	}
	// late joiner in the last seconds of a public lobby resets the timer to ≥ lateJoinMin
	if c.State == Lobby && c.Visibility == protocol.Public && c.deadline > 0 && c.deadline-c.tick < c.ticks(c.cfg.LateJoinMinS) {
		c.deadline = c.tick + c.ticks(c.cfg.LateJoinMinS)
	}
	c.roomDirty = true
	c.catchUp(p)
	return JoinResult{Spectator: p.spec}
}

// Reconnect re-attaches a disconnected player by token within the reconnect window.
func (c *Core) Reconnect(token string, send Sender) (*Player, bool) {
	for _, p := range c.players {
		if p.Token == token && token != "" && !p.left {
			if p.disconnectedAt >= 0 && c.tick-p.disconnectedAt > c.ticks(c.cfg.ReconnectS) {
				return nil, false
			}
			c.attach(p, send)
			return p, true
		}
	}
	return nil, false
}

func (c *Core) attach(p *Player, send Sender) {
	p.send = send
	p.disconnectedAt = -1
	p.lastInputTick = c.tick
	p.afk = false
	c.roomDirty = true
	c.catchUp(p)
}

// catchUp sends the current phase to a player who just (re)joined.
func (c *Core) catchUp(p *Player) {
	switch c.State {
	case Select:
		c.selectDirty = true
	case Countdown, Racing:
		c.sendTo(p, c.raceStartFor(p))
	}
}

// Disconnect marks a connection as gone. Racing players are driven by a bot and may
// reconnect; elsewhere the player leaves.
func (c *Core) Disconnect(id string) {
	p := c.find(id)
	if p == nil {
		return
	}
	p.send = nil
	if (c.State == Countdown || c.State == Racing) && p.car >= 0 {
		p.disconnectedAt = c.tick
		c.roomDirty = true
		return
	}
	c.remove(p)
}

// Leave removes a player now (their car, if racing, is driven by a bot).
func (c *Core) Leave(id string) {
	if p := c.find(id); p != nil {
		c.remove(p)
	}
}

func (c *Core) remove(p *Player) {
	p.left = true
	p.send = nil
	if v, ok := c.claimOf(p.ID); ok {
		delete(c.claims, v)
		c.selectDirty = true
	}
	delete(c.previews, p.ID)
	kept := c.players[:0]
	for _, q := range c.players {
		if q != p {
			kept = append(kept, q)
		}
	}
	c.players = kept
	if c.hostID == p.ID {
		c.hostID = ""
		for _, q := range c.players { // next human in join order, prefer seated
			if !q.spec {
				c.hostID = q.ID
				break
			}
		}
		if c.hostID == "" && len(c.players) > 0 {
			c.hostID = c.players[0].ID
		}
	}
	c.roomDirty = true
}

// Empty reports whether no human is connected.
func (c *Core) Empty() bool { return c.connectedHumans() == 0 }

// ShouldClose reports whether the room has been empty long enough to be destroyed.
func (c *Core) ShouldClose() bool {
	return c.Empty() && c.tick-c.emptySince >= c.ticks(c.cfg.EmptyRoomS)
}

// ---------- messages ----------

// Handle processes one decoded client message from player id.
func (c *Core) Handle(id string, msg any) {
	p := c.find(id)
	if p == nil {
		return
	}
	isHost := id == c.hostID
	switch m := msg.(type) {
	case *protocol.Ready:
		if c.State == Lobby && !p.spec {
			p.ready = m.Ready
			c.roomDirty = true
		}
	case *protocol.Settings:
		if !isHost {
			c.errTo(p, protocol.ErrNotHost, "only the host can change settings")
			return
		}
		if c.State != Lobby {
			c.errTo(p, protocol.ErrWrongState, "settings only in the lobby")
			return
		}
		if _, ok := c.data.Tracks[m.Map]; !ok || (m.Laps != 2 && m.Laps != 3) ||
			(m.Visibility != protocol.Public && m.Visibility != protocol.Private) {
			c.errTo(p, protocol.ErrBadMessage, "invalid settings")
			return
		}
		c.Map, c.Laps, c.BotsOn = m.Map, m.Laps, m.Bots
		if !c.Practice {
			c.Visibility = m.Visibility
		}
		c.rename()
		c.roomDirty = true
	case *protocol.Start:
		if !isHost {
			c.errTo(p, protocol.ErrNotHost, "only the host can start")
			return
		}
		if c.State != Lobby || !c.othersReady(p) {
			c.errTo(p, protocol.ErrWrongState, "everyone must be ready")
			return
		}
		c.startSelect()
	case *protocol.Kick:
		if !isHost || m.PlayerID == id {
			c.errTo(p, protocol.ErrNotHost, "only the host can kick")
			return
		}
		if t := c.find(m.PlayerID); t != nil {
			c.sendTo(t, protocol.Kicked{T: protocol.TKicked, Reason: "host"})
			c.kicked[t.ID] = c.tick + c.ticks(c.cfg.KickBanS)
			c.remove(t)
		}
	case *protocol.Preview:
		if c.State == Select {
			if _, ok := c.data.vehicle(m.Vehicle); ok {
				c.previews[id] = m.Vehicle
				c.selectDirty = true
			}
		}
	case *protocol.Lock:
		c.lock(p, m.Vehicle)
	case *protocol.In:
		if m.Seq > p.ack || p.ack == 0 {
			in := sim.Input{Steer: m.Steer, Throttle: m.Thr, Ability: m.Ab}
			if in != p.input {
				p.lastInputTick = c.tick
				p.afk = false
			}
			p.input = in
			p.ack = m.Seq
		}
	case *protocol.Rematch:
		if c.State == Results {
			p.ready = true
		}
	case *protocol.Report:
		if t := c.find(m.PlayerID); t != nil && t != p && c.opt.Reports != nil {
			_ = c.opt.Reports.Add(moderation.Report{Time: c.opt.Now(), Room: c.Code, Reporter: p.ID, Target: t.ID, Name: t.Name, Reason: m.Reason})
		}
	case *protocol.Ping:
		c.sendTo(p, protocol.Pong{T: protocol.TPong, Ts: m.Ts})
	case *protocol.Leave:
		c.remove(p)
	}
}

// SetPing records a measured round-trip time for the lobby list.
func (c *Core) SetPing(id string, ms int) {
	if p := c.find(id); p != nil && p.pingMs != ms {
		p.pingMs = ms
		c.roomDirty = true
	}
}

func (c *Core) othersReady(host *Player) bool {
	for _, q := range c.seatedHumans() {
		if q != host && !q.ready && q.connected() {
			return false
		}
	}
	return true
}

func (c *Core) allReady() bool {
	hs := c.seatedHumans()
	if len(hs) == 0 {
		return false
	}
	for _, q := range hs {
		if !q.ready && q.connected() {
			return false
		}
	}
	return true
}

func (c *Core) claimOf(id string) (string, bool) {
	for v, pid := range c.claims {
		if pid == id {
			return v, true
		}
	}
	return "", false
}

// lock implements "first lock wins": the server decides ties by message arrival order,
// which is the order Handle is called in.
func (c *Core) lock(p *Player, vehicle string) {
	if c.State != Select || p.spec {
		c.errTo(p, protocol.ErrWrongState, "not selecting")
		return
	}
	if _, ok := c.data.vehicle(vehicle); !ok {
		c.errTo(p, protocol.ErrBadMessage, "unknown vehicle")
		return
	}
	if _, already := c.claimOf(p.ID); already {
		return
	}
	if owner, taken := c.claims[vehicle]; taken && owner != p.ID {
		c.errTo(p, protocol.ErrTaken, "vehicle already taken")
		return
	}
	c.claims[vehicle] = p.ID
	p.vehicle = vehicle
	c.selectDirty = true
}

// ---------- tick ----------

// Step advances the room by one tick.
func (c *Core) Step() {
	c.tick++
	switch c.State {
	case Lobby:
		c.tickLobby()
	case Select:
		c.tickSelect()
	case Countdown, Racing:
		c.tickRace()
	case Results:
		if c.tick >= c.deadline {
			c.toLobby()
		}
	}
	if c.connectedHumans() > 0 {
		c.emptySince = c.tick
	}
	c.flush()
}

func (c *Core) tickLobby() {
	hs := c.seatedHumans()
	connected := 0
	for _, p := range hs {
		if p.connected() {
			connected++
		}
	}
	if c.Visibility == protocol.Public {
		switch {
		case connected == 0:
			c.setDeadline(0)
		case c.deadline == 0:
			if connected >= 2 {
				c.setDeadline(c.tick + c.ticks(c.cfg.PublicLobbyS))
			} else {
				c.setDeadline(c.tick + c.ticks(c.cfg.PublicLobbySoloS))
			}
		case connected >= 2 && c.deadline-c.tick > c.ticks(c.cfg.PublicLobbyS):
			c.setDeadline(c.tick + c.ticks(c.cfg.PublicLobbyS))
		}
		if c.allReady() && c.deadline-c.tick > c.ticks(c.cfg.AllReadyS) {
			c.setDeadline(c.tick + c.ticks(c.cfg.AllReadyS))
		}
	} else {
		if c.allReady() {
			if c.deadline == 0 {
				c.setDeadline(c.tick + c.ticks(c.cfg.PrivateAutoStartS))
			}
		} else {
			c.setDeadline(0)
		}
	}
	if c.deadline > 0 && c.tick >= c.deadline {
		c.startSelect()
	}
}

func (c *Core) setDeadline(t int) {
	if c.deadline != t {
		c.deadline = t
		c.roomDirty = true
	}
}

func (c *Core) startSelect() {
	c.State = Select
	c.claims = map[string]string{}
	c.previews = map[string]string{}
	for _, p := range c.players {
		p.vehicle = ""
	}
	c.deadline = c.tick + c.ticks(c.cfg.SelectS)
	c.roomDirty, c.selectDirty = true, true
}

func (c *Core) tickSelect() {
	all := true
	for _, p := range c.seatedHumans() {
		if _, ok := c.claimOf(p.ID); !ok && p.connected() {
			all = false
		}
	}
	if all || c.tick >= c.deadline {
		c.startRace()
	}
}

func (c *Core) freeVehicles() []string {
	var free []string
	for _, v := range c.data.Vehicles {
		if _, taken := c.claims[v.ID]; !taken {
			free = append(free, v.ID)
		}
	}
	return free
}

func (c *Core) startRace() {
	// unlocked humans get a random remaining vehicle
	var racers []*Player
	for _, p := range c.seatedHumans() {
		if _, ok := c.claimOf(p.ID); !ok {
			free := c.freeVehicles()
			v := free[c.rng.Intn(len(free))]
			c.claims[v] = p.ID
			p.vehicle = v
		}
		racers = append(racers, p)
	}
	// bots take what is left
	if c.BotsOn || c.Practice {
		for _, v := range c.freeVehicles() {
			if len(racers) >= c.cfg.MaxCars {
				break
			}
			veh, _ := c.data.vehicle(v)
			b := &Player{ID: "bot-" + v, Name: veh.Name + " Bot", Bot: true, vehicle: v, car: -1, disconnectedAt: -1}
			c.claims[v] = b.ID
			racers = append(racers, b)
		}
	}
	c.grid = c.gridOrder(racers)
	vehicles := make([]gamedata.Vehicle, len(c.grid))
	line := c.data.Lines[c.Map]
	for i, p := range c.grid {
		p.car = i
		p.input = sim.Input{}
		p.ack = 0
		p.afk, p.wasAfk = false, false
		p.lastInputTick = c.tick
		vehicles[i], _ = c.data.vehicle(p.vehicle)
		p.ctrl = bots.NewController(line, bots.Normal, c.rng.Uint32())
	}
	c.world = sim.NewWorld(c.data.Tracks[c.Map], c.data.Bal, vehicles, c.Laps)
	c.State = Countdown
	c.goTick = c.tick + c.ticks(c.data.Bal.Race.CountdownS)
	c.deadline = c.goTick
	c.roomDirty, c.selectDirty = true, false
	for _, p := range c.players {
		c.sendTo(p, c.raceStartFor(p))
	}
}

// gridOrder: reverse of the last race's results (random for the first race / newcomers).
func (c *Core) gridOrder(racers []*Player) []*Player {
	pos := map[string]int{}
	for i, id := range c.lastRank {
		pos[id] = i
	}
	shuffled := append([]*Player(nil), racers...)
	for i := len(shuffled) - 1; i > 0; i-- {
		j := c.rng.Intn(i + 1)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	}
	sort.SliceStable(shuffled, func(i, j int) bool {
		pi, iok := pos[shuffled[i].ID]
		pj, jok := pos[shuffled[j].ID]
		if iok && jok {
			return pi > pj // last place starts on pole
		}
		return iok && !jok
	})
	return shuffled
}

func (c *Core) raceStartFor(p *Player) protocol.RaceStart {
	grid := make([]protocol.GridSlot, len(c.grid))
	you := -1
	for i, g := range c.grid {
		grid[i] = protocol.GridSlot{Car: i, PlayerID: g.ID, Vehicle: g.vehicle, Name: g.Name, Bot: g.Bot}
		if g == p {
			you = i
		}
	}
	return protocol.RaceStart{
		T: protocol.TRaceStart, Seed: c.opt.Seed, Map: c.Map, Laps: c.Laps, Grid: grid,
		StartAt: c.unixMs(c.goTick), Tick: c.goTick, You: you,
	}
}

func (c *Core) tickRace() {
	if c.State == Countdown && c.tick >= c.goTick {
		c.State = Racing
		c.deadline = 0
		c.roomDirty = true
		c.broadcast(protocol.Ev{T: protocol.TEv, Kind: "state", Tick: c.tick, State: string(Racing)})
	}
	if c.State == Racing {
		c.driveCars()
		c.world.Step()
		for _, e := range c.world.Events {
			if e.Kind == "bump" || e.Kind == "land" {
				continue // cosmetic, derived on the client from snapshots
			}
			c.broadcast(protocol.Ev{T: protocol.TEv, Kind: e.Kind, Tick: c.tick, Car: e.Car, Other: e.Other, Value: e.Value})
		}
	}
	if c.tick%max(c.cfg.SnapshotEveryNth, 1) != 0 {
		c.sendSnapshot()
	}
	if c.State == Racing && c.world.Over() {
		c.finishRace()
	}
}

func (c *Core) driveCars() {
	afkTicks := c.ticks(c.cfg.AfkS)
	states := make([]*sim.CarState, len(c.world.Cars))
	for i, car := range c.world.Cars {
		states[i] = &car.State
	}
	for i, p := range c.grid {
		car := c.world.Cars[i]
		human := !p.Bot && p.connected()
		if human && c.tick-p.lastInputTick > afkTicks {
			p.afk, p.wasAfk = true, true
		}
		if human && !p.afk {
			car.Input = p.input
			continue
		}
		others := make([]*sim.CarState, 0, len(states)-1)
		for j, s := range states {
			if j != i {
				others = append(others, s)
			}
		}
		car.Input = p.ctrl.Decide(&car.State, others, c.world.Track)
	}
}

func (c *Core) sendSnapshot() {
	cars := make([]protocol.SnapCar, len(c.world.Cars))
	for i, car := range c.world.Cars {
		s := car.State
		var flags uint16
		if car.Finished {
			flags |= protocol.FlagFinished
		}
		cars[i] = protocol.SnapCar{ID: uint8(i), S: s.S, D: s.D, YawRel: s.YawRel, Y: s.Y, Speed: s.Speed, Vy: s.Vy, Lap: int8(s.Lap), Flags: flags}
	}
	base := protocol.EncodeSnapshot(uint32(c.tick), cars)
	for _, p := range c.players {
		if p.connected() {
			p.send(protocol.PatchAck(base, p.ack))
		}
	}
}

func (c *Core) finishRace() {
	rank := c.world.Ranking()
	tickMs := func(t int) int64 { return int64(t) * 1000 / int64(c.data.Bal.TickRate) }
	res := protocol.Results{T: protocol.TResults}
	c.lastRank = c.lastRank[:0]
	startTick := 0 // world ticks count from GO
	for pos, carID := range rank {
		car := c.world.Cars[carID]
		p := c.grid[carID]
		row := protocol.ResultRow{Pos: pos + 1, Car: carID, PlayerID: p.ID, Name: p.Name, Vehicle: p.vehicle, Bot: p.Bot, Finished: car.Finished}
		if car.Finished {
			row.TimeMs = tickMs(car.FinishTick - startTick)
		}
		prev := startTick
		for _, lt := range car.LapTicks {
			if lap := tickMs(lt - prev); row.BestLap == 0 || lap < row.BestLap {
				row.BestLap = lap
			}
			prev = lt
		}
		res.Rows = append(res.Rows, row)
		c.lastRank = append(c.lastRank, p.ID)
		if !p.Bot && !p.wasAfk {
			res.Verified = append(res.Verified, protocol.Verified{PlayerID: p.ID, BestLap: row.BestLap, TimeMs: row.TimeMs, Won: pos == 0 && car.Finished})
		}
	}
	c.broadcast(res)
	// AFK bookkeeping: 2 AFK races in a row in a public room → back to Home
	for _, p := range c.grid {
		if p.Bot || p.left {
			continue
		}
		if p.wasAfk {
			p.afkRaces++
		} else {
			p.afkRaces = 0
		}
		if c.Visibility == protocol.Public && p.afkRaces >= c.cfg.AfkRacesToKick {
			c.sendTo(p, protocol.Kicked{T: protocol.TKicked, Reason: "afk"})
			c.remove(p)
		}
	}
	c.State = Results
	c.deadline = c.tick + c.ticks(c.cfg.ResultsS)
	c.roomDirty = true
}

func (c *Core) toLobby() {
	// drop players whose reconnect window ran out
	for _, p := range append([]*Player(nil), c.players...) {
		if !p.connected() {
			c.remove(p)
		}
	}
	for _, p := range c.players {
		p.ready, p.vehicle, p.car, p.ctrl = false, "", -1, nil
	}
	// spectators take free seats in join order
	for _, p := range c.players {
		if p.spec && c.FreeSeats() > 0 {
			p.spec = false
		}
	}
	c.world, c.grid = nil, nil
	c.claims = map[string]string{}
	c.State = Lobby
	c.deadline = 0
	c.roomDirty = true
}

// ---------- output ----------

func (c *Core) unixMs(tick int) int64 {
	if tick <= 0 {
		return 0
	}
	return c.opt.Now().Add(time.Duration(tick-c.tick) * c.opt.TickDur).UnixMilli()
}

func (c *Core) sendTo(p *Player, msg any) {
	if p.connected() {
		p.send(protocol.Encode(msg))
	}
}

func (c *Core) errTo(p *Player, code, text string) {
	c.sendTo(p, protocol.Err{T: protocol.TErr, Code: code, Msg: text})
}

func (c *Core) broadcast(msg any) {
	b := protocol.Encode(msg)
	for _, p := range c.players {
		if p.connected() {
			p.send(b)
		}
	}
}

// RoomState builds the lobby view.
func (c *Core) RoomState() protocol.RoomState {
	rs := protocol.RoomState{
		T: protocol.TRoom, Code: c.Code, Name: c.Name, State: string(c.State), Visibility: c.Visibility,
		Map: c.Map, Laps: c.Laps, Bots: c.BotsOn, Deadline: c.unixMs(c.deadline), Region: protocol.DefaultRegion,
		Players: []protocol.PlayerInfo{},
	}
	for _, p := range c.players {
		rs.Players = append(rs.Players, protocol.PlayerInfo{ID: p.ID, Name: p.Name, Ready: p.ready, Host: p.ID == c.hostID,
			PingMs: p.pingMs, Vehicle: p.vehicle, Spec: p.spec})
	}
	for _, p := range c.grid {
		if p.Bot {
			rs.Players = append(rs.Players, protocol.PlayerInfo{ID: p.ID, Name: p.Name, Bot: true, Vehicle: p.vehicle})
		}
	}
	return rs
}

func (c *Core) selectState() protocol.Select {
	s := protocol.Select{T: protocol.TSelect, Previews: map[string]string{}, Deadline: c.unixMs(c.deadline), Claims: []protocol.Claim{}}
	for _, v := range c.data.Vehicles { // stable order
		if pid, ok := c.claims[v.ID]; ok {
			s.Claims = append(s.Claims, protocol.Claim{Vehicle: v.ID, PlayerID: pid})
		}
	}
	for k, v := range c.previews {
		s.Previews[k] = v
	}
	return s
}

func (c *Core) flush() {
	if c.roomDirty {
		c.broadcast(c.RoomState())
		c.roomDirty = false
		c.summaryVer++
	}
	if c.selectDirty && c.State == Select {
		c.broadcast(c.selectState())
		c.selectDirty = false
	}
}

// SummaryVersion changes whenever the public summary may have changed.
func (c *Core) SummaryVersion() int { return c.summaryVer }

// Summary is the room's row in the public listing.
func (c *Core) Summary() protocol.RoomSummary {
	humans := len(c.seatedHumans())
	bots := 0
	if c.grid != nil {
		for _, p := range c.grid {
			if p.Bot {
				bots++
			}
		}
	} else if c.BotsOn {
		bots = max(c.cfg.MaxCars-humans, 0)
	}
	host := ""
	if h := c.find(c.hostID); h != nil {
		host = h.Name
	}
	return protocol.RoomSummary{
		Code: c.Code, Name: c.Name, Host: host, Map: c.Map, Laps: c.Laps, Humans: humans, Bots: bots,
		MaxCars: c.cfg.MaxCars, State: string(c.State), Deadline: c.unixMs(c.deadline),
		Visibility: c.Visibility, Region: protocol.DefaultRegion, CreatedAt: c.CreatedAt.UnixMilli(),
	}
}

// Racing reports how many connected humans are currently in a race (for /api/stats).
func (c *Core) RacingHumans() int {
	if c.State != Racing && c.State != Countdown {
		return 0
	}
	n := 0
	for _, p := range c.grid {
		if !p.Bot && p.connected() {
			n++
		}
	}
	return n
}
