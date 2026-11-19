class_name Connection
extends Node

## One WebSocket to the game server (GAME_PLAN §3.5). Sends hello on open, pings at 1 Hz,
## emits decoded JSON messages and binary snapshots.

signal opened
signal message(msg: Dictionary)
signal snapshot(snap: Protocol.Snapshot)
signal closed(code: int, reason: String)

const PING_INTERVAL_S: float = 1.0

var player_id: String = ""
var token: String = ""
var room_code: String = ""
var ping_ms: int = 0
var bytes_in: int = 0

var _ws: WebSocketPeer = WebSocketPeer.new()
var _hello: Dictionary = {}
var _was_open: bool = false
var _active: bool = false
var _ping_t: float = 0.0


func connect_to(url: String, hello_msg: Dictionary) -> Error:
	_hello = hello_msg
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 16
	_was_open = false
	var err: Error = _ws.connect_to_url(url.trim_suffix("/") + "/ws")
	_active = err == OK
	return err


func send(msg: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func close() -> void:
	if _active:
		send(Protocol.leave())
		_ws.close(1000, "bye")


func is_open() -> bool:
	return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func _process(delta: float) -> void:
	if not _active:
		return
	_ws.poll()
	var state: WebSocketPeer.State = _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			send(_hello)
			opened.emit()
		while _ws.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _ws.get_packet()
			bytes_in += pkt.size()
			if _ws.was_string_packet():
				_on_text(pkt.get_string_from_utf8())
			else:
				var snap: Protocol.Snapshot = Protocol.decode_snapshot(pkt)
				if snap != null:
					snapshot.emit(snap)
		_ping_t += delta
		if _ping_t >= PING_INTERVAL_S:
			_ping_t = 0.0
			send(Protocol.ping(Time.get_ticks_msec()))
	elif state == WebSocketPeer.STATE_CLOSED:
		_active = false
		closed.emit(_ws.get_close_code(), _ws.get_close_reason())


func _on_text(text: String) -> void:
	var m: Dictionary = Protocol.parse(text)
	if m.is_empty():
		return
	match m["t"] as String:
		Protocol.T_WELCOME:
			player_id = m["playerId"] as String
			token = m["token"] as String
			room_code = m["room"] as String
		Protocol.T_PONG:
			ping_ms = Time.get_ticks_msec() - int(m["ts"])
	message.emit(m)
