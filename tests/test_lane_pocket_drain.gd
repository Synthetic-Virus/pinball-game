extends GutTest
## Test matrix entry: LANE POCKET STOPS THE BALL WITHOUT CLOSING THE CENTER DRAIN.
## Owner: gameplay-programmer + test-builder. Slice: make-the-core-interactions-physics-based.
##
## WHY THIS EXISTS: the developer reported the ball fell out the OPEN bottom of the launch lane
## because TableGeometry built no lane stop. The fix (TableGeometry._build_lane_pocket) adds a stop
## across ONLY the lane in X (x in [LANE_INNER_X, HALF_WIDTH]) and must LEAVE the center drain
## region (x in [-HALF_WIDTH, LANE_INNER_X]) OPEN. This file proves BOTH halves of that constraint
## with the REAL geometry and the REAL ball, never a stand-in:
##   1. a ball placed in the lane comes to REST (does not exit the bottom), and
##   2. a ball placed at center-X still reaches the drain (the pocket did not seal the center).
##
## INDEPENDENT-ORACLE RULE: assert the REAL ball's measured position (rest test) and the REAL
## drain's ball_drained signal firing (center-still-drains test), never a self-reported flag.

## Physics tick at 240 Hz.
const PHYSICS_TICK_S: float = 1.0 / 240.0
## Strong gravity (200) settles the ball fast; 180 frames (0.75 s) is generous for the settle.
const SETTLE_FRAMES: int = 180
## Extra frames to let a center ball roll all the way to the drain Area3D.
const DRAIN_TRAVEL_FRAMES: int = 240

const BALL_SCENE: PackedScene = preload("res://scenes/elements/Ball.tscn")
## The drain script, loaded once at class scope (gdlint forbids duplicated preloads in a file).
const DRAIN_SCRIPT: GDScript = preload("res://scripts/drain.gd")

var _world: Node3D = null
var _playfield: Node3D = null
var _ball: RigidBody3D = null


func before_each() -> void:
	# Build a tilted Playfield exactly like table.gd (rotated TILT_DEG about X) so gravity has the
	# real down-table component the bug depends on. A flat world would not exercise the pocket stop
	# because gravity would not push the ball toward the drain end.
	_world = Node3D.new()
	add_child_autofree(_world)

	_playfield = Node3D.new()
	_playfield.name = "Playfield"
	_playfield.rotation_degrees = Vector3(TableConfig.TILT_DEG, 0.0, 0.0)
	_world.add_child(_playfield)

	# Build the REAL static geometry including the new lane pocket. Using the actual geometry (not
	# a hand-built box) is what makes these tests meaningful: they validate TableGeometry.build().
	TableGeometry.build(_playfield)

	_ball = BALL_SCENE.instantiate() as RigidBody3D
	_ball.name = "Ball"
	_playfield.add_child(_ball)


# ---- STRUCTURAL: the lane pocket body exists on the right layer, spanning only the lane ----------

func test_lane_pocket_body_exists_on_static_layer() -> void:
	## The pocket must be a body on STATIC_OBSTACLES (so the ball, whose mask includes that layer,
	## collides with it). Find it by node name (TableGeometry names it "LanePocket").
	var pocket: Node = _playfield.find_child("LanePocket", true, false)
	assert_not_null(pocket, "TableGeometry must build a 'LanePocket' static stop in the launch lane")
	if pocket != null and pocket is StaticBody3D:
		assert_eq(
			(pocket as StaticBody3D).collision_layer,
			PhysicsLayers.STATIC_OBSTACLES,
			"the lane pocket must sit on STATIC_OBSTACLES so the ball collides with it"
		)


