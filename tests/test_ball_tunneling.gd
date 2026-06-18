extends GutTest
## Test matrix entry: NO TUNNELING, EVER (the headline correctness gate).
## Owner: test-builder + physics-programmer.
##
## This is the single most important test in the project (.claude/CLAUDE.md, DESIGN.md).
## It fires a RigidBody3D ball at a static wall at worst-case full-flip speed, repeatedly,
## and asserts the ball NEVER ends up on the far side of the wall plane.
##
## INDEPENDENT ORACLE RULE: we check the ball's measured POSITION relative to the wall
## plane after stepping the simulation, NOT a collision-count the body self-reports.
## Position cannot lie about tunneling.
##
## SPEED BUDGET: worst-case ball speed from a full-power flip is roughly
##   launch_speed_max + flipper_tip_speed.
## We use 2 * LAUNCH_SPEED_MAX as a generous upper bound so the test is strictly harder
## than anything the physics-programmer will tune for in gameplay.
##
## STRUCTURE: we build our own minimal world inside the test (a StaticBody3D wall and a
## RigidBody3D ball with CCD) so the test does not depend on the rest of the table scene
## being complete. This keeps it deterministic and isolated.
##
## NOTE FOR THE PHYSICS-PROGRAMMER: this test will only pass once ball.gd enables
## continuous_cd = true in _ready. The skeleton currently passes through because the
## ball body has no collision layers set; the physics programmer fills that in.
## The test is written now (before implementation) so CI marks it FAIL until the
## implementation lands - that is intentional and correct.

const TEST_ITERATIONS: int = 100
## Number of 240 Hz physics frames to simulate per shot. At 240 Hz, 30 frames = 125 ms.
## A ball at 2*LAUNCH_SPEED_MAX = 180 u/s travels 22.5 u in that time, well past a wall
## set 5 units away.
const STEP_FRAMES: int = 30

## Wall plane: the wall face sits at this Z in world space. The ball starts in front of it
## (at lower Z) and shoots toward it (+Z direction = toward the wall).
## We use a thin wall (WALL_THICKNESS from TableConfig) to maximise the tunneling risk.
const WALL_Z: float = 0.0
const BALL_START_Z: float = -5.0  ## Ball starts 5 units in front of the wall.

## Worst-case speed: 2x the maximum launch speed. This is strictly harder than gameplay.
var _test_speed: float = 0.0

## The minimal physics world nodes, created fresh for each iteration.
var _world: Node3D = null
var _ball_body: RigidBody3D = null
var _wall_body: StaticBody3D = null

func before_all() -> void:
	_test_speed = 2.0 * TableConfig.LAUNCH_SPEED_MAX

func before_each() -> void:
	# Build a fresh minimal world: one thin static wall and one RigidBody3D ball.
	# add_child_autofree ensures cleanup after each test function.
	_world = Node3D.new()
	add_child_autofree(_world)

	# --- Static wall -----------------------------------------------------------------
	# A thin StaticBody3D on the STATIC_OBSTACLES layer.
	# The ball shoots along +Z toward it; the wall face is at WALL_Z.
	_wall_body = StaticBody3D.new()
	_wall_body.collision_layer = PhysicsLayers.STATIC_OBSTACLES
	_wall_body.collision_mask = 0  ## Walls do not need to detect anything.
	_world.add_child(_wall_body)

	var wall_shape_node := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	## Width and height larger than anything the ball can reach; depth = TableConfig.WALL_THICKNESS.
	wall_box.size = Vector3(40.0, 40.0, TableConfig.WALL_THICKNESS)
	wall_shape_node.shape = wall_box
	## Center the box so its front face aligns with WALL_Z.
	wall_shape_node.position.z = WALL_Z + TableConfig.WALL_THICKNESS * 0.5
	_wall_body.add_child(wall_shape_node)

	# --- Ball -------------------------------------------------------------------------
	# A RigidBody3D with CCD enabled and the correct layer/mask from PhysicsLayers.
	# We build this by hand (not by instancing the scene) so the test is independent
	# of the scene file and the physics-programmer's _ready implementation; the test
	# sets the properties it needs directly and the CCD sub-test checks the scene.
	_ball_body = RigidBody3D.new()
	_ball_body.continuous_cd = true  ## The non-negotiable CCD property.
	_ball_body.collision_layer = PhysicsLayers.BALLS
	_ball_body.collision_mask = PhysicsLayers.BALL_COLLISION_MASK
	_ball_body.mass = TableConfig.BALL_MASS

	var ball_physics_mat := PhysicsMaterial.new()
	ball_physics_mat.bounce = TableConfig.BALL_BOUNCE
	ball_physics_mat.friction = TableConfig.BALL_FRICTION
	_ball_body.physics_material_override = ball_physics_mat

	_world.add_child(_ball_body)

	var ball_shape_node := CollisionShape3D.new()
	var ball_sphere := SphereShape3D.new()
	ball_sphere.radius = TableConfig.BALL_RADIUS
	ball_shape_node.shape = ball_sphere
	_ball_body.add_child(ball_shape_node)

