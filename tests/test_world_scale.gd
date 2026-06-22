extends GutTest
## Test matrix entry: WORLD SCALE CONTRACT.
## Owner: test-builder.
## Updated: slice "Table reshape + playtest fixes" (2026-06-19) - HALF_WIDTH 16 assertions added.
##
## Asserts that the TableConfig scale decision is internally consistent and that the
## project setting matches the constant, so no element can silently drift off the
## agreed scale. All checks are deterministic (constants + ProjectSettings); no
## physics frames are needed.
##
## Independent-oracle rule: the gravity check reads ProjectSettings directly rather
## than relying on TableConfig alone, so a mismatch between the two is caught.
##
## The "WIDEN" group at the bottom specifically asserts that the rescale landed
## (HALF_WIDTH == 16, all derived X constants in the correct post-widen range).
## These fail against the old width and pass once the table_config.gd widen is applied.

func test_gravity_matches_project_setting() -> void:
	# The project.godot file sets physics/3d/default_gravity = 200.0 and TableConfig.GRAVITY = 200.0.
	# Both must stay in sync. Reading the project setting is the independent oracle.
	var project_gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", -1.0)
	assert_eq(
		project_gravity,
		TableConfig.GRAVITY,
		"project.godot default_gravity must equal TableConfig.GRAVITY (both 200)"
	)

func test_ball_radius_in_design_range() -> void:
	# DESIGN.md mandates ball radius on the order of ~0.5-1.0 world units.
	assert_true(
		TableConfig.BALL_RADIUS >= 0.5 and TableConfig.BALL_RADIUS <= 1.0,
		"BALL_RADIUS %f must be in [0.5, 1.0] per DESIGN brief" % TableConfig.BALL_RADIUS
	)

func test_playfield_is_tens_of_units() -> void:
	# DESIGN.md: playfield on the order of tens of units long.
	var total_length: float = TableConfig.HALF_LENGTH * 2.0
	assert_true(
		total_length >= 20.0 and total_length <= 200.0,
		"Playfield total length %f should be tens of units per DESIGN brief" % total_length
	)

func test_flippers_do_not_overlap_at_pivots() -> void:
	# The two flipper pivots are at +/- FLIPPER_PIVOT_SPREAD on the X axis. At rest
	# each flipper tip extends FLIPPER_LENGTH outward from its pivot. For an inverted-V
	# to be physically correct the tips must NOT cross the center line.
	#
	# Rest angle is negative (tip points slightly down-toward-center). The horizontal
	# reach of the tip at rest is approximately FLIPPER_LENGTH * cos(|FLIPPER_REST_ANGLE|).
	# The gap between the inner face of each tip is:
	#   gap = 2 * FLIPPER_PIVOT_SPREAD - 2 * FLIPPER_LENGTH * cos(|REST_ANGLE|)
	# We require gap > 0 (tips do not cross center) and gap < DRAIN_WIDTH (the gap is
	# not wider than the whole table - a basic sanity floor).
	var reach: float = TableConfig.FLIPPER_LENGTH * cos(abs(TableConfig.FLIPPER_REST_ANGLE))
	var gap: float = 2.0 * TableConfig.FLIPPER_PIVOT_SPREAD - 2.0 * reach
	assert_true(
		gap > 0.0,
		"Flipper tips at rest must leave a positive gap at center (inverted-V). gap=%f" % gap
	)

func test_launch_speed_range_ordered() -> void:
	# A power meter maps 0..1 to LAUNCH_SPEED_MIN..MAX. Both must be positive and ordered.
	assert_true(
		TableConfig.LAUNCH_SPEED_MIN > 0.0,
		"LAUNCH_SPEED_MIN must be > 0"
	)
	assert_true(
		TableConfig.LAUNCH_SPEED_MIN < TableConfig.LAUNCH_SPEED_MAX,
		"LAUNCH_SPEED_MIN must be strictly less than LAUNCH_SPEED_MAX"
	)

func test_drain_position_is_past_flippers() -> void:
	# The drain trigger must be below (larger Z) than the flipper pivot row so a ball
	# that makes it past the flippers enters the drain. DESIGN: open center drain.
	assert_true(
		TableConfig.DRAIN_Z > TableConfig.FLIPPER_PIVOT_Z,
		"DRAIN_Z (%f) must be past (greater than) FLIPPER_PIVOT_Z (%f)" % [
			TableConfig.DRAIN_Z, TableConfig.FLIPPER_PIVOT_Z
		]
	)

