extends Control

## M0 boot screen: proves the app starts on device. Replaced by App.gd's state machine in M5.

@onready var _version_label: Label = $Center/VBox/Version
@onready var _watch: Button = $Center/VBox/Watch
@onready var _server: Label = $Center/VBox/Server

func _ready() -> void:
	var ver: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var engine: String = Engine.get_version_info().get("string", "") as String
	_version_label.text = "v%s · Godot %s · %s" % [ver, engine, OS.get_name()]
	_server.text = Config.server_url()
	_watch.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://src/app/Watch.tscn"))
	if Config.user_args().has("--watch"):
		_watch.pressed.emit()
