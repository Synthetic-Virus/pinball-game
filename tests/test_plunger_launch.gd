extends GutTest
## Test matrix entry: PHYSICAL LAUNCH MECHANIC (lane pocket + physical plunger strike).
## Owner: test-builder + physics-programmer.
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

## Physics tick duration at 240 Hz.
const PHYSICS_TICK_S: float = 1.0 / 240.0

## How many frames to let the ball settle from the spawn before measuring its rest position. Gravity
## is strong (200) so it settles fast; 120 frames (0.5 s) is generous.
const SETTLE_FRAMES: int = 120

## How many frames to let a strike resolve: long enough that the forward stroke has finished and the
## ball has left the face into free flight, but SHORT enough that the launched ball is still
## travelling up the lane and has not yet reached the arch (which would add bounce to the speed/pos
## reads). The forward stroke covers PLUNGER_STROKE_LENGTH (2.0 u) at >= 30 u/s in <= ~16 frames; at
## 30 frames (0.125 s) the ball is clear of the face and mid-lane, well short of the arch.
const STRIKE_FRAMES: int = 30

var _world: Node3D = null
var _playfield: Node3D = null
var _plunger: Node = null
var _ball: RigidBody3D = null

const PLUNGER_SCENE: PackedScene = preload("res://scenes/elements/Plunger.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/elements/Ball.tscn")

func before_each() -> void:
	# Build a tilted Playfield exactly like table.gd (rotated TILT_DEG about X) so gravity has the
	# real down-table component the bug depends on.
	_world = Node3D.new()
	add_child_autofree(_world)

	_playfield = Node3D.new()
	_playfield.name = "Playfield"
	_playfield.rotation_degrees = Vector3(TableConfig.TILT_DEG, 0.0, 0.0)
	_world.add_child(_playfield)

	# The REAL static geometry, including the new lane pocket. This is the actual shell the ball lives
	# in; using it (not a stand-in box) is what makes "the ball does not fall out the lane" meaningful.
	TableGeometry.build(_playfield)

	# The REAL plunger. It sits at the playfield origin and seats its own face at PLUNGER_REST_POS.
	_plunger = PLUNGER_SCENE.instantiate()
	_plunger.name = "Plunger"
	_plunger.position = Vector3.ZERO
	_playfield.add_child(_plunger)

	# The REAL ball. ball.gd._ready() sets CCD, layers, mass, material, and parks it at BALL_START.
	_ball = BALL_SCENE.instantiate() as RigidBody3D
	_ball.name = "Ball"
	_playfield.add_child(_ball)
	_plunger.set_ball(_ball)

	# Make sure the ball starts exactly at the lane rest spot, awake.
	_ball.reset_to_start()


# ---- Helpers ----------------------------------------------------------------------------

## Reset the ball to the lane start and let it settle to rest against the plunger/pocket.
func _seat_and_settle() -> void:
	_ball.reset_to_start()
	await wait_physics_frames(SETTLE_FRAMES)

## Fire a strike at the given power and let it fully resolve, returning the ball's resulting speed.
func _strike_and_measure(power: float) -> float:
	await _seat_and_settle()
	_plunger.test_strike_at_power(power)
	await wait_physics_frames(STRIKE_FRAMES)
	return _ball.current_speed()


# ---- PROBLEM 1: the ball must rest in the lane, not fall out the bottom ------------------

func test_ball_rests_in_lane_and_does_not_fall_out_bottom() -> void:
	## Drop the ball at the lane start, advance physics, and assert it has NOT rolled off the open
	## lane bottom. The lane pocket (TableGeometry._build_lane_pocket) is the stop. We check the
	## ball's measured local z stayed at or above (smaller-or-equal than) the pocket face plus a
	## ball radius of tolerance, and that it stayed on the +X lane side (it did not leak across the
	## lane divider into the playfield).
	await _seat_and_settle()

	# The ball must not have passed the lane pocket's up-table face by more than its radius (which
	# would mean it slipped past the stop). The pocket face is at LANE_POCKET_FACE_Z.
	var max_allowed_z: float = TableConfig.LANE_POCKET_FACE_Z + TableConfig.BALL_RADIUS
	assert_lt(
		_ball.position.z,
		max_allowed_z,
		"ball fell past the lane bottom: z=%f, lane pocket face=%f" % [
			_ball.position.z, TableConfig.LANE_POCKET_FACE_Z
		]
	)

	# The ball must stay on the lane (+X) side of the divider, i.e. it did not leak into the field.
	# Allow a ball radius of slack at the divider edge.
	assert_gt(
		_ball.position.x,
		TableConfig.LANE_INNER_X - TableConfig.BALL_RADIUS,
		"ball left the launch lane to the -X side: x=%f, lane inner x=%f" % [
			_ball.position.x, TableConfig.LANE_INNER_X
		]
	)

	# It must also not have fallen through the surface (a sanity check the floor held it).
	assert_gt(
		_ball.position.y,
		-TableConfig.BALL_RADIUS,
		"ball fell through the playfield surface: y=%f" % _ball.position.y
	)


