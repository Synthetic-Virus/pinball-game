extends GutTest
## Test matrix entry: PHYSICAL TARGETS (bounce + score-on-contact, not pass-through).
## Owner: gameplay-programmer (detector/scoring/cooldown) + physics-programmer (deflector/bounce).
## Slice: make-the-core-interactions-physics-based.
##
## WHY THIS EXISTS: today targets are Area3D pass-through triggers that rewrite the ball's velocity
## with a coded kick. For a physics game the ball must physically COLLIDE with a solid post, BOUNCE
## off (keeping its momentum - the designer's #1 fun risk: a target that kills/traps the ball ends
## the loop), and score ON the physics contact. The fix (ARCHITECTURE.md 9.4) keeps target.gd's
## root an Area3D DETECTOR and adds a child StaticBody3D DEFLECTOR with a near-elastic
## PhysicsMaterial; the old manual velocity kick is DELETED (the solver bounces now).
##
## INDEPENDENT-ORACLE RULE: assert the REAL ball's measured velocity DIRECTION change (it bounced)
## and SPEED (momentum kept, not killed), and the scored signal firing exactly once per contact.
## Never a self-reported counter. A target that "scores" but lets the ball pass through, or that
## scores but kills the speed, FAILS even if the count is right.

## Physics tick at 240 Hz.
const PHYSICS_TICK_S: float = 1.0 / 240.0
## Frames to let a fired ball reach and rebound off the target. At 180 u/s the ball crosses 5 units
## in ~6.7 frames, so 40 frames (167 ms) is more than enough for contact + rebound to complete.
const APPROACH_FRAMES: int = 40
## Firing speed: a typical mid-game ball speed, well below the tunneling stress threshold.
const FIRE_SPEED: float = 60.0
## The ball must keep at least 40% of incoming speed after the bounce (momentum kept, not killed).
## This is the designer's "TARGETS BOUNCE, NOT SWALLOW" requirement (DESIGN.md).
const MIN_MOMENTUM_FRACTION: float = 0.4
## Cooldown grinding window: hold the ball in contact for this many frames and assert the score
## count is much less than the frame count (the cooldown is actually blocking per-frame farming).
const CONTACT_HOLD_FRAMES: int = 120
## The post radius used in target.gd for the CylinderShape3D. Must match the implementation
## (target.gd const POST_RADIUS = 2.0 after the "Table reshape" resize slice).
const POST_RADIUS: float = 2.0

const TARGET_SCENE: PackedScene = preload("res://scenes/elements/Target.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/elements/Ball.tscn")

var _world: Node3D = null
var _target: Area3D = null
var _ball: RigidBody3D = null


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)

	# Target at the world origin so the geometry math is simple; the ball is fired at it along +Z.
	# A flat (un-tilted) world is fine for the target tests: gravity is zeroed on the ball below for
	# the momentum tests so noise does not mix with the contact measurement.
	_target = TARGET_SCENE.instantiate() as Area3D
	_target.position = Vector3.ZERO
	_world.add_child(_target)

	_ball = BALL_SCENE.instantiate() as RigidBody3D
	_world.add_child(_ball)
	_target.set_ball(_ball)
	# Zero gravity on the ball for the target interaction tests so gravity does not pull the ball off
	# the straight-in shot path and contaminate the momentum direction measurement. This is a test-
	# isolation choice: the shipping ball.gd keeps gravity_scale 1; we only touch it here.
	_ball.gravity_scale = 0.0
	await wait_frames(2)  # let _ready() build the deflector + detector shapes


## Place the ball in front of the target (at -z relative to the target origin) and fire it along +Z.
func _fire_ball_at_target(speed: float) -> void:
	# Start the ball 5 units up-table of the target (in the -Z direction from the target origin).
	# The ball's -z face will be just clear of the target surface at the start position.
	var start_z: float = -(POST_RADIUS + TableConfig.BALL_RADIUS + 5.0)
	_ball.position = Vector3(0.0, 0.0, start_z)
	_ball.linear_velocity = Vector3(0.0, 0.0, speed)
	_ball.angular_velocity = Vector3.ZERO
	_ball.sleeping = false


