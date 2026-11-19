package server

import (
	"bytes"
	"context"
	"errors"
	"math/rand/v2"
	"net/http"
	"time"

	"github.com/coder/websocket"

	"github.com/m0xai/ultiRace/internal/mathx"
	"github.com/m0xai/ultiRace/internal/moderation"
	"github.com/m0xai/ultiRace/internal/protocol"
	"github.com/m0xai/ultiRace/internal/room"
)

const (
	helloTimeout   = 5 * time.Second
	writeTimeout   = 5 * time.Second
	outBufferSize  = 64
	msgRatePerSec  = 60 // inputs arrive at 30 Hz; leave headroom for UI messages
	msgBurst       = 120
	kickedPrefix   = `{"t":"kicked"`
	readLimitBytes = protocol.MaxMessageBytes
)

// GET /ws — one WebSocket per player (GAME_PLAN §3.4: reader + writer goroutine).
func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	ip := clientIP(r)
	if !s.connLimit.Allow(ip) {
		http.Error(w, "rate limited", http.StatusTooManyRequests)
		return
	}
	ws, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true}) // native app clients send no Origin
	if err != nil {
		return
	}
	ws.SetReadLimit(readLimitBytes)
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	c := &conn{s: s, ws: ws, ip: ip, out: make(chan outMsg, outBufferSize), cancel: cancel}
	defer ws.CloseNow()
	c.serve(ctx)
}

type outMsg struct {
	b  []byte
	at time.Time
}

type conn struct {
	s      *Server
	ws     *websocket.Conn
	ip     string
	out    chan outMsg
	cancel context.CancelFunc
	id     string
	rm     *room.Room

	lastIn, lastOut time.Time // simulated-lag delivery times (monotonic per direction)
}

// send is the room's Sender: never blocks; a full buffer drops the client (it reconnects).
func (c *conn) send(b []byte) {
	select {
	case c.out <- outMsg{b: b, at: time.Now()}:
	default:
		c.cancel()
	}
}

func (c *conn) writeNow(ctx context.Context, v any) {
	wctx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	_ = c.ws.Write(wctx, websocket.MessageText, protocol.Encode(v))
}

func (c *conn) fail(ctx context.Context, code, msg string) {
	c.writeNow(ctx, protocol.Err{T: protocol.TErr, Code: code, Msg: msg})
	_ = c.ws.Close(websocket.StatusPolicyViolation, code)
}

func (c *conn) serve(ctx context.Context) {
	hctx, hcancel := context.WithTimeout(ctx, helloTimeout)
	typ, data, err := c.ws.Read(hctx)
	hcancel()
	if err != nil || typ != websocket.MessageText {
		return
	}
	msg, err := protocol.DecodeClient(data)
	hello, ok := msg.(*protocol.Hello)
	if err != nil || !ok {
		c.fail(ctx, protocol.ErrBadMessage, "first message must be hello")
		return
	}
	if hello.V != protocol.Version {
		c.fail(ctx, protocol.ErrVersion, "please update the app")
		return
	}
	token := hello.Token
	if len(token) < 16 || len(token) > 64 {
		token = newToken()
	}
	c.id = c.s.playerID(token)
	if c.s.Bans.Banned(c.id) {
		c.fail(ctx, protocol.ErrBanned, "banned")
		return
	}
	name, _ := moderation.CleanName(hello.Name, mathx.NewRng(rand.Uint32()))

	code, errCode := c.join(ctx, hello, token, name)
	if errCode != "" {
		c.fail(ctx, errCode, "could not join")
		return
	}
	c.writeNow(ctx, protocol.Welcome{T: protocol.TWelcome, PlayerID: c.id, Token: token, Room: code})

	go c.writer(ctx)
	c.reader(ctx)
	c.rm.Post(func(core *room.Core) { core.Disconnect(c.id) })
}