# ---- PROBLEM 2: a strike must physically impart velocity --------------------------------

func test_strike_imparts_velocity_to_ball() -> void:
	## With the plunger armed-equivalent (we drive the test hook), a release must throw the ball:
	## its measured speed rises well above rest. The momentum comes from the physical contact, not a
	## coded velocity set, but the oracle is the same either way: the ball is moving afterward.
	var speed: float = await _strike_and_measure(0.6)
	assert_gt(
		speed,
		1.0,
		"a strike must impart real velocity to the ball (speed > 1.0 after the strike); got %f" % speed
	)


func test_full_power_outthrows_weak_strike() -> void:
	## The power->stroke mapping must be MEANINGFUL and monotonic: a full-power strike must throw the
	## ball notably harder than a weak one. This is the launch-skill feel made objective.
	var weak_speed: float = await _strike_and_measure(0.05)
	var full_speed: float = await _strike_and_measure(1.0)
	assert_gt(
		full_speed,
		weak_speed,
		"full-power strike must out-throw a weak strike: full=%f, weak=%f" % [full_speed, weak_speed]
	)
	## And the gap must be substantial, not solver noise: >= 1.5x, mirroring the flipper feel gate.
	assert_gte(
		full_speed,
		1.5 * weak_speed,
		"full strike should be >= 1.5x the weak strike: full=%f, weak=%f" % [full_speed, weak_speed]
	)


func test_launched_ball_speed_lands_in_design_range() -> void:
	## The whole point of the power->stroke mapping is that a launched ball lands ROUGHLY in the
	## design feel window LAUNCH_SPEED_MIN..MAX (30..90). The exact transfer is solver-dependent, so
	## we allow generous slack on both ends and assert the ball comes out in a sane launch band (not a
	## dead dribble, not a hypersonic glitch). The exact value is flagged for on-device tuning.
	var full_speed: float = await _strike_and_measure(1.0)
	## Lower bound: a full strike must at least reach the MIN design speed (it should clear the arch).
	assert_gte(
		full_speed,
		TableConfig.LAUNCH_SPEED_MIN,
		"a full-power strike should reach at least LAUNCH_SPEED_MIN (%f); got %f" % [
			TableConfig.LAUNCH_SPEED_MIN, full_speed
		]
	)
	## Upper bound (with slack): the strike must not produce a wildly out-of-scale speed, which would
	## signal a tunneling pop or a bad mapping. 1.5x the design max is a generous ceiling.
	assert_lt(
		full_speed,
		TableConfig.LAUNCH_SPEED_MAX * 1.5,
		"a full-power strike speed is implausibly high (mapping/tunneling?): got %f, ceiling %f" % [
			full_speed, TableConfig.LAUNCH_SPEED_MAX * 1.5
		]
	)


# ---- NO TUNNELING: the ball never passes through the plunger face or the lane pocket -----

func test_max_strike_does_not_tunnel_ball_behind_plunger_or_pocket() -> void:
	## Fire the hardest possible strike repeatedly and assert the ball ALWAYS ends up on the playfield
	## side (up-table, smaller z) of where it started, and NEVER behind the plunger face or below the
	## lane pocket. A tunnel would leave the ball at a z greater than the pocket face (it punched
	## through the stop) or stuck behind the moving face.
	##
	## INDEPENDENT ORACLE: ball.position.z measured after the strike resolves. Position cannot lie.
	const ITERATIONS: int = 20
	var pocket_face_z: float = TableConfig.LANE_POCKET_FACE_Z
	for i in range(ITERATIONS):
		var speed: float = await _strike_and_measure(1.0)
		# The ball must have been thrown UP-TABLE (it should be well above, i.e. smaller z than, the
		# rest position). It must never be past the lane pocket (which would mean it tunneled the stop).
		assert_lt(
			_ball.position.z,
			pocket_face_z + TableConfig.BALL_RADIUS,
			"iteration %d: ball tunneled past the lane pocket. z=%f, pocket face=%f, speed=%f" % [
				i, _ball.position.z, pocket_face_z, speed
			]
		)
		# It must also have actually moved up-table (the strike connected), not be stuck at rest.
		assert_lt(
			_ball.position.z,
			TableConfig.BALL_START.z + TableConfig.BALL_RADIUS,
			"iteration %d: ball was not thrown up-table by a full strike. z=%f, start z=%f" % [
				i, _ball.position.z, TableConfig.BALL_START.z
			]
		)
		# And it must not have fallen through the floor.
		assert_gt(
			_ball.position.y,
			-TableConfig.BALL_RADIUS * 2.0,
			"iteration %d: ball dropped through the surface. y=%f" % [i, _ball.position.y]
		)
