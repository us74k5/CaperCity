extends Node
## Autoload "Music": scene-aware soundtrack.
##
## Picks a looping track from what's on screen (title, lobby, street, the building the active
## player is in, a police standoff, jail, victory) and crossfades between them. Plays the one-shot
## stings the server queues in state.cue (shootout, busted, rank up...). Every client renders the
## same state, so spectators hear exactly what the active player hears.
## On/off is remembered in user://settings.cfg. Silent on dedicated/headless servers.

const SETTINGS_PATH := "user://settings.cfg"
const FADE := 1.2
const MUSIC_DB := -9.0
const DUCK_DB := -18.0
# Cues that are sound effects rather than music stings (they follow the sound effects switch).
const SFX_CUES := {"arm_up": "gun_cock"}
const STING_FILES := {
	"shootout": "shootout", "gang_war": "gang_war", "success": "success", "fail": "gamble_lose",
	"jail_door": "jail_door", "rank_up": "rank_up", "kidnap": "kidnap", "cash": "cash",
	"gamble_win": "gamble_win", "gamble_lose": "gamble_lose", "month": "month", "holiday": "holiday",
	"police_alert": "police_alert", "busted": "busted",
}

var _enabled := true
var _silent := false
var _players: Array[AudioStreamPlayer] = []
var _cur := 0
var _scene := ""
var _sting: AudioStreamPlayer
var _queue: Array = []
var _last_cue := -1
var _cache := {}
var _tween: Tween
## Set by the HUD: true while an outcome is still being played out on screen (a casino hand), so
## its sting waits for the reveal instead of giving the result away.
var hold_while: Callable
var _held: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = DisplayServer.get_name() == "headless" or "--server" in OS.get_cmdline_user_args()
	if _silent:
		return
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_sting = AudioStreamPlayer.new()
	_sting.volume_db = -4.0
	_sting.finished.connect(_next_sting)
	add_child(_sting)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_enabled = cfg.get_value("audio", "music", true)
	Net.state_updated.connect(_on_state)
	Net.connection_lost.connect(func(_r): _on_state())
	set_scene("menu")


func is_on() -> bool:
	return _enabled


func is_enabled() -> bool:   # older name, used by the web title screen
	return _enabled


func toggle() -> bool:
	_enabled = not _enabled
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music", _enabled)
	cfg.save(SETTINGS_PATH)
	if _silent:
		return _enabled
	if _enabled:
		var s := _scene
		_scene = ""
		set_scene(s if s != "" else "menu")
	else:
		for p in _players:
			p.stop()
		_sting.stop()
		_queue.clear()
	return _enabled


## Which loop fits the current game state.
func scene_for_state(s: Dictionary) -> String:
	if s.is_empty():
		return "menu"
	match str(s.get("phase", "")):
		"lobby":
			return "lobby"
		"over":
			return "victory"
	var pend: Dictionary = s.get("pending", {})
	var active: Dictionary = {}
	if s.get("order", []).size() > 0:
		active = s.players[s.order[s.active]]
	match str(pend.get("kind", "")):
		"police":
			return "police_standoff"
		"fight":
			return "fight"
		"mini":
			var game := str(s.get("mini", {}).get("game", ""))
			return "chase" if game in ["escape", "catch"] else "heist"
	if not active.is_empty() and int(active.get("jail", 0)) > 0:
		return "jail"
	if not active.is_empty() and int(active.get("inside", -1)) >= 0:
		return str(s.city.buildings[int(active.inside)].type)
	return "street"


func set_scene(name: String) -> void:
	if _silent or name == _scene:
		return
	_scene = name
	_debug("scene -> " + name)
	if not _enabled:
		return
	var stream := _load("res://audio/music/%s.ogg" % name, true)
	if stream == null:
		return
	var old: AudioStreamPlayer = _players[_cur]
	_cur = 1 - _cur
	var new: AudioStreamPlayer = _players[_cur]
	new.stream = stream
	new.volume_db = -40.0
	new.play()
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(new, "volume_db", _music_level(), FADE)
	if old.playing:
		_tween.tween_property(old, "volume_db", -60.0, FADE)
		_tween.chain().tween_callback(old.stop)


func _music_level() -> float:
	return DUCK_DB if _sting != null and _sting.playing else MUSIC_DB


func _on_state() -> void:
	if _silent:
		return
	var s: Dictionary = Net.state
	set_scene(scene_for_state(s))
	var cue: Dictionary = s.get("cue", {})
	var n := int(cue.get("n", 0))
	if s.is_empty():
		_last_cue = -1
		return
	if _last_cue < 0:
		_last_cue = n          # joining mid-game: don't replay old stings
		return
	if n != _last_cue:
		_last_cue = n
		if hold_while.is_valid() and hold_while.call():
			_held.append_array(cue.get("names", []))
			return
		_play_cues(cue.get("names", []))


func _process(_delta: float) -> void:
	if _held.size() > 0 and not (hold_while.is_valid() and hold_while.call()):
		var names := _held.duplicate()
		_held.clear()
		_play_cues(names)


func _play_cues(names: Array) -> void:
	for c in names:
		if SFX_CUES.has(c):
			Sfx.play(SFX_CUES[c])
		elif STING_FILES.has(c):
			_queue.append(STING_FILES[c])
	if not _sting.playing:
		_next_sting()


func _next_sting() -> void:
	if _queue.is_empty() or not _enabled:
		_duck(false)
		return
	var sting_name: String = _queue.pop_front()
	_debug("sting  -> " + sting_name)
	var stream := _load("res://audio/sfx/%s.ogg" % sting_name, false)
	if stream == null:
		_next_sting()
		return
	_sting.stream = stream
	_sting.play()
	_duck(true)


func _duck(on: bool) -> void:
	var p: AudioStreamPlayer = _players[_cur]
	if p.playing:
		create_tween().tween_property(p, "volume_db", DUCK_DB if on else MUSIC_DB, 0.25)


func _debug(msg: String) -> void:
	if OS.has_environment("CAPER_AUDIO_DEBUG"):
		print("[music] ", msg)


func _load(path: String, loop: bool) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		push_warning("Missing audio: " + path)
		return null
	var s := load(path) as AudioStreamOggVorbis
	if s:
		s.loop = loop
	_cache[path] = s
	return s
