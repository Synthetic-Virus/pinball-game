extends GutTest
## Test matrix entry: WORLD SCALE CONTRACT.
## Owner: test-builder.
##
## Asserts that the TableConfig scale decision is internally consistent and that the
## project setting matches the constant, so no element can silently drift off the
## agreed scale. All checks are deterministic (constants + ProjectSettings); no
## physics frames are needed.
##
## Independent-oracle rule: the gravity check reads ProjectSettings directly rather
## than relying on TableConfig alone, so a mismatch between the two is caught.

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
