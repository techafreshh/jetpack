extends SceneTree
## Headless behavior tests for the soldier controller: config values, run,
## crouch half-height, thrust lift, fuel drain window, grounded refill window.
## Run: godot --headless --path jetpack --script res://tests/test_soldier.gd

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
	check(absf(actual - expected) <= tol, "%s (expected ~%f, got %f)" % [label, expected, actual])


func wait_physics(n: int) -> void:
	for i in n:
		await physics_frame


func wait_until_floor(soldier: CharacterBody2D, cap: int) -> bool:
	for i in cap:
		if soldier.is_on_floor():
			return true
		await physics_frame
	return soldier.is_on_floor()


func release_all() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("crouch")
	Input.action_release("fly")


func run_tests() -> void:
	await process_frame

	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2.ZERO
	var floor_shape := CollisionShape2D.new()
	var world_edge := WorldBoundaryShape2D.new()
	floor_shape.shape = world_edge
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)

	var packed := load("res://scenes/soldier.tscn") as PackedScene
	check(packed != null, "soldier.tscn loads as PackedScene")
	if packed == null:
		return
	var soldier := packed.instantiate() as CharacterBody2D
	check(soldier != null, "soldier.tscn instantiates CharacterBody2D")
	if soldier == null:
		return
	soldier.position = Vector2(0, -40)
	root.add_child(soldier)
	await process_frame
	await process_frame
	var settled := await wait_until_floor(soldier, 120)
	check(settled, "soldier settles onto floor")

	# (a) Config values on the live controller.
	check_close(float(soldier.get("fuel_burn_s")), 2.5, 0.1, "fuel_burn_s is 2.5")
	check_close(float(soldier.get("ground_refuel_mult")), 4.0, 0.5, "ground_refuel_mult is 4.0")
	var cfg := ConfigFile.new()
	check(cfg.load("res://resources/config/movement.cfg") == OK, "movement.cfg loads")
	check_close(float(cfg.get_value("movement", "fuel_burn_s", 0.0)), 2.5, 0.1, "cfg fuel_burn_s is 2.5")
	check_close(float(cfg.get_value("movement", "ground_refuel_mult", 0.0)), 4.0, 0.5, "cfg ground_refuel_mult is 4.0")

	# (b) Run: move_right for 60 ticks moves forward with speed.
	var x0: float = soldier.position.x
	soldier.velocity = Vector2.ZERO
	Input.action_press("move_right")
	await wait_physics(60)
	Input.action_release("move_right")
	check(soldier.position.x > x0 + 50.0, "run displaces forward (dx=%f)" % (soldier.position.x - x0))
	check(soldier.velocity.x > 200.0, "run reaches speed (vx=%f)" % soldier.velocity.x)
	var grounded_after_run := await wait_until_floor(soldier, 120)
	check(grounded_after_run, "soldier still grounded after run")

	# (c) Crouch halves height; release restores it.
	var body := soldier.get_node("Body") as CollisionShape2D
	var stand_h: float = (body.shape as RectangleShape2D).size.y
	Input.action_press("crouch")
	await wait_physics(5)
	check(bool(soldier.get("crouched")), "crouch sets crouched flag")
	check_close((body.shape as RectangleShape2D).size.y, stand_h * 0.5, 0.5, "crouch halves collision height")
	Input.action_release("crouch")
	await wait_physics(5)
	check(not bool(soldier.get("crouched")), "release clears crouched flag")
	check_close((body.shape as RectangleShape2D).size.y, stand_h, 0.5, "stand restores collision height")

	# (c2) Shared-scene crouch independence: two soldiers from one PackedScene stay isolated.
	var soldierB := packed.instantiate() as CharacterBody2D
	soldierB.position = Vector2(200, -40)
	root.add_child(soldierB)
	await process_frame
	await process_frame
	var bodyB := soldierB.get_node("Body") as CollisionShape2D
	check(bodyB != null, "second soldier exposes Body")
	check(body.shape != bodyB.shape, "soldiers get distinct shapes after _ready")
	check_close(float(soldier.get("_stand_h")), float(soldierB.get("_stand_h")), 0.01, "both soldiers share stand height")
	var iso_stand: float = float(soldier.get("_stand_h"))
	soldier.call("_set_crouched", true)
	check_close((body.shape as RectangleShape2D).size.y, iso_stand * 0.5, 0.5, "crouch-A halves A only")
	check_close((bodyB.shape as RectangleShape2D).size.y, iso_stand, 0.5, "crouch-A leaves B untouched")
	soldier.call("_set_crouched", false)
	check_close((body.shape as RectangleShape2D).size.y, iso_stand, 0.5, "uncrouch restores A")
	check_close((bodyB.shape as RectangleShape2D).size.y, iso_stand, 0.5, "B still at stand height")
	soldierB.queue_free()
	await process_frame

	# (d) Thrust lifts off within 30 ticks.
	soldier.set("fuel", float(soldier.get("fuel_max")))
	var y0: float = soldier.position.y
	Input.action_press("fly")
	await wait_physics(30)
	check(soldier.position.y < y0 - 10.0, "thrust lifts soldier (dy=%f)" % (soldier.position.y - y0))
	Input.action_release("fly")

	# (e) Full tank held thrust empties in 140-170 physics ticks.
	soldier.position = Vector2(0, -200)
	soldier.velocity = Vector2.ZERO
	soldier.set("fuel", float(soldier.get("fuel_max")))
	await process_frame
	Input.action_press("fly")
	var drain_ticks := 0
	while float(soldier.get("fuel")) > 0.0 and drain_ticks < 400:
		await physics_frame
		drain_ticks += 1
	Input.action_release("fly")
	check(drain_ticks >= 140 and drain_ticks <= 170, "fuel empties in 140-170 ticks (got %d)" % drain_ticks)

	# (f) Empty tank refills fully within 45 ticks grounded.
	release_all()
	soldier.position = Vector2(0, -40)
	soldier.velocity = Vector2.ZERO
	await process_frame
	var resettled := await wait_until_floor(soldier, 120)
	check(resettled, "soldier re-settles for refuel test")
	soldier.set("fuel", 0.0)
	var refill_ticks := 0
	while float(soldier.get("fuel")) < float(soldier.get("fuel_max")) and refill_ticks < 400:
		await physics_frame
		refill_ticks += 1
	check(refill_ticks <= 45, "grounded refill within 45 ticks (got %d)" % refill_ticks)

	# (g) Bare-node instantiation: soldier.gd survives with no children.
	var bare := CharacterBody2D.new()
	bare.set_script(load("res://scripts/soldier.gd"))
	root.add_child(bare)
	await process_frame
	await process_frame
	await wait_physics(5)
	check(is_instance_valid(bare), "bare soldier node stays valid")
	check(bool(bare.get("is_alive")), "bare soldier stays alive")
	check(bare.get_node_or_null("Body") == null, "bare soldier has no Body")
	check(bare.get_node_or_null("HeadCheck") == null, "bare soldier has no HeadCheck")
	check(bare.get_node_or_null("Visual") == null, "bare soldier has no Visual")
	check_close(float(bare.get("_stand_h")), 64.0, 0.01, "bare soldier keeps default stand height")
	bare.call("take_damage", 10.0)
	check_close(float(bare.get("hp")), 90.0, 0.01, "bare soldier takes damage")
	bare.call("heal", 5.0)
	check_close(float(bare.get("hp")), 95.0, 0.01, "bare soldier heals")
	bare.call("_set_crouched", true)
	check(bool(bare.get("crouched")), "bare soldier crouch flag sets without Body")
	bare.call("_set_crouched", false)
	check(not bool(bare.get("crouched")), "bare soldier crouch flag clears without Body")
	check(bool(bare.call("throw_grenade")), "bare soldier throws grenade")
	bare.queue_free()
	await process_frame

	release_all()
