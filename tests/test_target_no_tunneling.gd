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


## Read the deflector post radius LIVE from the instanced target's actual collision shape, so the
## tunnel threshold can never drift from a stale hardcoded test constant (the producer SEND_BACK:
## a test-local POST_RADIUS = 1.5 disagreed with the resized target radius of 2.0). The deflector is
## the child StaticBody3D "Deflector" with a CylinderShape3D; we return its radius. Returns 0.0 only
## if the deflector is somehow absent (caller asserts > 0), but the tests below
## guard that the deflector exists. This is the independent oracle: the radius the SOLVER actually
## sees, not a number a human kept in sync by hand.
func _live_post_radius() -> float:
	var deflector: Node = _target.find_child("Deflector", true, false)
	if deflector == null:
		return 0.0
	for child in deflector.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CylinderShape3D:
			return ((child as CollisionShape3D).shape as CylinderShape3D).radius
	return 0.0


func test_full_speed_ball_never_tunnels_the_target() -> void:
	## Fire the ball straight at the post at worst-case speed (2x LAUNCH_SPEED_MAX) TEST_ITERATIONS
	## times and assert it NEVER ends up on the far side of the post. The pass threshold is the post's
	## far face (+post_radius from origin) plus half a ball radius of epsilon (the same tolerance used
	## in test_ball_tunneling.gd for the flat wall). Anything beyond that means the sphere exited
	## through the solid body: a tunnel.
	##
	## ORACLE: _ball.position.z measured after each shot. Position cannot lie about tunneling.
	## If the physics-programmer forgot CCD on the ball, or if Jolt's CCD does not cover cylindrical
	## bodies at this speed, this loop will find it within a handful of iterations.
	## The post radius is read LIVE from the instanced deflector shape so it never drifts from config.
	var post_radius: float = _live_post_radius()
	assert_gt(post_radius, 0.0, "could not read the live deflector radius (Deflector/CylinderShape3D)")
	var post_far_face_z: float = post_radius
	var tunnel_threshold: float = post_far_face_z + TableConfig.BALL_RADIUS * 0.5
	var ball_start_z: float = -(post_radius + TableConfig.BALL_RADIUS + START_OFFSET)

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


func test_deflector_radius_is_read_live_and_matches_config() -> void:
	## The deflector post radius drives the tunnel threshold above; this test guarantees that radius is
	## read LIVE from the instanced collision shape (never a stale test constant) and that the shipping
	## target's radius equals the single source of truth (Target.POST_RADIUS in target.gd). The
	## producer SEND_BACK was exactly a drift: a test-local POST_RADIUS = 1.5 disagreed with the
	## resized 2.0 post. We derive everything from the live shape, so this asserts the live read works
	## and that target.gd's own constant and its built shape agree (they cannot silently diverge).
	var deflector: Node = _target.find_child("Deflector", true, false)
	if deflector == null:
		# The deflector does not exist yet (implementation pending); the existence gate lives in
		# test_target_physical.gd. We cannot check the radius without it.
		pending("Deflector not yet built in target.gd; skip radius consistency check")
		return

	var live_radius: float = _live_post_radius()
	assert_gt(
		live_radius, 0.0,
		"the deflector must expose a CylinderShape3D so the radius can be read live"
	)

	# The live shape radius must equal target.gd's own POST_RADIUS constant (the single source of
	# truth). Reading the script constant via the instanced node keeps both in lockstep automatically.
	var script_radius: float = _target.get_script().get_script_constant_map().get("POST_RADIUS", -1.0)
	assert_almost_eq(
		live_radius,
		script_radius,
		0.001,
		"the built deflector radius (%.3f) must equal target.gd POST_RADIUS (%.3f); reading it live "
		% [live_radius, script_radius]
		+ "means the tunnel threshold can never drift from the configured post size"
	)