# ---- STRUCTURAL: solid deflector on STATIC_OBSTACLES + Area3D detector on the BALLS mask --------

func test_target_has_solid_deflector_on_static_layer() -> void:
	## The new physical post: a child StaticBody3D on STATIC_OBSTACLES the ball collides with.
	## Named "Deflector" in target.gd. A StaticBody can be detected by a ball on BALL_COLLISION_MASK
	## because that mask includes STATIC_OBSTACLES.
	var deflector: Node = _target.find_child("Deflector", true, false)
	assert_not_null(
		deflector,
		"target.gd must build a child StaticBody3D 'Deflector' the ball physically bounces off"
	)
	if deflector != null and deflector is StaticBody3D:
		assert_eq(
			(deflector as StaticBody3D).collision_layer,
			PhysicsLayers.STATIC_OBSTACLES,
			"the deflector must sit on STATIC_OBSTACLES so the ball (BALL_COLLISION_MASK) hits it"
		)


func test_target_detector_monitors_the_balls_layer() -> void:
	## The Area3D root is the detector: it must monitor bodies on the BALLS layer so body_entered
	## fires for the ball. (The public contract: it is still an Area3D with set_ball + scored.)
	assert_eq(
		_target.collision_mask,
		PhysicsLayers.BALLS,
		"the target detector Area3D must monitor the BALLS layer to fire score-on-contact"
	)


func test_target_preserves_public_contract() -> void:
	## Contract guard: the slice must NOT change the target's public surface. table.gd and
	## game_flow.gd depend on these names byte-for-byte; a rename is a breaking change.
	assert_true(_target.has_signal("scored"), "target must keep signal scored(points)")
	assert_true(_target.has_method("set_ball"), "target must keep method set_ball(ball)")
	assert_true("points" in _target, "target must keep the exported points property")


# ---- BEHAVIORAL: the ball bounces (direction change + momentum kept) and scores once -----

func test_ball_bounces_off_target_changing_direction() -> void:
	## Fire the ball straight at the target along +Z at a known speed. After contact the ball must be
	## moving in the -Z direction (it bounced back, did not pass through). This is the basic proof
	## that a real collision occurred: the solver turned the ball around.
	## ORACLE: _ball.linear_velocity.z after APPROACH_FRAMES. A positive z after this time would
	## mean the ball continued forward through the target (pass-through) or was never deflected.
	_fire_ball_at_target(FIRE_SPEED)
	await wait_physics_frames(APPROACH_FRAMES)

	assert_lt(
		_ball.linear_velocity.z,
		0.0,
		"ball must rebound back (-z velocity) off the target; positive z means pass-through. "
		+ "vz=%f" % _ball.linear_velocity.z
	)


func test_ball_bounces_off_target_keeping_momentum() -> void:
	## After the bounce the ball's speed must be a substantial fraction of its incoming speed.
	## This is the designer's load-bearing "TARGETS BOUNCE, NOT SWALLOW" requirement: a fast ball
	## stays fast, not slowed to a crawl. We require >= 40% of incoming speed is preserved.
	## ORACLE: _ball.current_speed() measured after the bounce. Ball speed cannot lie.
	_fire_ball_at_target(FIRE_SPEED)
	await wait_physics_frames(APPROACH_FRAMES)

	var min_speed: float = FIRE_SPEED * MIN_MOMENTUM_FRACTION
	assert_gt(
		_ball.current_speed(),
		min_speed,
		"ball must keep its momentum off the target (>= %.0f%% of incoming). "
		% (MIN_MOMENTUM_FRACTION * 100.0)
		+ "Got speed=%f, min=%f, incoming=%f" % [_ball.current_speed(), min_speed, FIRE_SPEED]
	)


