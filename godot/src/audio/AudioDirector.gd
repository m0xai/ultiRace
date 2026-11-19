extends Node

## Audio buses, music and SFX (GAME_PLAN §5). Autoload "AudioDirector".
## Buses: Master (hard limiter) ← Music / SFX / Engine / UI. Music ducks under loud SFX.

const BUSES: PackedStringArray = ["Music", "SFX", "Engine", "UI"]
const SFX_POOL: int = 8
const DUCK_DB: float = -8.0

var _music: AudioStreamPlayer
var _music_name: String = ""
var _pool: Array[AudioStreamPlayer] = []
var _pool_i: int = 0
var _cache: Dictionary = {}
var _duck: float = 0.0


func _ready() -> void:
	for b: String in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	if AudioServer.get_bus_effect_count(0) == 0:
		AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	for i: int in SFX_POOL:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	apply_volumes()


## Bus volumes from the profile (0–1 linear).
func apply_volumes() -> void:
	for b: String in BUSES:
		var v: float = float(Profile.get_value("vol_" + b.to_lower(), 0.8 if b == "Music" else 1.0))
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(b), linear_to_db(maxf(v, 0.0001)))


static func load_stream(name: String, loop: bool = false) -> AudioStreamWAV:
	var s: AudioStreamWAV = load("res://assets/audio/%s.wav" % name) as AudioStreamWAV
	if s != null and loop:
		s = s.duplicate() as AudioStreamWAV
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * float(s.mix_rate))
	return s


func play_music(name: String) -> void:
	if name == _music_name:
		return
	_music_name = name
	_music.stream = load_stream("music_" + name, true)
	_music.play()


func sfx(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _cache.has(name):
		_cache[name] = load_stream("sfx_" + name)
	var s: AudioStream = _cache[name] as AudioStream
	if s == null:
		return
	var p: AudioStreamPlayer = _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
	if volume_db > -6.0:
		_duck = 0.6


func _process(delta: float) -> void:
	_duck = maxf(_duck - delta, 0.0)
	var target: float = DUCK_DB if _duck > 0.0 else 0.0
	_music.volume_db = lerpf(_music.volume_db, target, minf(1.0, delta * 8.0))
