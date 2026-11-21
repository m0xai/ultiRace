extends Node

## Client app state machine (GAME_PLAN §2.3):
## Home → Lobby → Vehicle Select → Countdown → Race → Results → (Rematch → Lobby).
## The server drives every transition; this only shows the right screen and forwards input.
## Dev args: --auto quick|practice  (auto-play the flow for screenshots / device checks)
##           --auto-nolock (with --auto: stay on vehicle select), --join quick|practice (connect only)

const INPUT_HZ: float = 30.0
const RECONNECT_TRIES: int = 5

enum Screen { HOME, LOBBY, SELECT, RACE, BROWSE }

var _conn: Connection = null
var _screen: Screen = Screen.HOME
var _home: HomeScreen
var _lobby: LobbyScreen
var _select: SelectScreen
var _results: ResultsScreen
var _settings: SettingsScreen
var _browser: RoomBrowserScreen
var _overlay: CanvasLayer
var _view: RaceView
var _hud: RaceHud
var _pause: PauseMenu = null
var _touch: TouchControls
var _ui: CanvasLayer
var _seq: int = 0
var _input_t: float = 0.0
var _racing: bool = false
var _leaving: bool = false
var _reconnect_left: int = 0
var _last_opts: Dictionary = {}
var _names: Dictionary = {}
var _laps: int = 3
var _auto: String = ""
var _auto_locked: bool = false
var _ult_pending: int = 0
var _taps_at_go: int = -1
var _banner_t: float = 0.0


func _ready() -> void:
	InputSetup.ensure()
	_overlay = (load("res://src/testing/DebugOverlay.gd") as GDScript).new() as CanvasLayer
	add_child(_overlay)
	_view = RaceView.new()
	add_child(_view)
	_ui = CanvasLayer.new()
	add_child(_ui)
	_hud = RaceHud.new()
	_touch = TouchControls.new()
	_home = HomeScreen.new()
	_lobby = LobbyScreen.new()
	_select = SelectScreen.new()
	_results = ResultsScreen.new()
	_browser = RoomBrowserScreen.new()
	for c: Control in [_hud, _touch, _home, _lobby, _select, _results, _browser]:
		_ui.add_child(c)
	_home.play.connect(_play)
	_home.browse.connect(func() -> void: _show(Screen.BROWSE))
	_browser.back.connect(func() -> void: _show(Screen.HOME))
	_browser.join.connect(func(code: String) -> void: _play({"room": code}))
	_browser.play.connect(_play)
	_home.settings.connect(func() -> void:
		_settings = SettingsScreen.new()
		_ui.add_child(_settings)
		_settings.closed.connect(func() -> void:
			_settings.queue_free()
			_rebuild_touch()))
	_lobby.send.connect(_send)
	_lobby.leave.connect(_leave)
	_select.send.connect(_send)
	_touch.ability_pressed.connect(func() -> void: _ult_pending = 3) # hold "ab" for 3 inputs
	_hud.pause_pressed.connect(_open_pause)
	_results.send.connect(_send)
	_results.leave.connect(_leave)
	_show(Screen.HOME)
	_auto = Config.arg("--auto", "")
	var join: String = Config.arg("--join", "")
	if _auto != "":
		_play({"quick": _auto == "quick", "practice": _auto == "practice"})
	elif join != "":
		_play({"quick": join == "quick", "practice": join == "practice"})
	if Config.user_args().has("--browse"):
		_show(Screen.BROWSE)
	if Config.user_args().has("--settings"):
		_home.settings.emit()


## Recreate touch controls so new control settings (size, sides, tilt) apply.
func _rebuild_touch() -> void:
	var vis: bool = _touch.visible
	_touch.queue_free()
	_touch = TouchControls.new()
	_ui.add_child(_touch)
	_ui.move_child(_touch, 1)
	_touch.ability_pressed.connect(func() -> void: _ult_pending = 3)
	_touch.visible = vis
	_touch.ult_id = _own_ult()
	_view.reduce_motion = bool(Profile.get_value("reduce_motion", false))


## The own car's ULT id (icon on the ULT button).
func _own_ult() -> String:
	if _view == null or _view.you < 0:
		return ""
	for slot: Variant in _view.grid: # grid slots carry their car index; not ordered by it
		var sd: Dictionary = slot as Dictionary
		if int(sd.get("car", -1)) == _view.you:
			return str(GameData.vehicle(str(sd.get("vehicle", ""))).get("ult", ""))
	return ""


func _show(s: Screen) -> void:
	_screen = s
	if s == Screen.RACE and _view.track != null:
		AudioDirector.play_music(_view.track.theme)
	elif s != Screen.RACE:
		AudioDirector.play_music("menu")
	_home.visible = s == Screen.HOME
	_browser.visible = s == Screen.BROWSE
	_lobby.visible = s == Screen.LOBBY
	_select.visible = s == Screen.SELECT
	var race: bool = s == Screen.RACE
	_view.visible = race
	_hud.visible = race
	_touch.visible = race
	if not race:
		_results.visible = false