func test_ccd_is_enabled_on_ball() -> void:
	## Cheap guard: instance the actual Ball scene and confirm continuous_cd is true.
	## If the physics-programmer turns CCD off a regression is caught immediately,
	## not just statistically through the position check.
	var ball_scene: PackedScene = load("res://scenes/elements/Ball.tscn")
	var ball_instance: RigidBody3D = ball_scene.instantiate()
	add_child_autofree(ball_instance)
	## _ready will have run by the time add_child returns.
	assert_true(
		ball_instance.continuous_cd,
		"Ball.tscn must have continuous_cd == true after _ready (physics-programmer: set it in _ready)"
	)

func test_full_speed_ball_never_tunnels_a_wall() -> void:
	## Fire the ball at the wall TEST_ITERATIONS times and assert it never crosses WALL_Z.
	## Each iteration: place ball in front of wall, set velocity toward wall, step N frames,
	## check position.
	##
	## PASS CONDITION: after all frames, ball's world Z >= WALL_Z - BALL_RADIUS.
	## (We allow the ball to sit exactly at the wall face or to have bounced back; we only
	## fail if the center is clearly past the wall plane by more than the ball radius, which
	## means the sphere has exited through the wall - i.e. tunneled.)
	for i in range(TEST_ITERATIONS):
		## Reset ball to start position in front of the wall, zero velocity.
		_ball_body.position = Vector3(0.0, 0.0, BALL_START_Z)
		_ball_body.linear_velocity = Vector3.ZERO
		_ball_body.angular_velocity = Vector3.ZERO

		## Fire toward the wall at worst-case speed.
		_ball_body.linear_velocity = Vector3(0.0, 0.0, _test_speed)

		## Step the simulation STEP_FRAMES physics frames.
		## GUT's await wait_physics_frames suspends here and resumes after the engine
		## has stepped the physics world the requested number of times.
		await wait_physics_frames(STEP_FRAMES)

		## POSITION ORACLE: the ball's center Z must not be past the wall.
		## Tunneling means center.z > WALL_Z (the ball is on the far side of the wall face).
		## We add a small epsilon (half BALL_RADIUS) to avoid a false failure if the solver
		## barely clips through on the last frame before bouncing.
		var tunnel_threshold: float = WALL_Z + TableConfig.BALL_RADIUS * 0.5
		assert_true(
			_ball_body.position.z < tunnel_threshold,
			"Iteration %d: ball tunneled through wall. ball.z=%f, threshold=%f, speed=%f" % [
				i, _ball_body.position.z, tunnel_threshold, _test_speed
			]
		)

func test_ball_stays_in_front_of_wall_after_bounce() -> void:
	## After the ball bounces off the wall it should be moving away (negative Z velocity)
	## and its position should be in front of the wall (negative Z relative to wall face).
	## This is a gentler sanity check that confirms a bounce actually occurred.
	_ball_body.position = Vector3(0.0, 0.0, BALL_START_Z)
	_ball_body.linear_velocity = Vector3.ZERO
	_ball_body.angular_velocity = Vector3.ZERO
	_ball_body.linear_velocity = Vector3(0.0, 0.0, _test_speed)

	## Give extra frames so the ball has clearly bounced back.
	await wait_physics_frames(STEP_FRAMES * 2)

	## After the bounce the ball should have moved back toward its start (lower Z or at wall).
	assert_true(
		_ball_body.position.z <= WALL_Z,
		"Ball should be at or in front of wall after bounce. ball.z=%f" % _ball_body.position.z
	)
