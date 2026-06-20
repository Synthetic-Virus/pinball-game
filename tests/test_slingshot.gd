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


## Drop the ball onto the FRONT of the slingshot's angled kicking face, moving INTO the face so it
## makes contact. SLICE "Playtest fixes 2", fix 3: the sling is now a rotated triangular hull whose
## kicking face normal is the kick direction (slingshot.gd._body_yaw maps the face's local +Z onto
## _kick_dir, the BUG-030 orientation the live table relies on). A draining ball strikes that face
## on its FRONT (the kick-normal side), so we stand the ball off along +kick_dir and fire it back
## along -kick_dir into the face; the active kick then sends it out along +kick_dir (into play). The
## earlier version dropped the ball from straight down-table (-Z), which struck the BACK of the face
## and only ever got a passive bounce - it passed only when the face was (incorrectly) flipped to
## point down-table, which broke the live-table launch path (test_soft_lock_integration).
func _drop_into_sling() -> void:
	var kick_dir: Vector3 = _sling._kick_dir
	var standoff: float = TableConfig.BALL_RADIUS + 2.0
	_ball.position = kick_dir * standoff
	_ball.position.y = 0.0  # strike the face at body mid-height, not over/under it.
	# Fire INTO the face (opposite the kick normal) so a real contact occurs; the active kick does the
	# rest, sending the ball back out along +kick_dir (up-table and toward center).
	_ball.linear_velocity = -kick_dir * SLOW_FIRE_SPEED
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


func test_slingshot_body_is_triangular_not_a_box() -> void:
	## SLICE "Playtest fixes 2", fix 3: the slingshot solid body must be a TRIANGLE (a convex hull),
	## NOT a BoxShape3D. The developer reported the slings read as small boxes; the fix swaps the
	## collider + mesh to a triangular prism. ORACLE: the REAL built KickerBody collision shape class.
	await _setup_sling(false)
	var body: Node = _sling.find_child("KickerBody", true, false)
	assert_not_null(body, "slingshot must build a KickerBody")
	if body == null:
		return
	var col: CollisionShape3D = null
	for child in body.get_children():
		if child is CollisionShape3D:
			col = child as CollisionShape3D
			break
	assert_not_null(col, "the KickerBody must have a CollisionShape3D")
	if col != null:
		assert_false(
			col.shape is BoxShape3D,
			"the slingshot solid body must NOT be a BoxShape3D (a square); use a triangular hull"
		)
		assert_true(
			col.shape is ConvexPolygonShape3D,
			"the slingshot solid body must be a ConvexPolygonShape3D (triangular prism). got %s"
			% [col.shape]
		)


func test_slingshot_mesh_is_triangular_not_a_box() -> void:
	## The visible mesh must AGREE with the triangular collider (read as a triangle, not a box).
	## ORACLE: the REAL KickerMesh mesh class.
	await _setup_sling(false)
	var mesh_instance: Node = _sling.find_child("KickerMesh", true, false)
	assert_not_null(mesh_instance, "slingshot must build a visible KickerMesh")
	if mesh_instance != null and mesh_instance is MeshInstance3D:
		var mesh: Mesh = (mesh_instance as MeshInstance3D).mesh
		assert_not_null(mesh, "the KickerMesh must have a mesh")
		assert_false(
			mesh is BoxMesh,
			"the slingshot mesh must agree with the triangular collider (not a plain BoxMesh)"
		)


func test_left_and_right_slings_are_mirrored() -> void:
	## A left-handed triangle above the LEFT flipper and a right-handed (mirrored) one above the RIGHT.
	## ORACLE: the apex X offset sign flips between the two configured slings. We read the convex hull
	## point clouds and compare the apex (the vertex furthest BACK on -Z in the local pre-yaw frame is
	## the one whose X offset encodes handedness). Simpler robust check: the two hulls are not
	## identical point sets (the mirror produced a different triangle), and each is a valid 3-point
	## prism (6 extruded points).
	await _setup_sling(false)
	var left_body: Node = _sling.find_child("KickerBody", true, false)
	var left_pts: PackedVector3Array = _hull_points(left_body)

	# Build a right (mirrored) sling in the same world and compare.
	var right: Area3D = SLINGSHOT_SCENE.instantiate() as Area3D
	if right.has_method("configure"):
		right.configure(true)
	right.position = Vector3.ZERO
	_world.add_child(right)
	await wait_frames(2)
	var right_pts: PackedVector3Array = _hull_points(right.find_child("KickerBody", true, false))

	assert_eq(left_pts.size(), 6, "a triangular prism hull has 6 extruded points (3 x top/bottom)")
	assert_eq(right_pts.size(), 6, "the mirrored prism hull also has 6 points")
	assert_false(
		_same_point_cloud(left_pts, right_pts),
		"the left and right slingshots must be MIRRORED (different triangle footprints), not identical"
	)