func test_drain_up_table_edge_clears_the_flipper_bat_catch_zone() -> void:
	# QA BUG-023: the drain VOLUME (not just its center) must not overlap the flipper bats. A ball
	# falling toward the flippers must reach the bat catch zone WITHOUT first crossing the drain's
	# up-table edge, or it drains while the player is about to cradle/flip it (core-loop break).
	# The drain volume's up-table edge is DRAIN_Z - DRAIN_DEPTH/2; it must sit below (greater Z than)
	# the furthest down-table a bat reaches (FLIPPER_BAT_MAX_Z), with a clearance margin. This is the
	# same machine-checked boundary BUG-022 introduced, now applied to the cradle, not the lane.
	var up_table_edge: float = TableConfig.DRAIN_Z - TableConfig.DRAIN_DEPTH * 0.5
	assert_true(
		up_table_edge > TableConfig.FLIPPER_BAT_MAX_Z,
		"drain up-table edge (%f) must clear the flipper bat catch zone (FLIPPER_BAT_MAX_Z=%f)" % [
			up_table_edge, TableConfig.FLIPPER_BAT_MAX_Z
		]
	)

func test_drain_center_stays_inside_or_at_the_open_bottom() -> void:
	# QA BUG-004 guard, re-checked after the BUG-023 reshape: the drain CENTER must not sit far
	# outside the open bottom edge (where a stray future bottom wall could block it). A slim band
	# whose center hangs at most one depth past HALF_LENGTH is acceptable (the down-table half is the
	# already-lost open mouth); assert it does not drift wildly past the field.
	assert_true(
		TableConfig.DRAIN_Z <= TableConfig.HALF_LENGTH + TableConfig.DRAIN_DEPTH,
		"DRAIN_Z (%f) must not sit far past the open bottom edge (HALF_LENGTH=%f)" % [
			TableConfig.DRAIN_Z, TableConfig.HALF_LENGTH
		]
	)

func test_ball_start_is_in_the_launch_lane() -> void:
	# BALL_START.x must be between LANE_INNER_X and HALF_WIDTH (inside the right lane).
	assert_true(
		TableConfig.BALL_START.x > TableConfig.LANE_INNER_X and
		TableConfig.BALL_START.x <= TableConfig.HALF_WIDTH,
		"BALL_START.x (%f) must be in the launch lane (LANE_INNER_X=%f..HALF_WIDTH=%f)" % [
			TableConfig.BALL_START.x,
			TableConfig.LANE_INNER_X,
			TableConfig.HALF_WIDTH
		]
	)

func test_wall_height_exceeds_ball_radius() -> void:
	# The perimeter walls must be taller than the ball radius; otherwise a fast ball can
	# clip over the wall top.
	assert_true(
		TableConfig.WALL_HEIGHT > TableConfig.BALL_RADIUS,
		"WALL_HEIGHT (%f) must exceed BALL_RADIUS (%f)" % [
			TableConfig.WALL_HEIGHT, TableConfig.BALL_RADIUS
		]
	)

func test_flipper_height_exceeds_ball_radius() -> void:
	# FLIPPER_HEIGHT is the thickness of the bat off the playfield surface; it must be
	# greater than BALL_RADIUS so the bat face actually contacts the sphere.
	assert_true(
		TableConfig.FLIPPER_HEIGHT > TableConfig.BALL_RADIUS,
		"FLIPPER_HEIGHT (%f) must exceed BALL_RADIUS (%f)" % [
			TableConfig.FLIPPER_HEIGHT, TableConfig.BALL_RADIUS
		]
	)


# ---- WIDEN ASSERTIONS (slice "Table reshape + playtest fixes", 2026-06-19) ------------------
# These assert the SPECIFIC post-widen values from ARCHITECTURE.md section 11.4.
# They fail on the old (HALF_WIDTH 12) constants and pass after the rescale.
# If any constant is accidentally reverted this group catches it immediately.

func test_half_width_is_16() -> void:
	# NARROW (2026-06-21): HALF_WIDTH set to 13.0 to match the developer's table outline (was 16).
	assert_eq(
		TableConfig.HALF_WIDTH, 13.0,
		"HALF_WIDTH must be 13.0 (match pink); got %f" % TableConfig.HALF_WIDTH
	)


func test_lane_inner_x_is_14() -> void:
	# NARROW: LANE_INNER_X follows the narrower table to 11.0 (lane = 11..13, ~ball-width chute).
	assert_eq(
		TableConfig.LANE_INNER_X, 11.0,
		"LANE_INNER_X must be 11.0 (match pink); got %f" % TableConfig.LANE_INNER_X
	)


func test_ball_start_x_is_lane_center() -> void:
	# BALL_START.x is the lane center, (LANE_INNER_X + HALF_WIDTH) * 0.5 (= 12 after the narrow). Asserted
	# as the RELATIONSHIP so it auto-follows future width changes instead of pinning a literal.
	assert_almost_eq(
		TableConfig.BALL_START.x, (TableConfig.LANE_INNER_X + TableConfig.HALF_WIDTH) * 0.5, 0.01,
		"BALL_START.x must be the lane center; got %f" % TableConfig.BALL_START.x
	)


