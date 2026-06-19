extends GutTest
## Test matrix entry: TABLE WIRING INTEGRATION (the real built Table.tscn tree).
## Owner: test-builder + qa-lead. Slice: make-the-core-interactions-physics-based.
##
## WHY THIS EXISTS (QA BUG-014): the slice's two BLOCKING bugs - the missing lane pocket (BUG-012)
## and the double-offset plunger (BUG-013) - sailed through CI because EVERY other slice test bypasses
## table.gd. The unit tests build their own playfield and (for the plunger) seat the Plunger node at
## Vector3.ZERO themselves, so they honored a contract table.gd violated and never exercised table.gd's
## actual wiring. This file closes that gap: it instances the REAL res://scenes/Table.tscn and asserts
## on the REAL built tree, so a regression in table.gd's element placement is caught here, not in a
## browser playtest.
##
## INDEPENDENT-ORACLE RULE: every assertion reads a REAL built node's measured transform or the REAL
## ball's measured position after settling, never a self-reported flag.
##
## NOTE on RED-before-fix: this file is written to LOCK the two blockers closed. Against the pre-fix
## code it FAILS (no LanePocket node; the plunger face lands off the table); against the fixed code it
## PASSES. That is the correct relationship between a regression test and the bug it guards.

const TableScene: PackedScene = preload("res://scenes/Table.tscn")

## Strong gravity (200) settles the lane ball fast; 180 frames (0.75 s) is generous.
const SETTLE_FRAMES: int = 180

var _table: Node3D = null


func before_each() -> void:
	_table = TableScene.instantiate() as Node3D
	add_child_autofree(_table)
	# Let _ready() build the whole tree (geometry, dynamic elements, flow, wiring) and let the
	# deferred camera framing run.
	await wait_frames(3)


## Depth-first search for the first descendant with the given node NAME. Returns null if none.
func _find_named(node_name: String, root: Node = null) -> Node:
	var start: Node = root if root != null else _table
	for child in start.get_children():
		if child.name == node_name:
			return child
		var found: Node = _find_named(node_name, child)
		if found != null:
			return found
	return null


## The tilted Playfield node every element is parented under. Used to convert a built node's GLOBAL
## transform back into playfield-LOCAL space, which is the coordinate space TableConfig is written in.
func _playfield() -> Node3D:
	return _find_named("Playfield") as Node3D


# ---- BUG-012: the lane pocket is actually built into the integrated table ----------------

func test_table_builds_the_lane_pocket() -> void:
	## table.gd -> TableGeometry.build() must produce the LanePocket static stop. Its absence is
	## exactly BUG-012 (the ball rolls off the open lane bottom in the real game).
	var pocket: Node = _find_named("LanePocket")
	assert_not_null(pocket, "the built Table must contain a 'LanePocket' static stop (QA BUG-012)")
	if pocket != null:
		assert_true(
			pocket is StaticBody3D,
			"LanePocket must be a StaticBody3D, got %s" % pocket.get_class()
		)
		assert_eq(
			(pocket as StaticBody3D).collision_layer,
			PhysicsLayers.STATIC_OBSTACLES,
			"LanePocket must sit on STATIC_OBSTACLES so the ball collides with it"
		)


# ---- BUG-013: the plunger face sits in the launch lane, not off the table ----------------

func test_plunger_face_sits_in_the_launch_lane_next_to_ball_start() -> void:
	## The plunger node must be parented at the playfield origin so its face lands at the playfield-
	## LOCAL PLUNGER_REST_POS, in the lane just down-table of BALL_START. The old double-offset bug
	## (BUG-013) put the face at BALL_START + PLUNGER_REST_POS = ~(20, 1.6, 47): past the right wall
	## and well past the open bottom. We convert the face's GLOBAL position into playfield-local space
	## and assert it is inside the lane in X and near BALL_START in Z.
	## ORACLE: the real built face's measured world transform, mapped into the field coordinate space.
	var face: Node3D = _find_named("PlungerFace") as Node3D
	assert_not_null(face, "the built Table must contain a 'PlungerFace' (the physical plunger)")
	var playfield: Node3D = _playfield()
	assert_not_null(playfield, "the built Table must contain the tilted Playfield node")
	if face == null or playfield == null:
		return

	# Map the face's world position back into playfield-local space (the space TableConfig uses).
	var local: Vector3 = playfield.global_transform.affine_inverse() * face.global_position

	# X must be inside the launch lane (between the divider and the right wall), NOT past the wall.
	assert_gt(
		local.x,
		TableConfig.LANE_INNER_X,
		"plunger face X (%.3f) must be inside the lane (> LANE_INNER_X=%.1f)" % [
			local.x, TableConfig.LANE_INNER_X
		]
	)
	assert_lt(
		local.x,
		TableConfig.HALF_WIDTH,
		(
			"plunger face X (%.3f) must be inside the right wall (< HALF_WIDTH=%.1f); the old "
			+ "double-offset put it past the wall (QA BUG-013)"
		) % [local.x, TableConfig.HALF_WIDTH]
	)

	# Z must be near BALL_START.z (the face seats just down-table of the resting ball), well inside the
	# playfield bottom edge. A double-offset would land it ~24 units past the open bottom.
	assert_almost_eq(
		local.z,
		TableConfig.PLUNGER_REST_POS.z,
		TableConfig.WALL_THICKNESS,
		(
			"plunger face Z (%.3f) must be at PLUNGER_REST_POS.z (%.3f); a double-offset lands it past "
			+ "the open table bottom (QA BUG-013)"
		) % [local.z, TableConfig.PLUNGER_REST_POS.z]
	)
	assert_lt(
		local.z,
		TableConfig.HALF_LENGTH,
		"plunger face Z (%.3f) must be inside the playfield bottom edge (< HALF_LENGTH=%.1f)" % [
			local.z, TableConfig.HALF_LENGTH
		]
	)


# ---- The two fixes together: the real ball rests in the lane in the integrated table ----

func test_real_ball_rests_in_the_lane_after_settling() -> void:
	## The end-to-end consequence of BOTH fixes: in the fully-built table the ball spawned at
	## BALL_START settles and stays in the launch lane (it does not roll off the open bottom, it does
	## not leak across the divider). If the lane pocket is missing, the ball ends up past the pocket
	## face; if the plunger is double-offset there is nothing wrong with this test per se, but together
	## with the face test above the launch path is locked.
	## ORACLE: the real ball's measured position after settling.
	var ball: Node3D = _find_named("Ball") as Node3D
	assert_not_null(ball, "the built Table must contain the Ball")
	if ball == null:
		return

	await wait_physics_frames(SETTLE_FRAMES)

	# Ball stayed in the lane bottom (did not roll off past the pocket face by more than one radius).
	var max_z: float = TableConfig.LANE_POCKET_FACE_Z + TableConfig.BALL_RADIUS
	assert_lt(
		ball.position.z,
		max_z,
		"ball fell past the lane pocket in the integrated table: z=%.3f, pocket face z=%.3f" % [
			ball.position.z, TableConfig.LANE_POCKET_FACE_Z
		]
	)

	# Ball stayed on the +X lane side of the divider.
	assert_gt(
		ball.position.x,
		TableConfig.LANE_INNER_X - TableConfig.BALL_RADIUS,
		"ball left the lane to the field side: x=%.3f, lane inner x=%.1f" % [
			ball.position.x, TableConfig.LANE_INNER_X
		]
	)

	# Ball did not fall through the surface.
	assert_gt(
		ball.position.y,
		-TableConfig.BALL_RADIUS,
		"ball fell through the surface: y=%.3f" % ball.position.y
	)