func test_lane_pocket_does_not_span_the_center_drain_region() -> void:
	## STRUCTURAL guard of the "center drain stays open" constraint (ARCHITECTURE.md 9.3, DESIGN.md
	## "lane pocket must stop the ball WITHOUT closing the center drain"). This is cheap geometry
	## math: read the LanePocket body's X position and its BoxShape3D half-width, compute the -X face
	## position, and assert it sits at or to the right of LANE_INNER_X (with one WALL_THICKNESS of
	## seal slack on the lane-divider side). If someone changes _build_lane_pocket to span the full
	## table width, this test catches it before the behavioral drain test even runs.
	##
	## INDEPENDENT ORACLE: we read the actual CollisionShape3D extent from the built node, not any
	## configuration variable that the pocket builder might have read incorrectly.
	var pocket: Node = _playfield.find_child("LanePocket", true, false)
	if pocket == null:
		assert_not_null(pocket, "LanePocket not found - structural test already fails above")
		return

	if not (pocket is StaticBody3D):
		assert_true(
			pocket is StaticBody3D,
			"LanePocket must be a StaticBody3D, got: %s" % pocket.get_class()
		)
		return

	# Find the first CollisionShape3D child (there should be exactly one on the pocket body).
	var col_shape: CollisionShape3D = null
	for child in pocket.get_children():
		if child is CollisionShape3D:
			col_shape = child as CollisionShape3D
			break

	assert_not_null(col_shape, "LanePocket must have a CollisionShape3D child")
	if col_shape == null:
		return

	assert_true(
		col_shape.shape is BoxShape3D,
		"LanePocket CollisionShape3D must use a BoxShape3D, got: %s" % col_shape.shape.get_class()
	)
	if not (col_shape.shape is BoxShape3D):
		return

	var box: BoxShape3D = col_shape.shape as BoxShape3D
	# box.size.x is the full width of the pocket in the X axis.
	# The body's local position (pocket.position.x) is the center of the box.
	# The -X face (the face closest to the center drain region) is at:
	#   body_center_x - (box_size_x / 2.0)
	var body_center_x: float = pocket.position.x
	var half_box_x: float = box.size.x * 0.5
	var left_face_x: float = body_center_x - half_box_x

	# The -X face must NOT reach into the center drain region AT ALL. The pocket pads only the +X
	# (right-wall) side now (QA BUG-020), so the -X face must land at or to the right of LANE_INNER_X.
	# A small epsilon absorbs float rounding. The previous tolerance allowed one WALL_THICKNESS of
	# slack on this side, which let the -X face protrude 0.4 units into the drain region and clip a
	# draining ball at the mouth (BUG-020); we now hold the tighter, correct boundary.
	var epsilon: float = 0.01
	assert_gte(
		left_face_x,
		TableConfig.LANE_INNER_X - epsilon,
		(
			"LanePocket -X face (x=%.3f) must not cross LANE_INNER_X (%.3f) into the center drain "
			+ "region (QA BUG-020: pad the right-wall side only). A full-width or -X-padded wall "
			+ "blocks/clips the center drain (DESIGN constraint)."
		) % [left_face_x, TableConfig.LANE_INNER_X]
	)


# ---- BEHAVIORAL 1: a ball in the lane rests and does not exit the bottom ----------------

func test_ball_in_lane_comes_to_rest_and_does_not_exit_bottom() -> void:
	## Place the ball at BALL_START (lane-X), let it settle under gravity and the pocket stop, and
	## assert it did NOT roll off the open lane bottom. The lane pocket is the only thing stopping it;
	## if the pocket is missing or misplaced the ball will have z >= LANE_POCKET_FACE_Z + radius.
	## ORACLE: the ball's measured position. Position cannot lie about falling through the stop.
	_ball.reset_to_start()
	await wait_physics_frames(SETTLE_FRAMES)

	# Ball must not have passed the pocket face by more than one ball radius.
	var max_z: float = TableConfig.LANE_POCKET_FACE_Z + TableConfig.BALL_RADIUS
	assert_lt(
		_ball.position.z,
		max_z,
		"ball fell past the lane pocket stop: z=%f, pocket face z=%f" % [
			_ball.position.z, TableConfig.LANE_POCKET_FACE_Z
		]
	)

	# Ball must stay on the +X lane side of the divider (pocket did not push it across).
	assert_gt(
		_ball.position.x,
		TableConfig.LANE_INNER_X - TableConfig.BALL_RADIUS,
		"ball crossed the lane divider to the field side: x=%f, lane inner x=%f" % [
			_ball.position.x, TableConfig.LANE_INNER_X
		]
	)

	# Sanity: ball must not have fallen through the playfield surface (floor is working).
	assert_gt(
		_ball.position.y,
		-TableConfig.BALL_RADIUS,
		"ball fell through the playfield surface: y=%f" % _ball.position.y
	)


