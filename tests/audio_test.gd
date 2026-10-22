extends SceneTree
## Plays random games and checks that every scene the game reaches has a music loop and
## every sting the server raises has a sound file.
## Run: godot --headless --path . --script res://tests/audio_test.gd

func _process(_d: float) -> bool:
	var music: Node = root.get_node("Music")
	var scenes := {}
	var cues := {}
	var problems := 0
	scenes[music.scene_for_state({})] = true
	for gi in 25:
		var g := GameServer.new(500 + gi)
		g.handle(1, {"t": "join", "name": "Ana", "crew": ""})
		scenes[music.scene_for_state(g.state)] = true
		g.handle(1, {"t": "add_local", "name": "Bo", "crew": ""})
		g.handle(1, {"t": "start", "target": 15})
		var rng := RandomNumberGenerator.new()
		rng.seed = gi
		var last_n := 0
		var steps := 0
		while g.state.phase == "playing" and steps < 30000:
			steps += 1
			var s: Dictionary = g.state
			var p: Dictionary = s.players[s.order[s.active]]
			var intent := {}
			if not s.pending.is_empty():
				var opts: Array = s.pending.options.filter(func(o): return o.get("enabled", true))
				intent = {"t": "pending", "id": opts[rng.randi() % opts.size()].id}
			elif int(p.inside) >= 0:
				var en: Array = p.menu.filter(func(e): return e.enabled and (str(e.id).begins_with("act:") or str(e.id).begins_with("sub:") or rng.randf() < 0.2))
				if en.is_empty():
					en = p.menu.filter(func(e): return e.enabled)
				intent = {"t": "menu", "id": en[rng.randi() % en.size()].id}
			elif rng.randf() < 0.02:
				intent = {"t": "gang_war", "target": s.order[rng.randi() % s.order.size()]}
			else:
				intent = {"t": "move", "dir": ["N", "S", "E", "W"][rng.randi() % 4]}
			g.handle(1, intent)
			scenes[music.scene_for_state(g.state)] = true
			if int(g.state.cue.n) != last_n:
				last_n = int(g.state.cue.n)
				for c in g.state.cue.names:
					cues[c] = true
		scenes[music.scene_for_state(g.state)] = true
	for sname in scenes:
		if not ResourceLoader.exists("res://audio/music/%s.ogg" % sname):
			print("PROBLEM: no music for scene ", sname)
			problems += 1
	for c in cues:
		if music.SFX_CUES.has(c):
			if not ResourceLoader.exists("res://audio/weapons/%s.ogg" % music.SFX_CUES[c]):
				print("PROBLEM: no sound effect for cue ", c)
				problems += 1
			continue
		if not music.STING_FILES.has(c) or not ResourceLoader.exists("res://audio/sfx/%s.ogg" % music.STING_FILES[c]):
			print("PROBLEM: no sting for cue ", c)
			problems += 1
	var fv_src := FileAccess.get_file_as_string("res://scripts/ui/fight_view.gd")
	var wanted := ["pistol", "rifle", "machine_gun", "explosion", "grenade_pin", "grenade_bounce", "gun_cock", "knife_throw",
		"knife_thunk", "knife_stab", "knife_slash", "swing_light", "swing_heavy", "punch_hit", "club_hit", "baton_hit",
		"bullet_flesh", "bullet_miss", "body_fall"]
	for w in wanted:
		if not fv_src.contains("\"%s\"" % w):
			print("PROBLEM: fight view no longer plays ", w)
			problems += 1
		if not ResourceLoader.exists("res://audio/weapons/%s.ogg" % w) and not ResourceLoader.exists("res://audio/weapons/%s_1.ogg" % w):
			print("PROBLEM: no weapon sound ", w)
			problems += 1
	var never: Array = []
	for f in DirAccess.get_files_at("res://audio/music"):
		if f.ends_with(".ogg") and not scenes.has(f.get_basename()):
			never.append(f.get_basename())
	print("scenes reached: %d %s" % [scenes.size(), str(scenes.keys())])
	print("stings raised: %d %s" % [cues.size(), str(cues.keys())])
	print("loops never reached in random play: %s" % str(never))
	print("PROBLEMS: %d" % problems)
	quit(1 if problems > 0 else 0)
	return true
