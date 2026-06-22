extends GutTest
## Test matrix entry: CAD SHOT GEOMETRY (shots are geometrically MAKEABLE; kicks point INTO play).
## Owner: lead-programmer + qa-lead. Slice: "real pinball furniture".
## Updated: slice "Table reshape + playtest fixes" (2026-06-19) - HALF_WIDTH 16 canary added.
## All wall-clearance / makeable-window checks already use TableConfig expressions, so they
## auto-follow the widen without literal changes. The canary below is the regression guard that
## catches an accidental revert of the table_config.gd widen.
##
## WHY THIS EXISTS: DESIGN must-feel #5 "shots are geometrically makeable, validated not eyeballed",
## in the spirit of Mission Pinball's "use CAD to test/plan shots" (REFERENCES.md). The layout is
## validated DETERMINISTICALLY from the TableConfig constants, NOT by looking at the rendered PNG.
## tools/table_viz.py PLOTS the same checks for the human; this GUT test ASSERTS them so CI fails
## if a bumper/sling kick aims at the drain or the standup bank sits outside flipper reach.
##
## These are pure geometry asserts on the contract constants (no physics bodies needed); they are
## fast and unambiguous. Independent oracle for "the layout is correct by construction".

## WIDEN CANARY: catches a revert of the widen before any geometry check can rely on the new scale.
func test_geometry_is_on_widened_table() -> void:
	## The shot-geometry checks below use HALF_WIDTH/LANE_INNER_X expressions throughout.
	## This canary asserts the concrete value so a stale revert to HALF_WIDTH=12 fails immediately
	## rather than silently changing every clearance threshold.
	assert_eq(
		TableConfig.HALF_WIDTH, 13.0,
		"geometry checks are calibrated for HALF_WIDTH=13 (match pink); got %f" % TableConfig.HALF_WIDTH
	)


## The MAKEABLE WINDOW for a flipped ball, expressed as an up-table Z range. A ball leaving the
## flipper tip travels up-table under the launch impulse; a "makeable" standup target sits in the
## field the ball can climb to, between the flipper tip and the arch base (a ball shot harder than
## that just rattles the arch and comes back). We model the window as:
##   far edge  = the arch base (ARCH_CENTER_Z): a hit past the arch is not a mid-field standup shot.
##   near edge = the flipper tip reach (pivot up-table by ~FLIPPER_LENGTH): closer than that and the
##               "shot" is the flipper just touching the target, not a deliberate aimed flip.
## This is the CAD discipline: assert the target is in the climbable band, not eyeball a picture.
## table_viz.py draws the flipper-tip sweep arc + the band so the human SEES the same check.
func _makeable_far_z() -> float:
	# The arch is the upper half-ellipse spanning z in [ARCH_CENTER_Z - ARCH_RADIUS_Z, ARCH_CENTER_Z]
	# (apex up-table, base where it meets the field). ARCH_CENTER_Z is where the arch meets the open
	# playfield, so it is the up-table limit of a makeable mid-field shot.
	return TableConfig.ARCH_CENTER_Z


func _makeable_near_z() -> float:
	# The flipper tip at full swing reaches roughly FLIPPER_LENGTH up-table of the pivot.
	return TableConfig.FLIPPER_PIVOT_Z - TableConfig.FLIPPER_LENGTH


# ---- STANDUP BANK is reachable from a flipper sweep ---------------------------------------------

func test_standup_bank_within_flipper_reach() -> void:
	## Each standup target's Z must sit inside the makeable window: up-table of the flipper-tip reach
	## (a deliberate aimed flip, not a touch) and down-table of the arch base (still in the open field
	## the ball can climb to, not lost in the arch). A target outside this band is an unmakeable shot.
	var far_z: float = _makeable_far_z()    # most up-table (smallest, most negative)
	var near_z: float = _makeable_near_z()  # least up-table (largest)
	for pos: Vector3 in TableConfig.STANDUP_BANK_POSITIONS:
		assert_lt(
			pos.z, near_z,
			"standup target z=%f is too close to the flippers (a touch, not a flip; near=%f)"
			% [pos.z, near_z]
		)
		assert_gt(
			pos.z, far_z,
			"standup target z=%f is past the arch base (unmakeable; far=%f)" % [pos.z, far_z]
		)


# ---- POP BUMPER cluster sits in the upper-middle, clear of walls --------------------------------

func test_pop_bumpers_in_upper_middle_clear_of_walls() -> void:
	## Each pop bumper must sit above the flippers (up-table) and inside the side walls with clearance
	## for its radius, so a ball can orbit the cluster without the body fouling a wall.
	for pos: Vector3 in TableConfig.POP_BUMPER_POSITIONS:
		assert_lt(
			pos.z, TableConfig.FLIPPER_PIVOT_Z,
			"pop bumper at z=%f must be up-table of the flippers (in the playfield, not the drain)"
			% pos.z
		)
		var clearance: float = TableConfig.HALF_WIDTH - TableConfig.POP_BUMPER_RADIUS
		assert_lt(
			absf(pos.x), clearance,
			"pop bumper at x=%f fouls a side wall (clearance %f)" % [pos.x, clearance]
		)


# ---- SLINGSHOT kicks point INTO play, never the drain -------------------------------------------

func test_slingshot_kicks_never_aim_at_drain() -> void:
	## The load-bearing "saved by the slings, never INTO the drain" geometry. Both kick directions must
	## have a strictly NEGATIVE Z (up-table) component. A positive Z would aim a kicked ball at the
	## drain - the worst possible slingshot behavior.
	assert_lt(
		TableConfig.SLINGSHOT_LEFT_KICK_DIR.z, 0.0,
		"left slingshot kick must point up-table (-z), never at the drain"
	)
	assert_lt(
		TableConfig.SLINGSHOT_RIGHT_KICK_DIR.z, 0.0,
		"right slingshot kick must point up-table (-z), never at the drain"
	)
	# Toward-center X sign per side (left of center kicks +x, right kicks -x).
	assert_gt(
		TableConfig.SLINGSHOT_LEFT_KICK_DIR.x, 0.0,
		"left slingshot must kick toward center (+x)"
	)
	assert_lt(
		TableConfig.SLINGSHOT_RIGHT_KICK_DIR.x, 0.0,
		"right slingshot must kick toward center (-x)"
	)


# ---- The kick-impulse contract is internally consistent ----------------------------------------

func test_kick_impulse_bounds_are_sane() -> void:
	## The floor < nominal < cap, and the cap is strictly inside the no-tunneling stress band (the
	## stress test fires at 2x LAUNCH_SPEED_MAX). A cap >= the stress speed would mean a kick could
	## produce a speed the stress test never proved safe.
	assert_lt(
		TableConfig.KICK_MIN_OUTGOING_SPEED, TableConfig.KICK_IMPULSE_SPEED,
		"the kick floor must be below the nominal kick speed"
	)
	assert_lt(
		TableConfig.KICK_IMPULSE_SPEED, TableConfig.KICK_MAX_OUTGOING_SPEED,
		"the nominal kick speed must be below the CCD-safe cap"
	)
	assert_lt(
		TableConfig.KICK_MAX_OUTGOING_SPEED, 2.0 * TableConfig.LAUNCH_SPEED_MAX,
		"the kick cap must be strictly inside the no-tunneling stress band (2x LAUNCH_SPEED_MAX)"
	)
