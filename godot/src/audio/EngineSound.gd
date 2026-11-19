class_name EngineSound
extends Node3D

## Engine layers (GAME_PLAN §5): idle/mid/high loops per car class, cross-faded and pitched by
## speed. The own car plays 2D; other cars 3D (RaceView keeps at most 4 audible).

const LAYERS: PackedStringArray = ["idle", "mid", "high"]

var _players: Array[Node] = []
var _top: float = 40.0
var audible: bool = true


static func car_class(vehicle_id: String) -> String:
	var w: int = int((GameData.vehicle(vehicle_id)["stats"] as Dictionary)["weight"])
	return "heavy" if w >= 4 else ("light" if w <= 2 else "medium")


func setup(vehicle_id: String, own: bool) -> void:
	_top = Physics.params_for_vehicle(vehicle_id).top_speed
	var cls: String = car_class(vehicle_id)
	for layer: String in LAYERS:
		var stream: AudioStreamWAV = AudioDirector.load_stream("engine_%s_%s" % [cls, layer], true)
		var p: Node
		if own:
			var p2: AudioStreamPlayer = AudioStreamPlayer.new()
			p2.stream = stream
			p2.bus = "Engine"
			p = p2
		else:
			var p3: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
			p3.stream = stream
			p3.bus = "Engine"
			p3.unit_size = 8.0
			p3.max_distance = 120.0
			p = p3
		add_child(p)
		_players.append(p)
		p.call("play")


func update(speed: float) -> void:
	var x: float = clampf(speed / maxf(_top, 1.0), 0.0, 1.3)
	# weights: idle at 0, mid around 0.5, high near top speed
	var w: Array[float] = [clampf(1.0 - x * 2.5, 0.0, 1.0), clampf(1.0 - absf(x - 0.5) * 2.5, 0.0, 1.0), clampf((x - 0.45) * 2.2, 0.0, 1.0)]
	for i: int in _players.size():
		var p: Node = _players[i]
		var db: float = linear_to_db(maxf(w[i] * (1.0 if audible else 0.0), 0.0001)) - 6.0
		p.set("volume_db", db)
		p.set("pitch_scale", 0.8 + x * 0.6)
