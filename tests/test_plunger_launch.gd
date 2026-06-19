extends GutTest
## Test matrix entry: PHYSICAL LAUNCH MECHANIC (lane pocket + physical plunger strike).
## Owner: test-builder + physics-programmer.
## Slice: make-the-core-interactions-physics-based.
##
## WHY THIS EXISTS: the developer reported two launch bugs in the deployed gray-box -
##   (1) the ball fell out the open bottom of the launch lane (no lane stop), and
##   (2) the plunger was fake (it set the ball's velocity in code, not a physical strike).
## These tests validate the FIX as a SYSTEM using REAL instanced bodies and a REAL physics world:
## a tilted Playfield with the actual TableGeometry (surface, walls, lane divider, and the new lane
## pocket), the shipping Plunger.tscn, and the shipping Ball.tscn. Nothing is hand-faked.
##
## INDEPENDENT ORACLE RULE: every assertion reads the REAL ball's measured position
## (ball.position) or current_speed(), never a self-reported counter. Position and speed cannot lie
## about whether the ball rested, was struck, or tunneled.
##
## TEST HOOK: headless GUT cannot hold the "launch" key across physics frames, so the plunger
## exposes test_strike_at_power(power), inert in play, like the flipper's force_energized() hook.
## We drive that hook, step physics frames, and measure the real ball.
##
## ADOPTED from prototype/physical-plunger. Not gate-passed; goes through QA + review + producer.

## Physics tick duration at 240 Hz.
const PHYSICS_TICK_S: float = 1.0 / 240.0

## How many frames to let the ball settle from the spawn before measuring its rest position. Gravity
## is strong (200) so it settles fast; 120 frames (0.5 s) is generous.
const SETTLE_FRAMES: int = 120

## How many frames to let a strike resolve: long enough that the forward stroke has finished and
## the ball has left the face into free flight, but SHORT enough the ball is still mid-lane and has
## not reached the arch (which would add bounce to the speed/position reads). The forward stroke
## covers PLUNGER_STROKE_LENGTH (2.0 u) at >= 30 u/s in <= ~16 frames; at 30 frames (0.125 s) the
## ball is clear of the face and mid-lane, well short of the arch.
const STRIKE_FRAMES: int = 30

const PLUNGER_SCENE: PackedScene = preload("res://scenes/elements/Plunger.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/elements/Ball.tscn")

var _world: Node3D = null
var _playfield: Node3D = null
var _plunger: Node = null
var _ball: RigidBody3D = null


func before_each() -> void:
	# Build a tilted Playfield exactly like table.gd (rotated TILT_DEG about X) so gravity has the
	# real down-table component the lane-fall bug depends on. Using the real tilt matters: on a
	# flat world gravity would not push the ball toward the drain and the pocket would not be tested.
	_world = Node3D.new()
	add_child_autofree(_world)

	_playfield = Node3D.new()
	_playfield.name = "Playfield"
	_playfield.rotation_degrees = Vector3(TableConfig.TILT_DEG, 0.0, 0.0)
	_world.add_child(_playfield)

	# The REAL static geometry, including the new lane pocket. This is the actual shell the ball
	# lives in; using it (not a hand-built stand-in box) is what makes "the ball does not fall out
	# the lane" meaningful. A stand-in would pass while the real pocket is broken or missing.
	TableGeometry.build(_playfield)

	# The REAL plunger. It seats its own face at PLUNGER_REST_POS.
	_plunger = PLUNGER_SCENE.instantiate()
	_plunger.name = "Plunger"
	_plunger.position = Vector3.ZERO
	_playfield.add_child(_plunger)

	# The REAL ball. ball.gd._ready() sets CCD, layers, mass, material, and parks it at BALL_START.
	_ball = BALL_SCENE.instantiate() as RigidBody3D
	_ball.name = "Ball"
	_playfield.add_child(_ball)
	_plunger.set_ball(_ball)

	_ball.reset_to_start()


# ---- Helpers -----------------------------------------------------------------------

## Reset the ball to the lane start and let it settle to rest against the plunger/pocket.
func _seat_and_settle() -> void:
	_ball.reset_to_start()
	await wait_physics_frames(SETTLE_FRAMES)


