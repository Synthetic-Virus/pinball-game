extends GutTest
## Test matrix entry: NO TUNNELING through the active-kick furniture (stress gate).
## Owner: physics-programmer + qa-lead. Slice: "real pinball furniture".
##
## WHY THIS EXISTS: the headline correctness gate (DESIGN.md "NOTHING TUNNELS, EVER") must hold for
## the pop-bumper and slingshot solid bodies, INCLUDING the worst case where the active kick STACKS
## on
## a fast incoming ball. Two things are proven here against the REAL instanced bodies (independent
## oracle, position cannot lie):
##   1. A ball fired at >= 2x LAUNCH_SPEED_MAX at the solid KickerBody never ends up behind it.
##   2. The active kick CAP holds: after any kick the ball's speed stays <= KICK_MAX_OUTGOING_SPEED,
##      so a stacked kick can never produce a speed outside the proven-safe CCD band. (If the kick
##      were uncapped, a fast-in + impulse could shove the ball through a neighbour before CCD
##      resolves - the exact failure the DESIGN brief warns about.)
##
## STRUCTURE: instance the REAL PopBumper.tscn / Slingshot.tscn and the REAL Ball.tscn. A hand-built
## stand-in passing here would be a false green on the gate that matters most.

const TEST_ITERATIONS: int = 60
const STEP_FRAMES: int = 30
const START_OFFSET: float = 5.0

const POP_BUMPER_SCENE: PackedScene = preload("res://scenes/elements/PopBumper.tscn")
const SLINGSHOT_SCENE: PackedScene = preload("res://scenes/elements/Slingshot.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/elements/Ball.tscn")

var _world: Node3D = null
var _test_speed: float = 0.0


func before_all() -> void:
	_test_speed = 2.0 * TableConfig.LAUNCH_SPEED_MAX


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)


## Fire the REAL ball at the given element TEST_ITERATIONS times at worst-case speed and assert the
## ball never ends up on the far (+Z) side of the element (a tunnel), and the post-kick speed never
## exceeds the CCD-safe cap. element_far_z is the +Z extent of the solid body from the origin.
func _stress(element: Area3D, element_far_z: float) -> void:
	var ball: RigidBody3D = BALL_SCENE.instantiate() as RigidBody3D
	_world.add_child(ball)
	element.set_ball(ball)
	ball.gravity_scale = 0.0
	await wait_frames(2)

	var tunnel_threshold: float = element_far_z + TableConfig.BALL_RADIUS * 0.5
	var start_z: float = -(element_far_z + TableConfig.BALL_RADIUS + START_OFFSET)

	for i in range(TEST_ITERATIONS):
		ball.position = Vector3(0.0, 0.0, start_z)
		ball.linear_velocity = Vector3(0.0, 0.0, _test_speed)
		ball.angular_velocity = Vector3.ZERO
		ball.sleeping = false
		await wait_physics_frames(STEP_FRAMES)

		assert_lt(
			ball.position.z,
			tunnel_threshold,
			"Iter %d: ball tunneled the element. z=%f, far face=%f, speed=%f"
			% [i, ball.position.z, element_far_z, _test_speed]
		)
		# After contact (kick), the speed must be inside the proven-safe cap band.
		assert_lte(
			ball.current_speed(),
			TableConfig.KICK_MAX_OUTGOING_SPEED + 1.0,
			"Iter %d: post-kick speed %f exceeds the CCD-safe cap %f"
			% [i, ball.current_speed(), TableConfig.KICK_MAX_OUTGOING_SPEED]
		)


func test_pop_bumper_never_tunnels() -> void:
	var bumper: Area3D = POP_BUMPER_SCENE.instantiate() as Area3D
	if bumper.has_method("configure"):
		bumper.configure()
	bumper.position = Vector3.ZERO
	_world.add_child(bumper)
	await _stress(bumper, TableConfig.POP_BUMPER_RADIUS)


func test_slingshot_never_tunnels() -> void:
	var sling: Area3D = SLINGSHOT_SCENE.instantiate() as Area3D
	if sling.has_method("configure"):
		sling.configure(false)
	sling.position = Vector3.ZERO
	_world.add_child(sling)
	# The slingshot box is thin in Z (SLINGSHOT_THICKNESS); its +Z extent is half the thickness.
	await _stress(sling, TableConfig.SLINGSHOT_THICKNESS * 0.5)
