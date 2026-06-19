extends GutTest
## Test matrix entry: NO TUNNELING through the physical target (stress gate).
## Owner: physics-programmer + qa-lead. Slice: make-the-core-interactions-physics-based.
##
## WHY THIS EXISTS: the headline correctness gate (DESIGN.md "NOTHING TUNNELS, EVER") must hold for
## EVERY new physical body in this slice. test_ball_tunneling.gd covers a flat wall; this file
## covers the TARGET deflector (a cylindrical post), a different shape with a curved face a fast
## ball could otherwise clip past between solver steps. We fire the REAL ball at >= ~2x the max
## launch speed (strictly harder than gameplay) repeatedly and assert it NEVER ends up behind it.
##
## INDEPENDENT-ORACLE RULE: assert the REAL ball's measured position relative to the post, never a
## collision-count the body self-reports. Position cannot lie about tunneling.
##
## STRUCTURE: instance the REAL Target.tscn (so the deflector body, its shape, layer, and material
## are the exact shipping ones the physics-programmer tuned) and the REAL Ball.tscn (CCD/mass/
## material from ball.gd). A green result on a hand-built stand-in would not satisfy the gate.

## How many times to fire the worst-case shot. Matches the flat-wall test (test_ball_tunneling.gd).
const TEST_ITERATIONS: int = 100

## At 240 Hz, 30 frames = 125 ms. A ball at 2*LAUNCH_SPEED_MAX (180 u/s) travels 22.5 units in
## that span, well past a post a few units away. A missed collision shows up as the ball being past
## the post's far face, which is exactly what we check.
const STEP_FRAMES: int = 30

## The post deflector cylinder radius as built by target.gd. Must match the script value (1.5).
## We use a named constant so the intent is obvious and a mismatch flags a maintenance issue.
const POST_RADIUS: float = 1.5

## Starting distance in front of the post (z offset from the post face toward the ball).
const START_OFFSET: float = 5.0

const TARGET_SCENE: PackedScene = preload("res://scenes/elements/Target.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/elements/Ball.tscn")

var _world: Node3D = null
var _target: Area3D = null
var _ball: RigidBody3D = null
## The test speed: 2x LAUNCH_SPEED_MAX. Strictly harder than anything the game tunes for.
var _test_speed: float = 0.0


func before_all() -> void:
	_test_speed = 2.0 * TableConfig.LAUNCH_SPEED_MAX


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)

	# Target at the world origin so the shot geometry is simple: ball fires along +Z at z = 0.
	_target = TARGET_SCENE.instantiate() as Area3D
	_target.position = Vector3.ZERO
	_world.add_child(_target)

	# The REAL shipping ball: CCD, layers, mass, material, and shape all set by ball.gd._ready().
	# Using the real ball is the whole point: a hand-built RigidBody3D that passes while the real
	# ball tunnels would be a false green on the gate that matters most.
	_ball = BALL_SCENE.instantiate() as RigidBody3D
	_world.add_child(_ball)
	_target.set_ball(_ball)
	# Zero gravity for the stress loop so the straight-in shot stays on axis across frames.
	# The tunneling check is about CCD + the solver catching the contact; gravity is noise here.
	_ball.gravity_scale = 0.0
	await wait_frames(2)  # let _ready() build the deflector body and shape


func test_full_speed_ball_never_tunnels_the_target() -> void:
	## Fire the ball straight at the post at worst-case speed (2x LAUNCH_SPEED_MAX) TEST_ITERATIONS
	## times and assert it NEVER ends up on the far side of the post. The pass threshold is the post's
	## far face (+POST_RADIUS from origin) plus half a ball radius of epsilon (the same tolerance used
	## in test_ball_tunneling.gd for the flat wall). Anything beyond that means the sphere exited
	## through the solid body: a tunnel.
	##
	## ORACLE: _ball.position.z measured after each shot. Position cannot lie about tunneling.
	## If the physics-programmer forgot CCD on the ball, or if Jolt's CCD does not cover cylindrical
	## bodies at this speed, this loop will find it within a handful of iterations.
	var post_far_face_z: float = POST_RADIUS
	var tunnel_threshold: float = post_far_face_z + TableConfig.BALL_RADIUS * 0.5
	var ball_start_z: float = -(POST_RADIUS + TableConfig.BALL_RADIUS + START_OFFSET)

	for i in range(TEST_ITERATIONS):
		# Reset ball in front of the post, zero velocity, awake.
		_ball.position = Vector3(0.0, 0.0, ball_start_z)
		_ball.linear_velocity = Vector3.ZERO
		_ball.angular_velocity = Vector3.ZERO
		_ball.sleeping = false

		# Fire toward the post at worst-case speed.
		_ball.linear_velocity = Vector3(0.0, 0.0, _test_speed)

		await wait_physics_frames(STEP_FRAMES)

		# POSITION ORACLE: the ball center must not be past the post far face + epsilon.
		assert_lt(
			_ball.position.z,
			tunnel_threshold,
			"Iteration %d: ball tunneled through the target post. "
			% i
			+ "z=%f, post far face=%f, threshold=%f, speed=%f" % [
				_ball.position.z, post_far_face_z, tunnel_threshold, _test_speed
			]
		)


func test_tunneling_check_matches_flat_wall_test_threshold() -> void:
	## Structural guard: assert our POST_RADIUS constant matches the actual deflector shape radius
	## so the tunnel_threshold in the loop above is accurate. We do this by finding the Deflector
	## child on the target and reading its CylinderShape3D radius. If the physics-programmer changes
	## the post radius in target.gd but does not update POST_RADIUS here, this test flags it as a
	## test-maintenance issue rather than silently using a wrong threshold.
	var deflector: Node = _target.find_child("Deflector", true, false)
	if deflector == null:
		# The deflector does not exist yet (implementation pending); we cannot check the radius.
		# The structural test in test_target_physical.gd already covers the existence gate.
		pending("Deflector not yet built in target.gd; skip radius consistency check")
		return

	# Find the CollisionShape3D on the deflector.
	var col: CollisionShape3D = null
	for child in deflector.get_children():
		if child is CollisionShape3D:
			col = child
			break

	if col == null or not (col.shape is CylinderShape3D):
		# Shape type not yet set; cannot check.
		pending("Deflector shape is not a CylinderShape3D yet; skip radius consistency check")
		return

	var actual_radius: float = (col.shape as CylinderShape3D).radius
	assert_eq(
		actual_radius,
		POST_RADIUS,
		"test constant POST_RADIUS (%.3f) does not match the actual deflector radius (%.3f). "
		% [POST_RADIUS, actual_radius]
		+ "Update POST_RADIUS in this test to match the implementation."
	)