## Read the convex hull point cloud of a KickerBody's CollisionShape3D, or an empty array.
func _hull_points(body: Node) -> PackedVector3Array:
	if body == null:
		return PackedVector3Array()
	for child in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is ConvexPolygonShape3D:
			return ((child as CollisionShape3D).shape as ConvexPolygonShape3D).points
	return PackedVector3Array()


## True if two point clouds are the same set (order-independent, approximate). Used to prove the
## mirror actually produced a different triangle.
func _same_point_cloud(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for pa: Vector3 in a:
		var found: bool = false
		for pb: Vector3 in b:
			if pa.is_equal_approx(pb):
				found = true
				break
		if not found:
			return false
	return true


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


func test_sling_corner_contact_still_kicks_and_scores() -> void:
	## REGRESSION for QA BUG-018: the slingshot solid body is a BoxShape3D rotated by _body_yaw, so
	## its corners poke past an AXIS-ALIGNED detector. A ball striking near a CORNER of the angled face
	## used to enter the solid body WITHOUT tripping body_entered, so the active kick + score silently
	## never fired and the ball only got the passive material bounce (the "limp bounce" the active
	## element exists to prevent). Now the detector is rotated to match the body and padded on the long
	## axis, so a corner contact must ALSO trip body_entered. We fire the ball at the up-table END of
	## the angled face and assert the kick fired (scored once AND the ball left at the kick floor).
	## ORACLE: the REAL scored signal count AND the REAL ball's measured speed.
	await _setup_sling(false)
	watch_signals(_sling)

	# Compute a point just off a CORNER of the LEFT slingshot's angled face, then fire the ball into
	# that corner. The solid body is a BoxShape3D rotated about Y by _body_yaw(), so we derive the
	# face axes from THAT SAME rotation (not a hand-written sin/cos, which previously had a sign error
	# on the long axis and aimed the ball at empty space PAST the face - it then only ever got a
	# passive glancing bounce, never a real corner contact, masking the behavior under test).
	#   along       = the face LONG axis  = Basis(Y, yaw) * +X  (one end is a corner).
	#   face_normal = the face THIN axis  = Basis(Y, yaw) * +Z  (the direction the ball stands off on).
	# Using the real rotated basis guarantees `corner` lies on the actual angled face the ball strikes.
	var yaw: float = _sling._body_yaw()
	var body_basis := Basis(Vector3(0.0, 1.0, 0.0), yaw)
	var along: Vector3 = body_basis * Vector3(1.0, 0.0, 0.0)       # face long axis (rotated +X).
	var face_normal: Vector3 = body_basis * Vector3(0.0, 0.0, 1.0)  # face thin axis (rotated +Z).
	# Corner = the end of the long axis, out on the face surface (+half thickness along the thin axis).
	var corner: Vector3 = (
		along * (TableConfig.SLINGSHOT_LENGTH * 0.5)
		+ face_normal * (TableConfig.SLINGSHOT_THICKNESS * 0.5)
	)
	var standoff: float = TableConfig.BALL_RADIUS + 1.5
	_ball.position = corner + face_normal * standoff
	_ball.position.y = 0.0  # strike the face edge-on at body mid-height, not over/under it.
	_ball.linear_velocity = -face_normal * SLOW_FIRE_SPEED  # fire into the corner of the face.
	_ball.angular_velocity = Vector3.ZERO
	_ball.sleeping = false
	await wait_physics_frames(APPROACH_FRAMES)

	assert_signal_emit_count(
		_sling, "scored", 1,
		"a corner contact on the angled slingshot face must still score (QA BUG-018)"
	)
	assert_gt(
		_ball.current_speed(),
		TableConfig.KICK_MIN_OUTGOING_SPEED,
		(
			"a corner contact must still get the ACTIVE kick (>= KICK_MIN_OUTGOING_SPEED), not a "
			+ "limp passive bounce (QA BUG-018). speed=%f"
		) % _ball.current_speed()
	)
