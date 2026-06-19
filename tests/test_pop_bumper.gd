extends GutTest
## Test matrix entry: ACTIVE POP BUMPER (radial active kick + score, not a limp bounce).
## Owner: physics-programmer (the active kick in active_kicker._apply_kick + the solid body) +
## gameplay-programmer (the cooldown + score) + test-builder. Slice: "real pinball furniture".
##
## WHY THIS EXISTS: DESIGN must-feel #1 "active kick, not a limp bounce": a pop bumper fires the
## ball
## AWAY with authority even if the ball arrived SLOWLY. Passive restitution would let a slow ball
## crawl back out; the active impulse must give it a minimum outgoing speed, directed RADIALLY
## OUTWARD
## from the bumper center. Must-feel #2 "no machine-gun farming": one kick + score, then a cooldown
## dead time. This test asserts BOTH against the REAL instanced bodies and the ball's measured
## velocity (independent oracle) - a green suite that never measures outward velocity is a FAIL.
##
## STRUCTURE: instance the REAL PopBumper.tscn (so the solid KickerBody, its layer, and the kick
## math
## are the shipping ones) and the REAL Ball.tscn. Fire a SLOW ball at the bumper and assert it
## leaves
## FAST and OUTWARD; fire one clean hit and assert exactly one score; hold the ball against it and
## assert the cooldown bounds the score count.

const PHYSICS_TICK_S: float = 1.0 / 240.0
## Frames to let a kicked ball clearly separate from the bumper and reach a steady outgoing
## velocity.
const APPROACH_FRAMES: int = 30
## A deliberately SLOW incoming speed: the whole point is that an active kick still fires it away
## fast.
const SLOW_FIRE_SPEED: float = 8.0
## Hold window for the cooldown-farming check.
const CONTACT_HOLD_FRAMES: int = 120

const POP_BUMPER_SCENE: PackedScene = preload("res://scenes/elements/PopBumper.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/elements/Ball.tscn")

var _world: Node3D = null
var _bumper: Area3D = null
var _ball: RigidBody3D = null


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)

	_bumper = POP_BUMPER_SCENE.instantiate() as Area3D
	if _bumper.has_method("configure"):
		_bumper.configure()
	_bumper.position = Vector3.ZERO
	_world.add_child(_bumper)

	_ball = BALL_SCENE.instantiate() as RigidBody3D
	_world.add_child(_ball)
	_bumper.set_ball(_ball)
	# Zero gravity so the radial-kick direction measurement is not contaminated by the table slope.
	_ball.gravity_scale = 0.0
	await wait_frames(2)  # let _ready build the body + detector


## Place the ball up-table of the bumper and push it gently in along +Z toward the bumper center.
func _fire_slow_at_bumper() -> void:
	var start_z: float = -(TableConfig.POP_BUMPER_RADIUS + TableConfig.BALL_RADIUS + 3.0)
	_ball.position = Vector3(0.0, 0.0, start_z)
	_ball.linear_velocity = Vector3(0.0, 0.0, SLOW_FIRE_SPEED)
	_ball.angular_velocity = Vector3.ZERO
	_ball.sleeping = false


# ---- STRUCTURAL ---------------------------------------------------------------------------------

func test_pop_bumper_has_solid_body_on_static_layer() -> void:
	## The active kick still needs a SOLID body the ball bounces off (CCD-safe). active_kicker.gd
	## builds a child StaticBody3D named "KickerBody" on STATIC_OBSTACLES.
	var body: Node = _bumper.find_child("KickerBody", true, false)
	assert_not_null(
		body, "pop bumper must build a child StaticBody3D 'KickerBody' the ball bounces off"
	)
	if body != null and body is StaticBody3D:
		assert_eq(
			(body as StaticBody3D).collision_layer,
			PhysicsLayers.STATIC_OBSTACLES,
			"the KickerBody must sit on STATIC_OBSTACLES so the ball collides with it"
		)


func test_pop_bumper_detector_monitors_balls_layer() -> void:
	assert_eq(
		_bumper.collision_mask, PhysicsLayers.BALLS,
		"the pop bumper detector Area3D must monitor the BALLS layer to fire on contact"
	)


