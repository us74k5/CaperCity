extends AudioStreamPlayer
## Autoload "Music": loops the theme. On/off is remembered in user://settings.cfg.

const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless" or "--server" in OS.get_cmdline_user_args():
		return
	var s := load("res://audio/theme.ogg") as AudioStreamOggVorbis
	if s == null:
		return
	s.loop = true
	stream = s
	volume_db = -9.0
	if is_enabled():
		play()


func is_enabled() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return cfg.get_value("audio", "music", true)


func toggle() -> bool:
	var on := not playing
	if on:
		play()
	else:
		stop()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music", on)
	cfg.save(SETTINGS_PATH)
	return on
