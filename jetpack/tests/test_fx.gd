extends SceneTree
## Headless behavior tests for the juice pass: tick-counted muzzle flash,
## synchronous camera shake, real-time hit-stop dip/restore, synthesized CC0
## audio with per-file license lines, and the SFX/UI bus volume round-trip.
## Run: godot --headless --path jetpack --script res://tests/test_fx.gd

var passed := 0
var failed := 0


func _initialize() -> void:
	await run_tests()
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		push_error("FAIL " + label)


func check_close(actual: float, expected: float, tol: float, label: String) -> void:
	check(absf(actual - expected) <= tol, "%s (expected ~%f, got %f)" % [label, expected, tol])


func wait_physics(n: int) -> void:
	for i in n:
		await physics_frame


func run_tests() -> void:
	await process_frame

	# (a) Muzzle flash: one AR pull shows MuzzleFlash for ticks 1-3, hides after.
	var soldier_packed := load("res://scenes/soldier.tscn") as PackedScene
	check(soldier_packed != null, "soldier.tscn loads as PackedScene")
	if soldier_packed == null:
		return
	var soldier := soldier_packed.instantiate() as CharacterBody2D
	check(soldier != null, "soldier.tscn instantiates CharacterBody2D")
	if soldier == null:
		return
	soldier.position = Vector2(0, -200)
	root.add_child(soldier)
	await process_frame
	await process_frame
	var weapon := soldier.get_node_or_null("Weapon")
	check(weapon != null, "soldier has Weapon child")
	var ranger := load("res://resources/weapons/ranger_ar.tres") as WeaponResource
	check(ranger != null, "ranger_ar.tres loads as WeaponResource")
	if weapon == null or ranger == null:
		return
	check(String(ranger.get("sfx_name")) != "", "ranger carries an sfx_name")
	weapon.call("equip", ranger)
	weapon.call("set_aim_point", Vector2(2000, -200))
	weapon.set("_cooldown", 0.0)
	check(bool(weapon.call("try_fire")), "AR try_fire succeeds")
	var flash_node := weapon.get_node_or_null("MuzzleFlash")
	check(flash_node != null, "MuzzleFlash node built under Weapon")
	check(weapon.get("muzzle_flash") != null, "weapon exposes muzzle_flash")
	check(bool(weapon.get("muzzle_flash").get("visible")), "muzzle_flash visible right after fire")
	var vis: Array = []
	for i in 5:
		await physics_frame
		vis.append(bool(weapon.get("muzzle_flash").get("visible")))
	check(vis[0], "muzzle_flash visible at tick 1")
	check(vis[1], "muzzle_flash visible at tick 2")
	check(vis[2], "muzzle_flash visible at tick 3")
	check(not vis[3], "muzzle_flash hidden at tick 4")
	check(not vis[4], "muzzle_flash hidden at tick 5")
	soldier.queue_free()
	await process_frame

	# (b) Camera shake: an AR shot in match.tscn offsets the shake camera.
	var match_packed := load("res://scenes/match.tscn") as PackedScene
	check(match_packed != null, "match.tscn loads as PackedScene")
	if match_packed == null:
		return
	var match_scene := match_packed.instantiate() as Node2D
	check(match_scene != null, "match.tscn instantiates Node2D")
	if match_scene == null:
		return
	root.add_child(match_scene)
	await process_frame
	await process_frame
	var shakers := get_nodes_in_group("camera_shake")
	check(not shakers.is_empty(), "camera_shake group non-empty in match")
	var cam: Camera2D = null
	if not shakers.is_empty():
		cam = shakers[0] as Camera2D
	check(cam != null, "shake node is a Camera2D")
	check(match_scene.get("camera_shake") != null, "match exposes camera_shake")
	var seated := match_scene.get_node_or_null("Soldier") as CharacterBody2D
	check(seated != null, "match seats a Soldier")
	if seated != null and cam != null:
		var gun := seated.get_node_or_null("Weapon")
		if gun != null:
			gun.call("set_aim_point", seated.global_position + Vector2(1500, -200))
			gun.set("_cooldown", 0.0)
			check(bool(gun.call("try_fire")), "seated AR try_fire succeeds")
			var mag := 0.0
			for i in 5:
				await physics_frame
				mag = maxf(mag, (cam as Camera2D).offset.length())
			check(mag > 0.0, "camera_shake offset magnitude >0 within 5 ticks (got %f)" % mag)
	match_scene.queue_free()
	await process_frame

	# (c) Hit-stop: a landed hit dips time_scale, then restores 1.0 in real time.
	Engine.time_scale = 1.0
	var dummy_packed := load("res://scenes/dummy.tscn") as PackedScene
	check(dummy_packed != null, "dummy.tscn loads as PackedScene")
	if dummy_packed == null:
		return
	var dummy := dummy_packed.instantiate() as StaticBody2D
	root.add_child(dummy)
	await process_frame
	await process_frame
	dummy.call("take_damage", 10.0)
	check(Engine.time_scale <= 0.3, "hit-stop dips time_scale <=0.3 (got %f)" % Engine.time_scale)
	OS.delay_msec(250)
	await process_frame
	await process_frame
	var restored := false
	for i in 120:
		if Engine.time_scale == 1.0:
			restored = true
			break
		await process_frame
	check(restored, "hit-stop restores time_scale to 1.0")
	dummy.queue_free()
	await process_frame
	Engine.time_scale = 1.0

	# (d) Audio audit: >=8 wav/ogg files, each with a CC0 line in LICENSE.md.
	var dir := DirAccess.open("res://assets/audio")
	check(dir != null, "assets/audio opens via DirAccess")
	var clips: Array[String] = []
	if dir != null:
		for f in dir.get_files():
			var lower := String(f).to_lower()
			if lower.ends_with(".wav") or lower.ends_with(".ogg"):
				clips.append(f)
	check(clips.size() >= 8, "audio holds >=8 clips (got %d)" % clips.size())
	var lic := FileAccess.open("res://assets/audio/LICENSE.md", FileAccess.READ)
	check(lic != null, "assets/audio/LICENSE.md readable")
	if lic != null:
		var text := lic.get_as_text()
		lic.close()
		for clip in clips:
			var base := String(clip).get_file()
			check(text.contains(base) and text.contains("CC0"), "LICENSE.md has a CC0 line for %s" % base)

	# (e) Bus control: SFX/UI buses exist and hold a volume round-trip.
	Sfx.ensure_buses()
	check(AudioServer.get_bus_index("SFX") >= 0, "SFX bus exists")
	check(AudioServer.get_bus_index("UI") >= 0, "UI bus exists")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("SFX")) == "Master", "SFX bus routes to Master")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("UI")) == "Master", "UI bus routes to Master")
	var audio_node: Node = load("res://scripts/audio.gd").new()
	root.add_child(audio_node)
	await process_frame
	await process_frame
	check(AudioServer.get_bus_index("Music") >= 0, "Music bus exists")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Music")) == "Master", "Music bus routes to Master")
	check(AudioServer.get_bus_index("SFX") >= 0, "SFX bus exists")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("SFX")) == "Master", "SFX bus routes to Master")
	audio_node.queue_free()
	await process_frame
	Sfx.set_bus_volume01("SFX", 0.5)
	check_close(Sfx.get_bus_volume01("SFX"), 0.5, 0.02, "SFX volume round-trips 0.5")
	Sfx.set_bus_volume01("UI", 0.25)
	check_close(Sfx.get_bus_volume01("UI"), 0.25, 0.02, "UI volume round-trips 0.25")
	Sfx.set_bus_volume01("SFX", 1.0)
	Sfx.set_bus_volume01("UI", 1.0)
	check_close(Sfx.get_bus_volume01("SFX"), 1.0, 0.01, "SFX volume restores to 1.0")

	# (f) Burst fires at blast, not at build: one-shot Burst builds idle, detonate restarts it.
	var boom_scr := load("res://scripts/fx/explosion.gd") as Script
	check(boom_scr != null, "explosion.gd loads as Script")
	if boom_scr != null:
		var boom := boom_scr.new() as Node2D
		check(boom != null, "explosion instantiates Node2D")
		if boom != null:
			boom.global_position = Vector2(5000, 5000)
			root.add_child(boom)
			var burst := boom.get_node_or_null("Burst") as CPUParticles2D
			check(burst != null, "burst node built under explosion")
			if burst != null:
				check(burst.one_shot, "burst is one-shot")
				check(not burst.emitting, "burst builds idle, fires at detonate (got emitting=true)")
				boom.call("detonate")
				check(burst.emitting, "detonate restarts burst (got emitting=false)")
			boom.queue_free()
			await process_frame
		var bare := boom_scr.new() as Node2D
		check(bare != null, "tree-less explosion instantiates Node2D")
		if bare != null:
			check(not bare.is_inside_tree(), "tree-less explosion starts outside tree")
			bare.position = Vector2(5000, 5000)
			bare.call("detonate")
			check(bare.get("_detonated") == true, "tree-less detonate marks _detonated")
			check(bare.get_node_or_null("Burst") == null, "tree-less detonate skips burst without error")
			bare.free()