# ---- BEHAVIORAL 2: a ball at center-X still reaches the drain (center NOT closed) -------

func test_center_ball_still_reaches_the_drain() -> void:
	## Drop a ball at center X (x = 0) just up-table of the drain. With the pocket only spanning the
	## lane (+X side), nothing should block the ball from rolling into the drain region at center.
	## This test FAILS if someone "fixes" the lane fall by adding a full-width bottom wall: that wall
	## would block the center and break the core "open center drain" mechanic (DESIGN.md constraint).
	## ORACLE: the real Drain.ball_drained signal fires (watch_signals), not a position guess.
	var drain: Area3D = DRAIN_SCRIPT.new()
	drain.name = "TestDrain"
	_playfield.add_child(drain)
	drain.set_ball(_ball)
	watch_signals(drain)

	# Place the ball just up-table of the drain Z at center X, at resting height.
	# The tilted playfield gravity will carry it down into the drain region.
	var start_pos := Vector3(0.0, TableConfig.BALL_RADIUS + 0.2, TableConfig.DRAIN_Z - 4.0)
	_ball.reset_to(start_pos)
	_ball.sleeping = false

	await wait_physics_frames(DRAIN_TRAVEL_FRAMES)

	assert_signal_emitted(
		drain,
		"ball_drained",
		"a center-X ball must reach the drain: the lane pocket must not seal the center drain"
	)


# ---- BEHAVIORAL 3: a ball RESTING in the launch lane must NOT drain (geometry, not a guard) ------

func test_lane_resting_ball_does_not_drain() -> void:
	## REGRESSION for QA B3: the drain volume must NOT overlap the launch-lane resting position. A ball
	## at BALL_START (x=10, in the lane) settling against the pocket must NEVER enter the drain. The
	## old full-width drain swallowed the lane and relied entirely on a GameFlow state guard to avoid a
	## spurious drain; this test proves the GEOMETRY itself keeps the lane ball out of the drain, so a
	## dribble launch that rolls the ball back to rest in the lane while BALL_IN_PLAY cannot drain it.
	##
	## INDEPENDENT ORACLE: the REAL Drain.ball_drained signal, watched for the whole settle. Zero
	## emissions is the pass - not a position guess, not a self-reported flag.
	var drain: Area3D = DRAIN_SCRIPT.new()
	drain.name = "TestDrainLane"
	_playfield.add_child(drain)
	drain.set_ball(_ball)
	watch_signals(drain)

	# Seat the ball where the plunger holds it before launch, then let it settle against the pocket.
	_ball.reset_to_start()
	await wait_physics_frames(SETTLE_FRAMES)

	# The drain must not have fired even once: the lane is a resting chute, not a drain.
	assert_signal_emit_count(
		drain,
		"ball_drained",
		0,
		(
			"a ball resting at BALL_START in the launch lane must NOT enter the drain volume "
			+ "(QA B3: the drain must span only the open center, not the lane)"
		)
	)

	# Sanity: confirm the ball actually stayed in the lane during the watch (so a 0-count is because
	# the geometry excludes the lane, not because the ball left the volume some other way).
	assert_gt(
		_ball.position.x,
		TableConfig.LANE_INNER_X - TableConfig.BALL_RADIUS,
		"ball should still be in the lane during the no-drain check: x=%f" % _ball.position.x
	)