func _play(opts: Dictionary) -> void:
	_last_opts = opts
	_leaving = false
	_reconnect_left = RECONNECT_TRIES
	_connect(opts)


func _connect(opts: Dictionary) -> void:
	if _conn != null:
		_conn.queue_free()
	_conn = Connection.new()
	add_child(_conn)
	_conn.message.connect(_on_message)
	_conn.snapshot.connect(_view.push_snapshot)
	_overlay.conn = _conn
	_conn.closed.connect(_on_closed)
	var hello_opts: Dictionary = opts.duplicate()
	hello_opts["token"] = Profile.token()
	hello_opts["blocked"] = Profile.blocked()
	var name: String = Profile.player_name()
	if _conn.connect_to(Config.server_url(), Protocol.hello(name if name != "" else "Guest", hello_opts)) != OK:
		_home.show_error("Cannot reach the server.")


func _send(msg: Dictionary) -> void:
	if _conn != null:
		_conn.send(msg)


## In-race pause menu (the server keeps racing; steering is released while it is open).
func _open_pause() -> void:
	if _pause != null or _screen != Screen.RACE or not _racing:
		return
	_pause = PauseMenu.new()
	_ui.add_child(_pause)
	_touch.visible = false
	_pause.resumed.connect(_close_pause)
	_pause.leave_race.connect(func() -> void:
		_close_pause()
		_leave())
	_pause.settings.connect(func() -> void:
		_settings = SettingsScreen.new()
		_ui.add_child(_settings)
		_settings.closed.connect(func() -> void:
			_settings.queue_free()
			_rebuild_touch()
			_touch.visible = false))


func _close_pause() -> void:
	if _pause == null:
		return
	_pause.queue_free()
	_pause = null
	_touch.visible = _screen == Screen.RACE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _pause == null and _screen == Screen.RACE and _racing:
		get_viewport().set_input_as_handled()
		_open_pause()


func _leave() -> void:
	_close_pause()
	_leaving = true
	if _conn != null:
		_conn.close()
	_racing = false
	_view.clear()
	_show(Screen.HOME)


func _on_closed(_code: int, _reason: String) -> void:
	if _leaving:
		return
	var room: String = _conn.room_code if _conn != null else ""
	if room != "" and _reconnect_left > 0:
		_reconnect_left -= 1
		_hud.reconnecting = true
		await get_tree().create_timer(1.0).timeout
		_connect({"room": room})
		return
	_racing = false
	_view.clear()
	_show(Screen.HOME)
	_home.show_error("Connection lost.")


func _on_message(m: Dictionary) -> void:
	match m["t"] as String:
		Protocol.T_WELCOME:
			Profile.set_value("token", m["token"])
			_lobby.my_id = _conn.player_id
			_select.my_id = _conn.player_id
			_results.my_id = _conn.player_id
			_hud.reconnecting = false
			_reconnect_left = RECONNECT_TRIES
		Protocol.T_ROOM:
			_on_room(m)
		Protocol.T_SELECT:
			if _screen != Screen.SELECT:
				_select.reset()
				_auto_locked = false
				_show(Screen.SELECT)
			_select.names = _names
			_select.update_select(m)
			if _auto != "" and not _auto_locked and not Config.user_args().has("--auto-nolock"):
				_auto_locked = true
				_auto_lock(m)
		Protocol.T_RACE_START:
			_laps = int(m["laps"])
			_view.start_race(m)
			_touch.ult_id = _own_ult()
			_hud.setup(_view, _laps)
			_results.visible = false
			_racing = true
			_show(Screen.RACE)
			if Config.user_args().has("--auto-pause"): # dev: screenshot the pause menu
				get_tree().create_timer(8.0).timeout.connect(_open_pause)
			if Config.user_args().has("--auto-finish"): # dev: screenshot the finish camera + results
				get_tree().create_timer(8.0).timeout.connect(func() -> void:
					var rows: Array = []
					for i: int in _view.grid.size():
						var g: Dictionary = _view.grid[i] as Dictionary
						rows.append({"pos": i + 1, "playerId": str(g.get("playerId", "")), "name": str(g.get("name", "Bot")),
							"vehicle": str(g.get("vehicle", "bolt")), "timeMs": 110000 + i * 1300, "finished": true, "bot": true})
					_view.start_finish_camera()
					_results.show_results({"rows": rows})
					_results.visible = true
					_hud.visible = false
					_touch.visible = false)
		Protocol.T_EV:
			_on_event(m)
		Protocol.T_RESULTS:
			_close_pause()
			_view.start_finish_camera() # (also covers a race that ended before we crossed the line)
			_view.fade_engines(1.5, 1.5)
			_results.show_results(m)
			_results.visible = true
			_hud.visible = false # clean view of your car orbiting behind the results
			_touch.visible = false
			_racing = false
		Protocol.T_KICKED:
			_leaving = true
			_view.clear()
			_show(Screen.HOME)
			_home.show_error("Removed from the room (%s)." % m.get("reason", ""))
		Protocol.T_ERR:
			match str(m.get("code", "")):
				"version":
					_leaving = true
					_show(Screen.HOME)
					_home.show_error("Please update UltiRace to play.")
				"no_room", "banned", "room_full":
					_leaving = true
					_show(Screen.HOME)
					_home.show_error("Could not join that room.")
				_:
					print("server: ", m)