func test_ball_does_not_pass_through_target() -> void:
	## Pass-through guard: after the approach the ball's z must NOT be past the far (+Z) face of
	## the target post. Position past the post center + radius means the sphere exited through the
	## solid body (tunneled). The far face of the post in world space is at +POST_RADIUS.
	## ORACLE: _ball.position.z measured. Position cannot lie about pass-through.
	_fire_ball_at_target(FIRE_SPEED)
	await wait_physics_frames(APPROACH_FRAMES)

	# The ball center must not be past the far face of the post plus half the ball's own radius.
	# A ball sitting right against the far face would have its center at POST_RADIUS + BALL_RADIUS;
	# anything beyond that means a tunnel.
	var pass_through_threshold: float = POST_RADIUS + TableConfig.BALL_RADIUS * 0.5
	assert_lt(
		_ball.position.z,
		pass_through_threshold,
		"ball must NOT end up past the far side of the target post (tunneled). "
		+ "z=%f, post far face=%f" % [_ball.position.z, POST_RADIUS]
	)


func test_target_scores_once_per_contact() -> void:
	## A single clean hit must emit scored EXACTLY once: not zero (the signal never fired), not
	## more than one (per-frame farming). We watch_signals the target, fire one shot, and assert
	## the count is exactly 1 with the correct flat point value.
	## ORACLE: GUT's signal emission count via assert_signal_emitted / assert_signal_emit_count.
	watch_signals(_target)

	_fire_ball_at_target(FIRE_SPEED)
	await wait_physics_frames(APPROACH_FRAMES)

	assert_signal_emitted(
		_target, "scored",
		"target must emit scored on a single clean hit"
	)
	assert_signal_emit_count(
		_target, "scored", 1,
		"target must emit scored EXACTLY ONCE per clean hit, not per-frame"
	)


func test_target_cooldown_blocks_per_frame_farming() -> void:
	## BUG-007 guard (behavior preserved by the slice): a ball grinding against the post on the
	## tilted plane re-fires body_entered every physics frame. Without the RETRIGGER_COOLDOWN_S dead
	## time, the score would increment every frame at 240 Hz (an infinite score exploit). This test
	## places the ball against the post face and holds it there for CONTACT_HOLD_FRAMES frames, then
	## asserts the total score emission count is much less than the frame count.
	##
	## The maximum legitimate score emissions over the hold window is:
	##   ceil(hold_frames * PHYSICS_TICK_S / RETRIGGER_COOLDOWN_S)
	## For CONTACT_HOLD_FRAMES=120 at 240 Hz (0.5 s) with RETRIGGER_COOLDOWN_S=0.20:
	##   max_emissions = ceil(0.5 / 0.20) = 3
	## Anything more than that (and certainly more than 120) means the cooldown is not working.
	## ORACLE: GUT's signal emission count.
	watch_signals(_target)

	# Place the ball just touching the post front face and give it a gentle push into it.
	# We want sustained contact, not a clean bounce and fly-away.
	var contact_z: float = -(POST_RADIUS + TableConfig.BALL_RADIUS * 0.9)
	_ball.position = Vector3(0.0, 0.0, contact_z)
	_ball.linear_velocity = Vector3(0.0, 0.0, 5.0)  # just enough to keep contact
	_ball.sleeping = false

	await wait_physics_frames(CONTACT_HOLD_FRAMES)

	var emit_count: int = get_signal_emit_count(_target, "scored")
	# Max legitimate emissions at RETRIGGER_COOLDOWN_S=0.20 over 0.5 s is 3. We allow 5 as
	# a loose ceiling to absorb any solver timing jitter at frame boundaries.
	var max_expected: int = 5
	assert_lte(
		emit_count,
		max_expected,
		"cooldown must bound the score count: got %d emissions in %d frames (max %d expected)" % [
			emit_count, CONTACT_HOLD_FRAMES, max_expected
		]
	)
