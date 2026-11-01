extends SceneTree
## Headless verification for the grey-box arena and match host: both scenes
## load, the collider count satisfies the >=10 gate, and a 600-tick sim keeps
## the Spawn0 soldier above the kill-plane (y=2000).
## Run: godot --headless --path jetpack --script res://tests/test_arena.gd

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


func wait_physics(n: int) -> void:
	for i in n:
		await physics_frame


func run_tests() -> void:
	await process_frame

	var grey_packed := load("res://scenes/arena/greybox.tscn") as PackedScene
	check(grey_packed != null, "greybox.tscn loads as PackedScene")
	var match_packed := load("res://scenes/match.tscn") as PackedScene
	check(match_packed != null, "match.tscn loads as PackedScene")
	if grey_packed == null or match_packed == null:
		return

	var grey := grey_packed.instantiate() as Node2D
	check(grey != null, "greybox instantiates Node2D")
	if grey == null:
		return
	root.add_child(grey)
	await process_frame

	var bodies := grey.find_children("*", "StaticBody2D", true, false)
	check(bodies.size() >= 10, "greybox has >=10 StaticBody2D (got %d)" % bodies.size())
	check(grey.get_node_or_null("Spawn0") != null, "Spawn0 marker exists")

	var tower_wall := grey.get_node_or_null("TowerWall") as StaticBody2D
	check(tower_wall != null, "TowerWall exists for east-steps check")
	var tower_cap := grey.get_node_or_null("TowerCap") as StaticBody2D
	check(tower_cap != null, "TowerCap exists for east-steps check")
	if tower_wall != null:
		check(absf((tower_wall as Node2D).position.x - 2624.0) <= 1.0, "TowerWall x is 2624 mirror axis (got %f)" % (tower_wall as Node2D).position.x)
		var wall_x := (tower_wall as Node2D).position.x
		var west_names: Array = ["TowerStep0", "TowerStep1", "TowerStep2", "TowerStep3"]
		var east_names: Array = ["TowerStepE0", "TowerStepE1", "TowerStepE2", "TowerStepE3"]
		var expect_y: Array = [280.0, 160.0, 40.0, -80.0]
		var expect_gap: Array = [244.0, 184.0, 124.0, 64.0]
		var east_steps: Array = []
		for i in 4:
			var w := grey.get_node_or_null(west_names[i]) as StaticBody2D
			var e := grey.get_node_or_null(east_names[i]) as StaticBody2D
			check(w != null, "%s exists for mirror check" % west_names[i])
			check(e != null, "%s exists east of TowerWall" % east_names[i])
			if e == null:
				continue
			east_steps.append(e)
			check(e is StaticBody2D, "%s is StaticBody2D" % east_names[i])
			var epos := (e as Node2D).position
			check(epos.x > wall_x + 24.0, "%s center sits east of wall face (x=%f wall=%f)" % [east_names[i], epos.x, wall_x])
			if i < 3:
				check(epos.x - 80.0 > wall_x + 24.0, "%s fully east of wall face (left=%f face=%f)" % [east_names[i], epos.x - 80.0, wall_x + 24.0])
			else:
				check(epos.x - 80.0 < wall_x + 24.0, "%s top step overlaps wall like west Step3 (left=%f face=%f)" % [east_names[i], epos.x - 80.0, wall_x + 24.0])
			check(absf(epos.y - float(expect_y[i])) <= 1.0, "%s matches west height y=%f (got %f)" % [east_names[i], float(expect_y[i]), epos.y])
			if w != null:
				var wpos := (w as Node2D).position
				check(absf((epos.x - wall_x) - (wall_x - wpos.x)) <= 1.0, "%s mirrors %s across x=2624 (e=%f w=%f)" % [east_names[i], west_names[i], epos.x, wpos.x])
				check(absf((epos.x - wall_x) - float(expect_gap[i])) <= 1.0, "%s offset from wall is %f (got %f)" % [east_names[i], float(expect_gap[i]), epos.x - wall_x])
				check(absf(wpos.y - epos.y) <= 1.0, "%s y matches %s y (%f vs %f)" % [east_names[i], west_names[i], epos.y, wpos.y])
			var ecol := e.get_node_or_null("Collision") as CollisionShape2D
			check(ecol != null and ecol.shape is RectangleShape2D, "%s has RectangleShape2D collision" % east_names[i])
			if ecol != null and ecol.shape is RectangleShape2D:
				var esize := (ecol.shape as RectangleShape2D).size
				check(absf(esize.x - 160.0) <= 1.0 and absf(esize.y - 24.0) <= 1.0, "%s collision is 160x24 (got %s)" % [east_names[i], str(esize)])
				if w != null:
					var wcol := w.get_node_or_null("Collision") as CollisionShape2D
					if wcol != null and wcol.shape is RectangleShape2D:
						var wsize := (wcol.shape as RectangleShape2D).size
						check(absf(esize.x - wsize.x) <= 1.0 and absf(esize.y - wsize.y) <= 1.0, "%s collision matches %s size" % [east_names[i], west_names[i]])
		for i in range(1, east_steps.size()):
			var prev := (east_steps[i - 1] as Node2D).position
			var cur := (east_steps[i] as Node2D).position
			check(absf((prev.y - cur.y) - 120.0) <= 1.0, "east rise %s->%s is 120px (got %f)" % [east_names[i - 1], east_names[i], prev.y - cur.y])
			var overlap := minf(prev.x + 80.0, cur.x + 80.0) - maxf(prev.x - 80.0, cur.x - 80.0)
			check(overlap >= 20.0, "east steps %s/%s overlap >=20px in x (got %f)" % [east_names[i - 1], east_names[i], overlap])
		if tower_cap != null and east_steps.size() == 4:
			var cap_pos := (tower_cap as Node2D).position
			var cap_col := tower_cap.get_node_or_null("Collision") as CollisionShape2D
			var cap_h := 24.0
			if cap_col != null and cap_col.shape is RectangleShape2D:
				cap_h = (cap_col.shape as RectangleShape2D).size.y
			var cap_top := cap_pos.y - cap_h * 0.5
			var e3_top := (east_steps[3] as Node2D).position.y - 12.0
			check(e3_top > cap_top and (e3_top - cap_top) <= 100.0, "TowerStepE3 top within 100px below TowerCap top (e3=%f cap=%f)" % [e3_top, cap_top])
			check(cap_col != null and cap_col.shape is RectangleShape2D, "TowerCap has RectangleShape2D collision")
			if cap_col != null and cap_col.shape is RectangleShape2D:
				var cap_size := (cap_col.shape as RectangleShape2D).size
				check(absf(cap_size.x - 160.0) <= 1.0 and absf(cap_size.y - 24.0) <= 1.0, "TowerCap collision is 160x24 (got %s)" % str(cap_size))
				check(absf(cap_pos.x - wall_x) <= 1.0, "TowerCap centered on tower axis (cap x=%f wall=%f)" % [cap_pos.x, wall_x])
				var wall_top := (tower_wall as Node2D).position.y - 280.0
				var cap_bottom := cap_pos.y + cap_size.y * 0.5
				check(absf(cap_bottom - wall_top) <= 1.0, "TowerCap bottom stacked on TowerWall top (bottom=%f top=%f)" % [cap_bottom, wall_top])
				var cap_left := cap_pos.x - cap_size.x * 0.5
				var cap_right := cap_pos.x + cap_size.x * 0.5
				check(absf(cap_left - (wall_x - 80.0)) <= 1.0, "TowerCap left flush with 160 step width (left=%f expect=%f)" % [cap_left, wall_x - 80.0])
				check(absf(cap_right - (wall_x + 80.0)) <= 1.0, "TowerCap right flush with 160 step width (right=%f expect=%f)" % [cap_right, wall_x + 80.0])
			var cap_vis := tower_cap.get_node_or_null("Visual") as Polygon2D
			check(cap_vis != null, "TowerCap Visual exists for flush check")
			if cap_vis != null:
				var min_x := INF
				var max_x := -INF
				for p in cap_vis.polygon:
					min_x = minf(min_x, p.x)
					max_x = maxf(max_x, p.x)
				check(absf(max_x - 80.0) <= 1.0 and absf(min_x + 80.0) <= 1.0, "TowerCap visual is +-80 flush (min=%f max=%f)" % [min_x, max_x])

	var ceiling := grey.get_node_or_null("Ceiling")
	check(ceiling != null, "Ceiling node exists")
	check(ceiling is StaticBody2D, "Ceiling is StaticBody2D")
	var wall_l := grey.get_node_or_null("WallL") as StaticBody2D
	var wall_r := grey.get_node_or_null("WallR") as StaticBody2D
	check(wall_l != null, "WallL exists for ceiling span check")
	check(wall_r != null, "WallR exists for ceiling span check")
	if ceiling is StaticBody2D and wall_l != null and wall_r != null:
		var ceil_col := ceiling.get_node_or_null("Collision") as CollisionShape2D
		var wall_l_col := wall_l.get_node_or_null("Collision") as CollisionShape2D
		var wall_r_col := wall_r.get_node_or_null("Collision") as CollisionShape2D
		check(ceil_col != null and ceil_col.shape is RectangleShape2D, "Ceiling has RectangleShape2D collision")
		if ceil_col != null and ceil_col.shape is RectangleShape2D and wall_l_col != null and wall_l_col.shape is RectangleShape2D and wall_r_col != null and wall_r_col.shape is RectangleShape2D:
			var ceil_size := (ceil_col.shape as RectangleShape2D).size
			var ceil_pos := (ceiling as Node2D).position
			var wl_size := (wall_l_col.shape as RectangleShape2D).size
			var wr_size := (wall_r_col.shape as RectangleShape2D).size
			var wl_pos := (wall_l as Node2D).position
			var wr_pos := (wall_r as Node2D).position
			var ceil_left := ceil_pos.x - ceil_size.x * 0.5
			var ceil_right := ceil_pos.x + ceil_size.x * 0.5
			var ceil_bottom := ceil_pos.y + ceil_size.y * 0.5
			var wall_l_outer := wl_pos.x - wl_size.x * 0.5
			var wall_r_outer := wr_pos.x + wr_size.x * 0.5
			var wall_top := wl_pos.y - wl_size.y * 0.5
			check(ceil_left <= wall_l_outer + 1.0, "Ceiling spans to WallL outer face (left=%f outer=%f)" % [ceil_left, wall_l_outer])
			check(ceil_right >= wall_r_outer - 1.0, "Ceiling spans to WallR outer face (right=%f outer=%f)" % [ceil_right, wall_r_outer])
			check(absf(ceil_bottom - wall_top) <= 40.0, "Ceiling bottom flush with wall tops (bottom=%f top=%f)" % [ceil_bottom, wall_top])
			check(ceil_size.x >= wall_r_outer - wall_l_outer, "Ceiling covers wall-to-wall width")

	var gap_names: Array = ["FloorGap0", "FloorGap1", "FloorGap2"]
	var gap_centers: Array = [460.0, 1260.0, 2260.0]
	var gap_west: Array = [400.0, 1200.0, 2200.0]
	var gap_east: Array = [520.0, 1320.0, 2320.0]
	for i in 3:
		var gap := grey.get_node_or_null(gap_names[i]) as StaticBody2D
		check(gap != null, "%s exists closing floor gap" % gap_names[i])
		if gap == null:
			continue
		check(gap is StaticBody2D, "%s is StaticBody2D" % gap_names[i])
		var gpos := (gap as Node2D).position
		check(absf(gpos.x - float(gap_centers[i])) <= 1.0, "%s center x is %f (got %f)" % [gap_names[i], float(gap_centers[i]), gpos.x])
		check(absf(gpos.y - 440.0) <= 1.0, "%s center y is 440 (got %f)" % [gap_names[i], gpos.y])
		var gcol := gap.get_node_or_null("Collision") as CollisionShape2D
		check(gcol != null and gcol.shape is RectangleShape2D, "%s has RectangleShape2D collision" % gap_names[i])
		if gcol != null and gcol.shape is RectangleShape2D:
			var gsize := (gcol.shape as RectangleShape2D).size
			check(absf(gsize.x - 120.0) <= 1.0 and absf(gsize.y - 80.0) <= 1.0, "%s collision is 120x80 (got %s)" % [gap_names[i], str(gsize)])
			var gtop := gpos.y - gsize.y * 0.5
			check(absf(gtop - 400.0) <= 1.0, "%s top face flush at y=400 (got %f)" % [gap_names[i], gtop])
			var gleft := gpos.x - gsize.x * 0.5
			var gright := gpos.x + gsize.x * 0.5
			check(absf(gleft - float(gap_west[i])) <= 1.0, "%s left edge spans gap west %f (got %f)" % [gap_names[i], float(gap_west[i]), gleft])
			check(absf(gright - float(gap_east[i])) <= 1.0, "%s right edge spans gap east %f (got %f)" % [gap_names[i], float(gap_east[i]), gright])

	var bunker_blocks: Array = ["BunkerW", "BunkerE"]
	var bunker_caps: Array = ["BunkerWCap", "BunkerECap"]
	for i in 2:
		var blk := grey.get_node_or_null(bunker_blocks[i]) as StaticBody2D
		var cap := grey.get_node_or_null(bunker_caps[i]) as StaticBody2D
		check(blk != null, "%s exists for cap-flush check" % bunker_blocks[i])
		check(cap != null, "%s exists for cap-flush check" % bunker_caps[i])
		if blk == null or cap == null:
			continue
		var blk_col := blk.get_node_or_null("Collision") as CollisionShape2D
		var cap_col := cap.get_node_or_null("Collision") as CollisionShape2D
		check(cap_col != null and cap_col.shape is RectangleShape2D, "%s has RectangleShape2D collision" % bunker_caps[i])
		if blk_col == null or not (blk_col.shape is RectangleShape2D) or cap_col == null or not (cap_col.shape is RectangleShape2D):
			continue
		var blk_size := (blk_col.shape as RectangleShape2D).size
		var cap_size := (cap_col.shape as RectangleShape2D).size
		check(absf(cap_size.x - 160.0) <= 1.0 and absf(cap_size.y - 24.0) <= 1.0, "%s collision is 160x24 (got %s)" % [bunker_caps[i], str(cap_size)])
		var blk_pos := (blk as Node2D).position
		var cap_pos := (cap as Node2D).position
		check(absf(cap_pos.x - blk_pos.x) <= 1.0, "%s centered on %s (cap x=%f block x=%f)" % [bunker_caps[i], bunker_blocks[i], cap_pos.x, blk_pos.x])
		var cap_left := cap_pos.x - cap_size.x * 0.5
		var cap_right := cap_pos.x + cap_size.x * 0.5
		var blk_left := blk_pos.x - blk_size.x * 0.5
		var blk_right := blk_pos.x + blk_size.x * 0.5
		check(absf(cap_left - blk_left) <= 1.0, "%s left flush with %s left (cap=%f block=%f)" % [bunker_caps[i], bunker_blocks[i], cap_left, blk_left])
		check(absf(cap_right - blk_right) <= 1.0, "%s right flush with %s right (cap=%f block=%f)" % [bunker_caps[i], bunker_blocks[i], cap_right, blk_right])
		var cap_bottom := cap_pos.y + cap_size.y * 0.5
		var blk_top := blk_pos.y - blk_size.y * 0.5
		check(absf(cap_bottom - blk_top) <= 1.0, "%s bottom stacked on %s top (bottom=%f top=%f)" % [bunker_caps[i], bunker_blocks[i], cap_bottom, blk_top])

	var fa := FileAccess.open("res://scenes/arena/greybox.tscn", FileAccess.READ)
	if fa != null:
		var text := fa.get_as_text()
		fa.close()
		var n := text.count("StaticBody2D")
		check(n >= 10, "greybox.tscn mentions StaticBody2D >=10 times (got %d)" % n)
	else:
		check(false, "greybox.tscn readable via FileAccess")

	# Sim phase uses the match-owned arena only: detach the static-phase
	# greybox so StaticBody2D instances are not doubled at the same origin.
	root.remove_child(grey)
	grey.queue_free()
	await process_frame
	await physics_frame

	var match_inst := match_packed.instantiate() as Node2D
	check(match_inst != null, "match instantiates Node2D")
	if match_inst == null:
		return
	root.add_child(match_inst)
	await process_frame
	await process_frame

	# Rebind arena reads to the live sim arena the soldier collides with.
	var arena := match_inst.get_node_or_null("Greybox") as Node2D
	check(arena != null, "match Greybox present for sim")
	if arena == null:
		return
	check(root.find_children("Greybox", "Node2D", true, false).size() == 1, "single Greybox arena during sim (got %d)" % root.find_children("Greybox", "Node2D", true, false).size())
	var sim_bodies := root.find_children("*", "StaticBody2D", true, false).size()
	var arena_bodies := arena.find_children("*", "StaticBody2D", true, false).size()
	check(sim_bodies == arena_bodies, "no doubled static bodies during sim (root=%d arena=%d)" % [sim_bodies, arena_bodies])
	var ceilings := root.find_children("Ceiling", "StaticBody2D", true, false)
	check(ceilings.size() == 1, "single Ceiling body during sim (got %d)" % ceilings.size())

	var soldier := match_inst.get_node_or_null("Soldier") as CharacterBody2D
	check(soldier != null, "match contains Soldier")
	if soldier == null:
		return

	var max_y: float = soldier.position.y
	var ticks := 600
	for i in ticks:
		await physics_frame
		max_y = maxf(max_y, soldier.position.y)
	check(max_y < 2000.0, "soldier stays above kill-plane (max y=%f)" % max_y)
	check(soldier.is_on_floor(), "soldier rests on floor after 600 ticks")

	# Ceiling-bounded climb: sustained thrust must stop at the ceiling.
	var ceil_node := arena.get_node_or_null("Ceiling") as StaticBody2D
	var ceil_collision: CollisionShape2D = null
	if ceil_node != null:
		ceil_collision = ceil_node.get_node_or_null("Collision") as CollisionShape2D
	var ceil_bottom := -1600.0
	if ceil_collision != null and ceil_collision.shape is RectangleShape2D:
		ceil_bottom = ceil_node.position.y + (ceil_collision.shape as RectangleShape2D).size.y * 0.5
	var soldier_body := soldier.get_node_or_null("Body") as CollisionShape2D
	check(soldier_body != null and soldier_body.shape is RectangleShape2D, "Soldier body shape readable for ceiling check")
	var soldier_h := 64.0
	if soldier_body != null and soldier_body.shape is RectangleShape2D:
		soldier_h = (soldier_body.shape as RectangleShape2D).size.y
	soldier.position = Vector2(1200, -1000)
	soldier.velocity = Vector2.ZERO
	await process_frame
	await physics_frame
	var min_y: float = soldier.position.y
	var touched_ceiling := soldier.is_on_ceiling()
	Input.action_press("fly")
	for i in 600:
		soldier.set("fuel", float(soldier.get("fuel_max")))
		await physics_frame
		min_y = minf(min_y, soldier.position.y)
		if soldier.is_on_ceiling():
			touched_ceiling = true
	Input.action_release("fly")
	check(touched_ceiling, "sustained thrust contacts ceiling (is_on_ceiling)")
	check(min_y >= ceil_bottom + soldier_h - 100.0, "climb stopped by ceiling (min y=%f floor=%f)" % [min_y, ceil_bottom + soldier_h - 100.0])

	# Floor-gap run crossings: each filler restores walkable continuity.
	var run_starts: Array = [300.0, 1100.0, 2100.0]
	var run_targets: Array = [540.0, 1340.0, 2340.0]
	for i in 3:
		soldier.position = Vector2(float(run_starts[i]), 360.0)
		soldier.velocity = Vector2.ZERO
		Input.action_release("fly")
		await process_frame
		await physics_frame
		for s in 60:
			if soldier.is_on_floor():
				break
			await physics_frame
		Input.action_press("move_right")
		var lo_y: float = soldier.position.y
		var hi_y: float = soldier.position.y
		for t in 180:
			await physics_frame
			lo_y = minf(lo_y, soldier.position.y)
			hi_y = maxf(hi_y, soldier.position.y)
		Input.action_release("move_right")
		for s in 10:
			await physics_frame
		check(soldier.position.x > float(run_targets[i]), "run crosses gap %d past east edge (x=%f target=%f)" % [i, soldier.position.x, float(run_targets[i])])
		check(lo_y >= 360.0 and hi_y <= 440.0, "run over gap %d stays on floor-top y in [360,440] (lo=%f hi=%f)" % [i, lo_y, hi_y])
		check(soldier.is_on_floor(), "soldier on floor after gap %d run crossing" % i)

	# Flight hop over the middle gap still works and gains height.
	soldier.position = Vector2(1100.0, 360.0)
	soldier.velocity = Vector2.ZERO
	await process_frame
	await physics_frame
	var hop_start_y: float = soldier.position.y
	var hop_min_y: float = soldier.position.y
	Input.action_press("fly")
	Input.action_press("move_right")
	for t in 180:
		soldier.set("fuel", float(soldier.get("fuel_max")))
		await physics_frame
		hop_min_y = minf(hop_min_y, soldier.position.y)
	Input.action_release("fly")
	Input.action_release("move_right")
	check(soldier.position.x > 1340.0, "flight hop crosses middle gap (x=%f)" % soldier.position.x)
	check(hop_min_y <= hop_start_y - 20.0, "flight hop gains height over gap (min y=%f start=%f)" % [hop_min_y, hop_start_y])

	# BunkerW still blocks pure run, so flight keeps meaning for tuning.
	soldier.position = Vector2(700.0, 360.0)
	soldier.velocity = Vector2.ZERO
	Input.action_release("fly")
	await process_frame
	await physics_frame
	Input.action_press("move_right")
	var bunker_max_x: float = soldier.position.x
	for t in 300:
		await physics_frame
		bunker_max_x = maxf(bunker_max_x, soldier.position.x)
	Input.action_release("move_right")
	check(bunker_max_x < 980.0, "BunkerW blocks pure run (max x=%f)" % bunker_max_x)
