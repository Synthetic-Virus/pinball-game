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


## Stress a slingshot by firing the ball ALONG ITS KICK NORMAL into the REAL rotated triangular
## face at worst-case speed, asserting the ball never crosses to the far side of the real hull. The
## far extent is derived from the actual rotated KickerBody hull (not a hardcoded box thickness),
## and the firing line is the body's real face normal (Basis(Y, _body_yaw()) * +Z), so this
## exercises the true triangular geometry at >= 2x LAUNCH_SPEED_MAX.
func _stress_along_normal(sling: Area3D) -> void:
	# Face outward normal in world space: the body's local +Z (the kicking face), rotated by the real
	# body yaw. The ball approaches the face ALONG this normal (the kick line), like a draining ball.
	var yaw: float = sling._body_yaw()
	var normal: Vector3 = (Basis(Vector3(0.0, 1.0, 0.0), yaw) * Vector3(0.0, 0.0, 1.0)).normalized()

	# The REAL rotated hull's center and its BACK extent measured along the normal. The body sits
	# BEHIND its face (the apex is on -normal), so a tunnel = the ball ends up past the back of the
	# real hull (proj < back_extent). back_extent is derived from the actual rotated triangular hull,
	# never a hardcoded box thickness (the SEND_BACK note: the old stress modelled a thin Z box).
	var body: Node = sling.find_child("KickerBody", true, false)
	var face_center: Vector3 = _hull_face_center(body, normal)
	var back_extent: float = _hull_min_proj_along(body, normal)

	var ball: RigidBody3D = BALL_SCENE.instantiate() as RigidBody3D
	_world.add_child(ball)
	sling.set_ball(ball)
	ball.gravity_scale = 0.0
	await wait_frames(2)

	# A tunnel = the ball passed clean through to BEHIND the real hull (proj below the back extent,
	# minus half a ball radius of solver tolerance, mirroring the box stress's tolerance band).
	var tunnel_threshold: float = back_extent - TableConfig.BALL_RADIUS * 0.5
	# Start standing off the FRONT of the real face center along +normal, and fire INTO the face
	# (-normal) at >= 2x LAUNCH_SPEED_MAX. Aiming at the face center (not the body origin) guarantees
	# the worst-case line strikes the real triangular face squarely.
	var start_pos: Vector3 = face_center + normal * (TableConfig.BALL_RADIUS + START_OFFSET)

	for i in range(TEST_ITERATIONS):
		ball.position = start_pos
		ball.linear_velocity = -normal * _test_speed
		ball.angular_velocity = Vector3.ZERO
		ball.sleeping = false
		await wait_physics_frames(STEP_FRAMES)

		var along: float = ball.position.dot(normal)
		assert_gt(
			along,
			tunnel_threshold,
			"Iter %d: ball tunneled behind the triangular sling. along_normal=%f, back=%f, speed=%f"
			% [i, along, back_extent, _test_speed]
		)
		assert_lte(
			ball.current_speed(),
			TableConfig.KICK_MAX_OUTGOING_SPEED + 1.0,
			"Iter %d: post-kick speed %f exceeds the CCD-safe cap %f"
			% [i, ball.current_speed(), TableConfig.KICK_MAX_OUTGOING_SPEED]
		)


## World-space hull points of the body's KickerBody convex shape, brought through the body transform
## (the body is yawed by _body_yaw() and sits at the sling origin, so the transformed points are in
## the same frame the ball position is measured in here). Empty if the body/shape is missing.
func _hull_world_points(body: Node) -> PackedVector3Array:
	if body == null:
		return PackedVector3Array()
	var col: CollisionShape3D = null
	for child in body.get_children():
		if child is CollisionShape3D:
			col = child as CollisionShape3D
			break
	if col == null or not (col.shape is ConvexPolygonShape3D):
		return PackedVector3Array()
	var pts: PackedVector3Array = (col.shape as ConvexPolygonShape3D).points
	var xform: Transform3D = (body as Node3D).transform
	var out := PackedVector3Array()
	for p: Vector3 in pts:
		out.append(xform * p)
	return out


## The minimum projection of the REAL hull points onto the given unit direction: the BACK extent of
## the rotated triangular hull (the apex side). A ball is judged tunneled if it ends up past this.
func _hull_min_proj_along(body: Node, direction: Vector3) -> float:
	var pts: PackedVector3Array = _hull_world_points(body)
	if pts.is_empty():
		return -TableConfig.SLINGSHOT_LENGTH
	var min_proj: float = INF
	for p: Vector3 in pts:
		min_proj = minf(min_proj, p.dot(direction))
	return min_proj


## The center of the kicking FACE of the real rotated hull: the average of the hull points with the
## MAX projection along the normal (the face vertices sit furthest along +normal). The ball is fired
## at this point so the worst-case line strikes the real triangular face squarely.
func _hull_face_center(body: Node, normal: Vector3) -> Vector3:
	var pts: PackedVector3Array = _hull_world_points(body)
	if pts.is_empty():
		return Vector3.ZERO
	var max_proj: float = -INF
	for p: Vector3 in pts:
		max_proj = maxf(max_proj, p.dot(normal))
	var sum := Vector3.ZERO
	var count: int = 0
	for p: Vector3 in pts:
		if absf(p.dot(normal) - max_proj) < 0.01:
			sum += p
			count += 1
	if count == 0:
		return Vector3.ZERO
	return sum / float(count)


func test_pop_bumper_never_tunnels() -> void:
	var bumper: Area3D = POP_BUMPER_SCENE.instantiate() as Area3D
	if bumper.has_method("configure"):
		bumper.configure()
	bumper.position = Vector3.ZERO
	_world.add_child(bumper)
	await _stress(bumper, TableConfig.POP_BUMPER_RADIUS)


func test_slingshot_never_tunnels() -> void:
	## SLICE "Playtest fixes 2", fix 3a: the sling is now a ROTATED TRIANGULAR hull, not a thin
	## axis-aligned box. The prior stress modelled it as a thin Z box (half SLINGSHOT_THICKNESS far_z)
	## and only fired the real face at SLOW speed, so it never exercised the real triangular face at
	## the worst-case speed. We now derive the face NORMAL from the body's real yaw and fire the ball
	## ALONG that normal (the kick line) into the real face at >= 2x LAUNCH_SPEED_MAX, asserting the
	## measured ball position never crosses to the far side of the real rotated hull (no tunneling).
	var sling: Area3D = SLINGSHOT_SCENE.instantiate() as Area3D
	if sling.has_method("configure"):
		sling.configure(false)
	sling.position = Vector3.ZERO
	_world.add_child(sling)
	await _stress_along_normal(sling)