func _on_room(m: Dictionary) -> void:
	_names.clear()
	for p: Variant in m["players"] as Array:
		var pd: Dictionary = p as Dictionary
		_names[pd["id"]] = pd["name"]
	if m["state"] == "LOBBY":
		_racing = false
		if _screen != Screen.LOBBY:
			_view.clear()
			_show(Screen.LOBBY)
		_lobby.update_room(m)
		if _auto != "":
			_auto_lobby(m)


func _auto_lobby(m: Dictionary) -> void:
	for p: Variant in m["players"] as Array:
		var pd: Dictionary = p as Dictionary
		if pd["id"] == _conn.player_id:
			if not pd.get("ready", false):
				_send(Protocol.ready(true))
			elif pd.get("host", false) and m["visibility"] == Protocol.PRIVATE:
				_send(Protocol.start())


func _auto_lock(m: Dictionary) -> void:
	var taken: Dictionary = {}
	for c: Variant in m["claims"] as Array:
		taken[(c as Dictionary)["vehicle"]] = true
	for v: Variant in GameData.vehicles():
		var vid: String = (v as Dictionary)["id"] as String
		if not taken.has(vid):
			_send(Protocol.lock(vid))
			return


const ULT_NAMES: Dictionary = {"nitro": "Nitro", "ram": "Ram Charge", "ice": "Ice Slick", "emp": "EMP Pulse",
	"grapple": "Grapple", "goo": "Goo Bomb", "phase": "Phase", "tornado": "Tornado"}


func _on_event(m: Dictionary) -> void:
	_view.on_event(m)
	var kind: String = str(m.get("kind", ""))
	var car: int = int(m.get("car", -1))
	if kind == "hit" and car == _view.you:
		var src: int = int(m.get("other", -1))
		var who: String = str((_view.grid[src] as Dictionary)["name"]) if src >= 0 and src < _view.grid.size() else ""
		_hud.banner("%s — %s" % [ULT_NAMES.get(str(m.get("ult", "")), "Hit"), who])
	elif kind == "startBoost" and car == _view.you:
		_hud.banner("START BOOST!")
	elif kind == "abilityUsed":
		_view.flash(car)


func _process(delta: float) -> void:
	if not _racing or _view.you < 0:
		return
	var flags: int = _view.flags_of(_view.you)
	_touch.ult_progress = Protocol.charge_of(flags)
	var ready_now: bool = _touch.ult_progress >= 0.999 and _view.race_time() >= 3.0
	if ready_now and not _touch.ult_ready:
		AudioDirector.sfx("ult_ready", -6.0)
		Haptics.tap_light()
	_touch.ult_ready = ready_now
	# fixed 30 Hz input clock (carry the remainder): the server applies one input per tick and
	# prediction replays them one by one, so the rate must match exactly
	_input_t = minf(_input_t + delta, 3.0 / INPUT_HZ)
	while _input_t >= 1.0 / INPUT_HZ:
		_input_t -= 1.0 / INPUT_HZ
		_send_input_tick()
	if _view.prediction != null:
		# render blend phase from the ideal 30 Hz schedule (keeps the remainder); measuring from the
		# frame that happened to run the tick made the car hitch every few frames
		_view.prediction.phase = _input_t * INPUT_HZ


func _send_input_tick() -> void:
	_seq += 1
	var thr: int = _touch.throttle
	if Profile.auto_accelerate():
		# Start boost needs a fresh press within 0.25 s after GO: with auto-accelerate the throttle
		# stays off during the countdown (touching counts as a jump start) and turns on 0.3 s after
		# GO, or earlier when the player taps after GO.
		var t: float = _view.race_time()
		if t < 0.0:
			thr = 1 if _touch.touching else 0
			_taps_at_go = _touch.taps
		elif t < 0.3:
			thr = 1 if _touch.taps > _taps_at_go else 0
	var ab: bool = _ult_pending > 0
	_ult_pending = max(_ult_pending - 1, 0)
	var steer: int = 0 if _pause != null else Protocol.steer_from_screen(_touch.steer)
	_send(Protocol.input(_seq, steer, thr, ab))
	if _view.prediction != null:
		_view.prediction.step_local(_seq, steer, thr)
