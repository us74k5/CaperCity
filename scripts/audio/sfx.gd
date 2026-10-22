extends Node
## Autoload "Sfx": short sound effects (gunshots, blows, explosions) for the fight arena and shops.
##
## play("pistol") picks a random variant from audio/weapons/pistol_1.ogg, pistol_2.ogg ... (or
## pistol.ogg if there is just one), adds a little pitch jitter so repeats don't sound robotic, and
## plays it on a free voice from a small pool. Drop replacement files in with the same names to
## swap in recorded sounds (.ogg, .wav or .mp3 all work).
## On/off is remembered in user://settings.cfg (audio/sfx). Silent on dedicated/headless servers.

const SETTINGS_PATH := "user://settings.cfg"
const DIRS := ["res://audio/weapons/", "res://audio/sfx/"]
const EXTS := ["ogg", "wav", "mp3"]
const VOICES := 12
const BASE_DB := -3.0

var _enabled := true
var _silent := false
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _variants := {}   # name -> Array[AudioStream]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = DisplayServer.get_name() == "headless" or "--server" in OS.get_cmdline_user_args()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_enabled = cfg.get_value("audio", "sfx", true)
	if _silent:
		return
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


func is_on() -> bool:
	return _enabled


func toggle() -> bool:
	_enabled = not _enabled
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "sfx", _enabled)
	cfg.save(SETTINGS_PATH)
	if not _enabled:
		for p in _pool:
			p.stop()
	return _enabled


## True if there is at least one sound file for `name`.
func has(name: String) -> bool:
	return not _streams(name).is_empty()


## Play one variant of `name`. `delay` seconds from now if > 0. Returns false if there's no such sound.
func play(name: String, volume_db := 0.0, pitch_jitter := 0.06, delay := 0.0) -> bool:
	if _silent or not _enabled:
		return false
	var streams := _streams(name)
	if streams.is_empty():
		return false
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func(): play(name, volume_db, pitch_jitter))
		return true
	var p := _voice()
	p.stream = streams[randi() % streams.size()]
	p.volume_db = BASE_DB + volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
	return true


func _voice() -> AudioStreamPlayer:
	for i in VOICES:
		var p := _pool[(_next + i) % VOICES]
		if not p.playing:
			_next = (_next + i + 1) % VOICES
			return p
	# all busy: steal the oldest
	var q := _pool[_next]
	_next = (_next + 1) % VOICES
	return q


func _streams(name: String) -> Array:
	if _variants.has(name):
		return _variants[name]
	var out: Array = []
	for dir in DIRS:
		for ext in EXTS:
			if ResourceLoader.exists(dir + name + "." + ext):
				out.append(load(dir + name + "." + ext))
		for i in range(1, 9):
			for ext in EXTS:
				var path: String = dir + "%s_%d.%s" % [name, i, ext]
				if ResourceLoader.exists(path):
					out.append(load(path))
		if not out.is_empty():
			break
	_variants[name] = out
	return out