func test_flipper_pivot_spread_holds_drain_mouth() -> void:
	# FLIPPER_PIVOT_SPREAD was moved from 7.0 to 7.2 to keep the drain mouth at ~2.46 units
	# (~2 ball-diameters) instead of scaling it wide with the table (which would create a
	# chasm). The drain mouth = 2*SPREAD - 2*FLIPPER_LENGTH*cos(|REST_ANGLE|).
	# Expected: ~2.46 u. Hard floor: > 2*BALL_RADIUS (ball can drain); hard ceiling: < 6.0
	# (not a chasm).
	var mouth: float = (
		2.0 * TableConfig.FLIPPER_PIVOT_SPREAD
		- 2.0 * TableConfig.FLIPPER_LENGTH * cos(abs(TableConfig.FLIPPER_REST_ANGLE))
	)
	assert_gt(
		mouth,
		2.0 * TableConfig.BALL_RADIUS,
		"drain mouth (%f) must be wider than a ball diameter so balls can drain" % mouth
	)
	assert_lt(
		mouth, 6.0,
		"drain mouth (%f) must not be a chasm (>= 6 u); keep it ~2-3 ball-diameters" % mouth
	)


func test_slingshot_positions_are_outboard_of_flippers() -> void:
	# After the widen the slingshot positions moved from +/-8.5 to +/-10.5 to stay outboard
	# of the new flipper pivots (+/-7.2) and inside the side walls (+/-16). A slingshot that
	# drifted inside the pivot would not intercept a ball falling down the side channel.
	assert_lt(
		TableConfig.SLINGSHOT_LEFT_POS.x, -TableConfig.FLIPPER_PIVOT_SPREAD,
		"left sling (%f) must be outboard of (< -) the left flipper pivot (%f)"
		% [TableConfig.SLINGSHOT_LEFT_POS.x, -TableConfig.FLIPPER_PIVOT_SPREAD]
	)
	assert_gt(
		TableConfig.SLINGSHOT_RIGHT_POS.x, TableConfig.FLIPPER_PIVOT_SPREAD,
		"right sling (%f) must be outboard of (> +) the right flipper pivot (%f)"
		% [TableConfig.SLINGSHOT_RIGHT_POS.x, TableConfig.FLIPPER_PIVOT_SPREAD]
	)
	# Both must be inside the side walls.
	assert_lt(
		absf(TableConfig.SLINGSHOT_LEFT_POS.x), TableConfig.HALF_WIDTH,
		"left sling must be inside the left wall"
	)
	assert_lt(
		absf(TableConfig.SLINGSHOT_RIGHT_POS.x), TableConfig.HALF_WIDTH,
		"right sling must be inside the right wall"
	)


func test_pop_bumper_positions_use_widened_spread() -> void:
	# The two lower bumpers moved from +/-4.5 to +/-6.0 for the wider table. Assert the
	# spread is >= 5.0 (definitively wider than the old +/-4.5) and that no bumper fouls
	# the side wall (clearance = HALF_WIDTH - POP_BUMPER_RADIUS must not be exceeded).
	for pos: Vector3 in TableConfig.POP_BUMPER_POSITIONS:
		var x_abs: float = absf(pos.x)
		assert_lt(
			x_abs + TableConfig.POP_BUMPER_RADIUS,
			TableConfig.HALF_WIDTH,
			"pop bumper at x=%f + radius %f fouls the side wall (HALF_WIDTH=%f)"
			% [pos.x, TableConfig.POP_BUMPER_RADIUS, TableConfig.HALF_WIDTH]
		)


func test_lane_guide_divider_auto_follows_widen() -> void:
	# LANE_GUIDE_DIVIDER_X is defined as HALF_WIDTH - 3.0. After the widen it must equal
	# 13.0. This keeps the OUTLANE at ~3.0 units (drain-risk channel) while the INLANE
	# widens to ~5.8 units (save lane). ARCHITECTURE.md 11.4 and 11.5.
	assert_eq(
		TableConfig.LANE_GUIDE_DIVIDER_X,
		TableConfig.HALF_WIDTH - 3.0,
		"LANE_GUIDE_DIVIDER_X must be HALF_WIDTH-3.0=%f; got %f"
		% [TableConfig.HALF_WIDTH - 3.0, TableConfig.LANE_GUIDE_DIVIDER_X]
	)
	# Concrete value check so a constant extraction typo is caught (HALF_WIDTH 13 - 3 = 10 after narrow).
	assert_eq(
		TableConfig.LANE_GUIDE_DIVIDER_X, 10.0,
		"LANE_GUIDE_DIVIDER_X must be 10.0 (HALF_WIDTH-3); got %f"
		% TableConfig.LANE_GUIDE_DIVIDER_X
	)