func test_pop_bumper_preserves_contract() -> void:
	assert_true(_bumper.has_signal("scored"), "pop bumper must emit scored(points)")
	assert_true(_bumper.has_signal("kicked"), "pop bumper must emit kicked(direction)")
	assert_true(_bumper.has_method("set_ball"), "pop bumper must have set_ball(ball)")


# ---- BEHAVIORAL: a SLOW ball leaves FAST and OUTWARD
# ----------------------------------------------

func test_slow_ball_leaves_fast() -> void:
	## The active-kick headline: a ball arriving at SLOW_FIRE_SPEED (8 u/s) must leave at AT LEAST
	## KICK_MIN_OUTGOING_SPEED. Passive restitution could never do this (it would leave at ~0.x * 8).
	## ORACLE: _ball.current_speed() after the kick. Speed cannot lie about an active kick.
	_fire_slow_at_bumper()
	await wait_physics_frames(APPROACH_FRAMES)

	assert_gt(
		_ball.current_speed(),
		TableConfig.KICK_MIN_OUTGOING_SPEED,
		"a slow ball must leave the pop bumper FAST (>= KICK_MIN_OUTGOING_SPEED). speed=%f, min=%f"
		% [_ball.current_speed(), TableConfig.KICK_MIN_OUTGOING_SPEED]
	)


func test_kick_is_directed_outward() -> void:
	## The ball entered along +Z (down-table side of the bumper at -Z start), so a RADIALLY OUTWARD
	## kick must send it back along -Z (away from the bumper center, toward where it came from). We
	## assert the outgoing z-velocity is negative (outward, not continuing through the bumper).
	## ORACLE: _ball.linear_velocity.z after the kick.
	_fire_slow_at_bumper()
	await wait_physics_frames(APPROACH_FRAMES)

	assert_lt(
		_ball.linear_velocity.z, 0.0,
		"a head-on contact must be kicked back OUTWARD (-z), not pushed through the bumper. vz=%f"
		% _ball.linear_velocity.z
	)


func test_kick_speed_is_capped() -> void:
	## CCD-safe cap: even after a kick the ball must not exceed KICK_MAX_OUTGOING_SPEED, so a stacked
	## kick can never push the ball past the speed the no-tunneling stress test proves safe.
	## ORACLE: _ball.current_speed() after the kick.
	_fire_slow_at_bumper()
	await wait_physics_frames(APPROACH_FRAMES)

	assert_lte(
		_ball.current_speed(),
		TableConfig.KICK_MAX_OUTGOING_SPEED + 0.5,
		"the kick must be capped at KICK_MAX_OUTGOING_SPEED (CCD-safe). speed=%f, cap=%f"
		% [_ball.current_speed(), TableConfig.KICK_MAX_OUTGOING_SPEED]
	)


# ---- BEHAVIORAL: scoring + cooldown -------------------------------------------------------------

func test_pop_bumper_scores_once_per_contact() -> void:
	watch_signals(_bumper)
	_fire_slow_at_bumper()
	await wait_physics_frames(APPROACH_FRAMES)
	assert_signal_emit_count(
		_bumper, "scored", 1, "pop bumper must score EXACTLY once per clean kick"
	)


func test_pop_bumper_cooldown_blocks_farming() -> void:
	## Hold the ball against the bumper for CONTACT_HOLD_FRAMES; the cooldown must bound the score
	## count (one kick, dead time, not a per-frame strobe). Same family as the target BUG-007 guard.
	## Max legitimate emissions over 0.5 s at KICK_COOLDOWN_S=0.25 is 2; allow 4 for solver jitter.
	## ORACLE: GUT signal emission count.
	watch_signals(_bumper)
	var contact_z: float = -(TableConfig.POP_BUMPER_RADIUS + TableConfig.BALL_RADIUS * 0.9)
	_ball.position = Vector3(0.0, 0.0, contact_z)
	_ball.linear_velocity = Vector3(0.0, 0.0, 3.0)
	_ball.sleeping = false
	await wait_physics_frames(CONTACT_HOLD_FRAMES)

	var emit_count: int = get_signal_emit_count(_bumper, "scored")
	assert_lte(
		emit_count, 4,
		"cooldown must bound pop-bumper scoring: got %d emissions in %d frames"
		% [emit_count, CONTACT_HOLD_FRAMES]
	)
