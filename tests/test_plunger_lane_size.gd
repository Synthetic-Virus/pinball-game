extends GutTest
## Test matrix entry: THE LAUNCH FURNITURE FITS THE BALL (lane + plunger resize).
## Owner: lead-programmer (TableConfig geometry) + physics-programmer (the resized face strikes
## head-on) + test-builder. Slice: "Playtest fixes 2", fix 4.
##
## WHY THIS EXISTS: developer playtest feedback - the launch ramp/plunger were too wide/bulky and
## did not line up with the ball. The fix narrows LANE_WIDTH + PLUNGER_FACE_WIDTH to a ball width.
## This STRUCTURAL test is the independent oracle that the resized constants are actually the snug
## values (caught a real soft-lock-adjacent bug last slice where the lane and ball were misaligned),
## and that the REAL instanced plunger face is built at the resized width. It reads the contract
## constants AND the real built face, never a self-reported value.
##
## DESIGN must-feel #4: the plunger face and lane are sized to ~the ball width (ball diameter ~1.2),
## the ball sits squarely in the lane, and the face strikes it head-on with no gap. The behavioral
## "the resized face still launches on the first stroke / never tunnels" lives in
## tests/test_plunger_launch.gd; this file proves the SIZES are right.

const PLUNGER_SCENE: PackedScene = preload("res://scenes/elements/Plunger.tscn")

## Ball diameter from the contract. The lane/face are sized relative to this.
var _ball_dia: float = TableConfig.BALL_RADIUS * 2.0

var _world: Node3D = null


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)


# ---- STRUCTURAL: the resized constants are a snug ball-width chute ------------------------------

func test_lane_width_is_a_snug_ball_width_chute() -> void:
	## The lane (HALF_WIDTH - LANE_INNER_X) must be a snug chute: at least a ball diameter (the ball
	## fits) and no more than ~3 ball diameters (it reads as a chute, not a box). This is the resize.
	var lane_w: float = TableConfig.LANE_WIDTH
	assert_gte(
		lane_w, _ball_dia,
		"the lane must be at least one ball diameter wide. lane=%f dia=%f" % [lane_w, _ball_dia]
	)
	assert_lte(
		lane_w, 3.0 * _ball_dia,
		"the lane must be a snug chute (<= ~3 ball diameters), not bulky. lane=%f dia=%f"
		% [lane_w, _ball_dia]
	)


func test_plunger_face_is_ball_width_and_fits_the_lane() -> void:
	## The plunger face must be WIDER than the ball (so an off-center rest is struck squarely) yet FIT
	## inside the lane with clearance (no part poking into the divider or the wall).
	var face_w: float = TableConfig.PLUNGER_FACE_WIDTH
	assert_gt(
		face_w, _ball_dia,
		"the plunger face must be wider than the ball to strike it squarely. face=%f dia=%f"
		% [face_w, _ball_dia]
	)
	assert_lt(
		face_w, TableConfig.LANE_WIDTH,
		"the plunger face must fit inside the lane with clearance. face=%f lane=%f"
		% [face_w, TableConfig.LANE_WIDTH]
	)


func test_ball_start_and_plunger_share_the_lane_center() -> void:
	## The resting ball (BALL_START.x) and the plunger face (PLUNGER_REST_POS.x) must be at the SAME X
	## (the lane center) so the face strikes the ball head-on, and that X must be inside the lane.
	var lane_center: float = (TableConfig.LANE_INNER_X + TableConfig.HALF_WIDTH) * 0.5
	assert_almost_eq(
		TableConfig.BALL_START.x, lane_center, 0.01,
		"the ball must rest at the lane center"
	)
	assert_almost_eq(
		TableConfig.PLUNGER_REST_POS.x, lane_center, 0.01,
		"the plunger face must center on the lane center (head-on with the ball)"
	)
	assert_gt(
		TableConfig.BALL_START.x - TableConfig.BALL_RADIUS, TableConfig.LANE_INNER_X,
		"the resting ball must sit fully inside the lane (clear of the divider)"
	)
	assert_lt(
		TableConfig.BALL_START.x + TableConfig.BALL_RADIUS, TableConfig.HALF_WIDTH,
		"the resting ball must sit fully inside the lane (clear of the right wall)"
	)


# ---- STRUCTURAL: the REAL built face is the resized width --------------------------------------

func test_built_plunger_face_matches_resized_width() -> void:
	## The independent oracle on the BUILT body: the real PlungerFace collision box must be
	## PLUNGER_FACE_WIDTH wide (so a future code change that hardcodes a width is caught here).
	var plunger: Node = PLUNGER_SCENE.instantiate()
	plunger.position = Vector3.ZERO
	_world.add_child(plunger)
	await wait_frames(2)
	var face: Node = plunger.find_child("PlungerFace", true, false)
	assert_not_null(face, "the plunger must build a PlungerFace body")
	if face == null:
		return
	var col: CollisionShape3D = null
	for child in face.get_children():
		if child is CollisionShape3D:
			col = child as CollisionShape3D
			break
	assert_not_null(col, "the PlungerFace must have a CollisionShape3D")
	if col != null and col.shape is BoxShape3D:
		var box: BoxShape3D = col.shape as BoxShape3D
		assert_almost_eq(
			box.size.x, TableConfig.PLUNGER_FACE_WIDTH, 0.01,
			"the built plunger face width must match the resized PLUNGER_FACE_WIDTH"
		)