## Fire a strike at the given power, let it resolve, and return the ball's resulting speed.
func _strike_and_measure(power: float) -> float:
	await _seat_and_settle()
	_plunger.test_strike_at_power(power)
	await wait_physics_frames(STRIKE_FRAMES)
	return _ball.current_speed()


# ---- STRUCTURAL: the plunger scene has a physical face on the right layer --------------

func test_plunger_face_body_exists_on_kinematic_layer() -> void:
	## The physical plunger face must be an AnimatableBody3D on KINEMATIC_OBSTACLES so the ball
	## (BALL_COLLISION_MASK) collides with it. Find it by the agreed name "PlungerFace".
	var face: Node = _plunger.find_child("PlungerFace", true, false)
	assert_not_null(
		face,
		"plunger.gd must build a child AnimatableBody3D 'PlungerFace' on KINEMATIC_OBSTACLES"
	)
	if face != null and face is AnimatableBody3D:
		assert_eq(
			(face as AnimatableBody3D).collision_layer,
			PhysicsLayers.KINEMATIC_OBSTACLES,
			"the plunger face must sit on KINEMATIC_OBSTACLES (same layer as flippers)"
		)


func test_plunger_keeps_public_contract_signals() -> void:
	## The slice must NOT break the public contract. table.gd and tests/test_plunger.gd depend on
	## these signals exactly; changing their names is a breaking change that breaks the game flow.
	assert_true(_plunger.has_signal("power_changed"), "plunger must keep signal power_changed")
	assert_true(_plunger.has_signal("ball_launched"), "plunger must keep signal ball_launched")


func test_plunger_keeps_public_contract_methods() -> void:
	## Method contract guard: arm/disarm/set_ball/is_armed must all exist with the same names.
	assert_true(_plunger.has_method("arm"), "plunger must keep method arm()")
	assert_true(_plunger.has_method("disarm"), "plunger must keep method disarm()")
	assert_true(_plunger.has_method("set_ball"), "plunger must keep method set_ball(ball)")
	assert_true(_plunger.has_method("is_armed"), "plunger must keep method is_armed()")


func test_plunger_exposes_test_hook() -> void:
	## test_strike_at_power() is the agreed test hook (ARCHITECTURE.md 9.3), inert in play. It must
	## exist so the behavioral tests below can drive it in headless CI without synthesizing key events.
	assert_true(
		_plunger.has_method("test_strike_at_power"),
		"plunger must expose test_strike_at_power(power) for headless CI tests"
	)


# ---- BEHAVIORAL: the ball rests in the lane, does not fall out the bottom ---------------

func test_ball_rests_in_lane_and_does_not_fall_out_bottom() -> void:
	## Drop the ball at the lane start, advance physics, and assert it has NOT rolled off the open
	## lane bottom. The lane pocket (TableGeometry._build_lane_pocket) is the stop. We check the
	## ball's measured local z stayed at or above (smaller z than) the pocket face plus one ball
	## radius of tolerance, and that it stayed on the +X lane side of the divider.
	## ORACLE: the ball's measured position. Position cannot lie about falling through.
	await _seat_and_settle()

	# Ball must not have passed the pocket's up-table face by more than one ball radius.
	var max_z: float = TableConfig.LANE_POCKET_FACE_Z + TableConfig.BALL_RADIUS
	assert_lt(
		_ball.position.z,
		max_z,
		"ball fell past the lane bottom: z=%f, pocket face z=%f" % [
			_ball.position.z, TableConfig.LANE_POCKET_FACE_Z
		]
	)

	# Ball must stay on the lane side (+X) of the divider; it must not have leaked into the field.
	assert_gt(
		_ball.position.x,
		TableConfig.LANE_INNER_X - TableConfig.BALL_RADIUS,
		"ball left the lane to the -X side: x=%f, lane inner x=%f" % [
			_ball.position.x, TableConfig.LANE_INNER_X
		]
	)

	# Sanity: ball must not have fallen through the playfield surface.
	assert_gt(
		_ball.position.y,
		-TableConfig.BALL_RADIUS,
		"ball fell through the playfield surface: y=%f" % _ball.position.z
	)


# ---- BEHAVIORAL: a strike physically imparts velocity (no ball.launch() call) -----------

