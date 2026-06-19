extends GutTest
## Test matrix entry: SLINGSHOT (active kick UP-table and toward center, never the drain).
## Owner: physics-programmer (active kick + solid body) + gameplay-programmer (cooldown + score) +
## test-builder. Slice: "real pinball furniture".
##
## WHY THIS EXISTS: DESIGN must-feel "saved by the slings": a ball dropping down the side is kicked
## back UP-table and toward CENTER (into play), NEVER down toward the drain. Unlike a pop bumper
## (radial), a slingshot has a FIXED kick direction so it reliably returns the ball regardless of
## the
## contact point. This test asserts, for BOTH the left and right slingshot, that the outgoing
## velocity
## has a positive up-table (-Z) component AND a toward-center X sign, against the REAL ball's
## measured
## velocity (independent oracle). A kick that pointed at the drain (+Z) would FAIL.

const SLOW_FIRE_SPEED: float = 8.0
## Frames needed for the slow ball to travel from its start position (z ~= BALL_RADIUS + 2.0 = 2.6)
## to the slingshot face at z ~= 0 and let the kick + outgoing velocity settle. At 8 u/s and
## 240 Hz that is ~78 frames. Use 120 frames for a comfortable margin.
const APPROACH_FRAMES: int = 120

const SLINGSHOT_SCENE: PackedScene = preload("res://scenes/elements/Slingshot.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/elements/Ball.tscn")

var _world: Node3D = null
var _sling: Area3D = null
var _ball: RigidBody3D = null


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)


## Build a slingshot of the given handedness at the origin with a ball ready to drop into it.
func _setup_sling(mirrored: bool) -> void:
	_sling = SLINGSHOT_SCENE.instantiate() as Area3D
	if _sling.has_method("configure"):
		_sling.configure(mirrored)
	_sling.position = Vector3.ZERO
	_world.add_child(_sling)

	_ball = BALL_SCENE.instantiate() as RigidBody3D
	_world.add_child(_ball)
	_sling.set_ball(_ball)
	_ball.gravity_scale = 0.0
	await wait_frames(2)


## Drop the ball onto the slingshot from down-table (the side a draining ball comes from), moving
## up-and-in toward the face so it makes contact.
func _drop_into_sling() -> void:
	_ball.position = Vector3(0.0, 0.0, TableConfig.BALL_RADIUS + 2.0)
	# Push gently toward the sling (up-table) so a contact occurs; the active kick does the rest.
	_ball.linear_velocity = Vector3(0.0, 0.0, -SLOW_FIRE_SPEED)
	_ball.angular_velocity = Vector3.ZERO
	_ball.sleeping = false


# ---- STRUCTURAL ---------------------------------------------------------------------------------

func test_slingshot_has_solid_body_on_static_layer() -> void:
	await _setup_sling(false)
	var body: Node = _sling.find_child("KickerBody", true, false)
	assert_not_null(body, "slingshot must build a child StaticBody3D 'KickerBody'")
	if body != null and body is StaticBody3D:
		assert_eq(
			(body as StaticBody3D).collision_layer,
			PhysicsLayers.STATIC_OBSTACLES,
			"the slingshot KickerBody must sit on STATIC_OBSTACLES"
		)


func test_slingshot_kick_directions_point_into_play() -> void:
	## Geometry guard (no physics needed): the configured kick directions in TableConfig must point
	## INTO play - positive up-table (-Z) component, and a toward-center X sign per side. This is the
	## load-bearing "never toward the drain" guarantee, asserted on the contract constants directly.
	var left: Vector3 = TableConfig.SLINGSHOT_LEFT_KICK_DIR
	var right: Vector3 = TableConfig.SLINGSHOT_RIGHT_KICK_DIR
	assert_lt(left.z, 0.0, "left sling must kick UP-table (-z), not toward the drain. z=%f" % left.z)
	assert_gt(left.x, 0.0, "left sling (left of center) must kick toward +x center. x=%f" % left.x)
	assert_lt(right.z, 0.0, "right sling must kick UP-table (-z). z=%f" % right.z)
	assert_lt(right.x, 0.0, "right sling (right of center) must kick toward -x center. x=%f" % right.x)


# ---- BEHAVIORAL: the kicked ball travels up-table and toward center ------------------------------

func test_left_sling_kicks_ball_into_play() -> void:
	## A ball dropping onto the LEFT slingshot must leave moving up-table (-Z) and toward +X (center).
	## ORACLE: _ball.linear_velocity components after the kick.
	await _setup_sling(false)
	_drop_into_sling()
	await wait_physics_frames(APPROACH_FRAMES)

	assert_lt(
		_ball.linear_velocity.z, 0.0,
		"left sling must send the ball UP-table (-z), never toward the drain. vz=%f"
		% _ball.linear_velocity.z
	)
	assert_gt(
		_ball.linear_velocity.x, 0.0,
		"left sling must send the ball toward center (+x). vx=%f" % _ball.linear_velocity.x
	)


func test_right_sling_kicks_ball_into_play() -> void:
	## Mirror of the left: a ball on the RIGHT slingshot leaves up-table (-Z) and toward -X (center).
	await _setup_sling(true)
	_drop_into_sling()
	await wait_physics_frames(APPROACH_FRAMES)

	assert_lt(
		_ball.linear_velocity.z, 0.0,
		"right sling must send the ball UP-table (-z). vz=%f" % _ball.linear_velocity.z
	)
	assert_lt(
		_ball.linear_velocity.x, 0.0,
		"right sling must send the ball toward center (-x). vx=%f" % _ball.linear_velocity.x
	)


func test_sling_gives_minimum_outgoing_speed() -> void:
	## A slow ball must still leave with authority (the active kick floor). ORACLE: current_speed().
	await _setup_sling(false)
	_drop_into_sling()
	await wait_physics_frames(APPROACH_FRAMES)
	assert_gt(
		_ball.current_speed(),
		TableConfig.KICK_MIN_OUTGOING_SPEED,
		"a slow ball must leave the slingshot fast (>= KICK_MIN_OUTGOING_SPEED). speed=%f"
		% _ball.current_speed()
	)


func test_sling_scores_once_per_contact() -> void:
	await _setup_sling(false)
	watch_signals(_sling)
	_drop_into_sling()
	await wait_physics_frames(APPROACH_FRAMES)
	assert_signal_emit_count(_sling, "scored", 1, "slingshot must score exactly once per kick")