// join resolves where the player goes: reconnect, room code, practice, create or quick play.
func (c *conn) join(ctx context.Context, h *protocol.Hello, token, name string) (string, string) {
	s := c.s
	try := func(rm *room.Room) (string, bool) {
		var res room.JoinResult
		reconnected := false
		if !rm.Do(func(core *room.Core) {
			if h.Token != "" {
				if _, ok := core.Reconnect(token, c.send); ok {
					reconnected = true
					return
				}
			}
			res = core.Join(c.id, name, token, h.Blocked, c.send)
		}) {
			return protocol.ErrNoRoom, false
		}
		if reconnected {
			c.rm = rm
			return "", true
		}
		if res.Err != "" {
			return res.Err, false
		}
		c.rm = rm
		return "", true
	}

	switch {
	case h.Room != "":
		rm := s.Rooms.Get(h.Room)
		if rm == nil {
			return "", protocol.ErrNoRoom
		}
		if e, ok := try(rm); !ok {
			return "", e
		}
		s.MM.Release(rm.Code)
		return rm.Code, ""
	case h.Practice || h.Create != nil:
		if !s.createLimit.Allow(c.ip) {
			return "", protocol.ErrRateLimited
		}
		vis := protocol.Public
		if h.Practice || (h.Create != nil && h.Create.Visibility == protocol.Private) {
			vis = protocol.Private
		}
		rm, err := s.Rooms.Create(vis, h.Practice)
		if err != nil {
			return "", protocol.ErrServer
		}
		if e, ok := try(rm); !ok {
			return "", e
		}
		return rm.Code, ""
	case h.Quick:
		exclude := map[string]bool{}
		for attempt := 0; attempt < 3; attempt++ {
			code, err := s.MM.Pick(h.Blocked, exclude)
			if err != nil {
				return "", protocol.ErrServer
			}
			rm := s.Rooms.Get(code)
			if rm == nil {
				exclude[code] = true
				continue
			}
			_, ok := try(rm)
			s.MM.Release(code)
			if ok {
				return code, ""
			}
			exclude[code] = true
		}
		return "", protocol.ErrRoomFull
	}
	return "", protocol.ErrBadMessage
}

type inMsg struct {
	post func() bool
	at   time.Time
}

func (c *conn) reader(ctx context.Context) {
	var delayed chan inMsg
	if c.s.cfg.SimLag > 0 {
		delayed = make(chan inMsg, 256)
		go func() {
			for {
				select {
				case <-ctx.Done():
					return
				case m := <-delayed:
					inDelay.wait(&c.lastIn, m.at, c.s.lag())
					m.post()
				}
			}
		}()
	}
	for {
		typ, data, err := c.ws.Read(ctx)
		if err != nil {
			return
		}
		if typ != websocket.MessageText {
			continue
		}
		if !c.s.apiLimitConn(c) {
			c.send(protocol.Encode(protocol.Err{T: protocol.TErr, Code: protocol.ErrRateLimited, Msg: "slow down"}))
			continue
		}
		msg, err := protocol.DecodeClient(data)
		if err != nil {
			if errors.Is(err, protocol.ErrUnknownType) {
				continue // newer client feature; ignore
			}
			c.send(protocol.Encode(protocol.Err{T: protocol.TErr, Code: protocol.ErrBadMessage, Msg: "bad message"}))
			continue
		}
		id := c.id
		post := func() bool { return c.rm.Post(func(core *room.Core) { core.Handle(id, msg) }) }
		if delayed != nil { // dev only: simulated inbound latency
			select {
			case delayed <- inMsg{post: post, at: time.Now()}:
			default: // dev queue overflow: drop
			}
		} else if !post() {
			return
		}
		if _, leaving := msg.(*protocol.Leave); leaving {
			return
		}
	}
}

func (c *conn) writer(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case m := <-c.out:
			b := m.b
			if c.s.cfg.SimLag > 0 {
				inDelay.wait(&c.lastOut, m.at, c.s.lag())
			}
			typ := websocket.MessageText
			if len(b) > 0 && b[0] == protocol.SnapKind {
				typ = websocket.MessageBinary
			}
			wctx, cancel := context.WithTimeout(ctx, writeTimeout)
			err := c.ws.Write(wctx, typ, b)
			cancel()
			if err != nil {
				c.cancel()
				return
			}
			if bytes.HasPrefix(b, []byte(kickedPrefix)) {
				_ = c.ws.Close(websocket.StatusNormalClosure, "kicked")
				c.cancel()
				return
			}
		}
	}
}

// lag returns one artificial delay (dev flags -sim-lag / -sim-jitter).
func (s *Server) lag() time.Duration {
	d := s.cfg.SimLag
	if s.cfg.SimJitter > 0 {
		d += time.Duration(rand.Int64N(int64(2*s.cfg.SimJitter))) - s.cfg.SimJitter
	}
	return max(d, 0)
}

type delayer struct{}

var inDelay delayer

// wait sleeps until max(previous delivery, at+lag): simulated latency without serialising
// the stream (each message keeps its own send time) and without reordering it.
func (delayer) wait(last *time.Time, at time.Time, lag time.Duration) {
	deliver := at.Add(lag)
	if deliver.Before(*last) {
		deliver = *last
	}
	*last = deliver
	if d := time.Until(deliver); d > 0 {
		time.Sleep(d)
	}
}

// apiLimitConn applies the per-player message limit (bucket keyed by player id).
func (s *Server) apiLimitConn(c *conn) bool { return s.msgLimit.Allow(c.id) }