func test_strike_imparts_velocity_to_ball() -> void:
	## The momentum must come from the physical contact (the AnimatableBody3D face moving into the
	## ball), NOT from plunger.gd calling ball.launch(). We measure the ball's speed after the hook
	## fires and assert it rose above rest. The production path must NOT call ball.launch() for this
	## to be a real physics strike; the physics-programmer is accountable for that.
	## ORACLE: ball.current_speed() after the strike resolves, measured, not self-reported.
	var speed: float = await _strike_and_measure(0.6)
	assert_gt(
		speed,
		1.0,
		"a strike must impart real velocity to the ball from physical contact; got %f" % speed
	)


func test_full_power_outthrows_weak_strike() -> void:
	## The power->stroke speed mapping must be MEANINGFUL and monotonic: a full-power strike must
	## throw the ball harder than a weak one by a ratio of >= 1.5x (the same floor as the flipper
	## feel gate). This is the launch-skill requirement: where you release the meter matters.
	## ORACLE: ball.current_speed() for each trial.
	var weak_speed: float = await _strike_and_measure(0.05)
	var full_speed: float = await _strike_and_measure(1.0)

	assert_gt(
		full_speed,
		weak_speed,
		"full-power strike (%f) must out-throw a weak one (%f)" % [full_speed, weak_speed]
	)
	assert_gte(
		full_speed,
		1.5 * weak_speed,
		"full strike must be >= 1.5x the weak strike: full=%f, weak=%f" % [full_speed, weak_speed]
	)


func test_launched_ball_speed_lands_in_design_range() -> void:
	## A full-power strike must produce a ball speed in the design window so the ball can actually
	## clear the arch. We allow generous solver tolerance on the ceiling (1.5x MAX) because the
	## exact transfer is physics-solver-dependent. The lower bound is the hard gate: a ball too
	## slow on full power fails the launch-skill requirement.
	var full_speed: float = await _strike_and_measure(1.0)

	assert_gte(
		full_speed,
		TableConfig.LAUNCH_SPEED_MIN,
		"full-power strike must reach >= LAUNCH_SPEED_MIN (%f); got %f" % [
			TableConfig.LAUNCH_SPEED_MIN, full_speed
		]
	)
	assert_lt(
		full_speed,
		TableConfig.LAUNCH_SPEED_MAX * 1.5,
		"full-power strike speed is implausibly high (tunnel pop or bad mapping?): %f" % full_speed
	)


# ---- STRESS: a max-power strike never tunnels the face or the lane pocket ---------------

func test_max_strike_does_not_tunnel_ball_behind_plunger_or_pocket() -> void:
	## Fire the hardest possible strike 20 times and assert the ball ALWAYS ends up on the
	## up-table side of the lane pocket (it was thrown forward, not through the stop), and that it
	## never fell through the floor. A tunnel leaves the ball at z > LANE_POCKET_FACE_Z.
	## ORACLE: ball.position.z measured after each strike. Position cannot lie about tunneling.
	const ITERATIONS: int = 20
	var pocket_face_z: float = TableConfig.LANE_POCKET_FACE_Z
	for i in range(ITERATIONS):
		var speed: float = await _strike_and_measure(1.0)

		# Ball must not have tunneled past the lane pocket stop.
		assert_lt(
			_ball.position.z,
			pocket_face_z + TableConfig.BALL_RADIUS,
			"iter %d: ball tunneled past the lane pocket z=%f, pocket=%f, speed=%f" % [
				i, _ball.position.z, pocket_face_z, speed
			]
		)

		# Ball must have moved up-table from its starting position (the strike connected).
		assert_lt(
			_ball.position.z,
			TableConfig.BALL_START.z + TableConfig.BALL_RADIUS,
			"iter %d: ball was not thrown up-table by a full strike. z=%f, start z=%f" % [
				i, _ball.position.z, TableConfig.BALL_START.z
			]
		)

		# Ball must not have fallen through the surface (basic solver sanity).
		assert_gt(
			_ball.position.y,
			-TableConfig.BALL_RADIUS * 2.0,
			"iter %d: ball dropped through the surface. y=%f" % [i, _ball.position.y]
		)
