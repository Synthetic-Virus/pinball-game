extends GutTest
## Test matrix entry: LAUNCH DIAGNOSTIC (measure-first, do NOT guess).
## Owner: gamedev-physics-programmer (fills the measurement + the assert) + gamedev-test-builder.
## Slice: "Fix the launch" (DESIGN.md / BACKLOG.md / ARCHITECTURE.md section 13).
##
## WHY THIS EXISTS: the deployed launch climbs the chute, stalls, and rolls back across the lower
## half of the meter. The slice rule is MEASURE the cause before tuning anything. This harness fires
## the REAL plunger strike at MIN / MID / MAX power on the REAL tilted lane geometry and records,
## per power level, (a) the delivered ball speed just after the strike, and (b) the APEX (the lowest
## z, most up-table, the ball reaches before rolling back). Those six numbers name the true cause:
##   (a) FLOOR TOO LOW   - delivered speed at MIN below the ~45.3 u/s climb requirement, apex stalls
##                         down-table of LAUNCH_REACHED_PLAY_Z.
##   (b) IMPULSE UNDER-DELIVERS - delivered speed at MAX below LAUNCH_SPEED_MAX.
##   (c) RATTLE / FRICTION STALL - apex falls well short of what the measured speed predicts.
## After the fix this stays a permanent gate: the apex at MIN must clear LAUNCH_REACHED_PLAY_Z.
##
## INDEPENDENT ORACLE: every number is read from the REAL ball (current_speed / position.z), never a
## self-reported counter. Position and speed cannot lie about how fast or how far the ball went.
##
## Built EXACTLY like tests/test_plunger_launch.gd (rotated TILT_DEG Playfield, real TableGeometry,
## shipping Plunger.tscn + Ball.tscn) so the diagnosis is on the geometry the player actually plays.

## Physics tick duration at 240 Hz.
const PHYSICS_TICK_S: float = 1.0 / 240.0

## Frames to settle the ball from spawn to rest against the plunger/pocket before a strike.
const SETTLE_FRAMES: int = 120

## Frames to sample for the delivered-speed PEAK just after a strike: long enough to capture the
## impulse peak, short enough the ball is still in the straight lane (no arch bounce inflates it).
const PEAK_SAMPLE_FRAMES: int = 12

## Frames to track the apex (the up-table climb) before the ball rolls back. A successful launch
## crosses the field in well under a second; an unsuccessful one stalls and rolls back inside ~2 s.
## 480 frames (2.0 s) covers both the climb and the roll-back so min(z) is the true apex.
const APEX_TRACK_FRAMES: int = 480

const PLUNGER_SCENE: PackedScene = preload("res://scenes/elements/Plunger.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/elements/Ball.tscn")

var _world: Node3D = null
var _playfield: Node3D = null
var _plunger: Node = null
var _ball: RigidBody3D = null


func before_each() -> void:
	# Build the tilted Playfield + real geometry exactly like test_plunger_launch.gd. The tilt is
	# load-bearing: it provides the down-slope deceleration the climb must overcome.
	_world = Node3D.new()
	add_child_autofree(_world)

	_playfield = Node3D.new()
	_playfield.name = "Playfield"
	_playfield.rotation_degrees = Vector3(TableConfig.TILT_DEG, 0.0, 0.0)
	_world.add_child(_playfield)

	TableGeometry.build(_playfield)

	_plunger = PLUNGER_SCENE.instantiate()
	_plunger.name = "Plunger"
	_plunger.position = Vector3.ZERO
	_playfield.add_child(_plunger)

	_ball = BALL_SCENE.instantiate() as RigidBody3D
	_ball.name = "Ball"
	_playfield.add_child(_ball)
	_plunger.set_ball(_ball)

	_ball.reset_to_start()


# ---- Helpers -----------------------------------------------------------------------

## Reset the ball to the lane start and let it settle to rest against the plunger/pocket.
func _seat_and_settle() -> void:
	_ball.reset_to_start()
	await wait_physics_frames(SETTLE_FRAMES)


## Fire a strike at the given power and return the PEAK delivered speed over the first few frames.
## ORACLE: ball.current_speed() sampled at peak.
func _measure_delivered_speed(power: float) -> float:
	await _seat_and_settle()
	_plunger.test_strike_at_power(power)
	var peak: float = 0.0
	for _i in range(PEAK_SAMPLE_FRAMES):
		await wait_physics_frames(1)
		peak = maxf(peak, _ball.current_speed())
	return peak


## Fire a strike at the given power and return the APEX: the lowest (most up-table) z the ball
## reaches before rolling back. ORACLE: min(ball.position.z) tracked each frame.
func _measure_apex(power: float) -> float:
	await _seat_and_settle()
	_plunger.test_strike_at_power(power)
	var apex_z: float = _ball.position.z
	for _i in range(APEX_TRACK_FRAMES):
		await wait_physics_frames(1)
		apex_z = minf(apex_z, _ball.position.z)
	return apex_z


# ---- DIAGNOSTIC: report the six numbers and name the cause ------------------------------
# TODO(physics-programmer): FILL the body of each measurement test. Fire MIN (0.0) / MID (0.5) /
# MAX (1.0), gd-print the delivered speed and apex, and assert the post-fix expectation. Report the
# six measured numbers (speed + apex at each power) in the slice deliverable. The signatures and
# helpers above are STABLE so the test-builder can write test_launch_clears_lane.gd against the same
# rig in parallel.

## The frictionless climb requirement to crest the arch center, in u/s. Derived from the geometry
## (see table_config.gd LAUNCH_SPEED_MIN WHY note): sqrt(2 * GRAVITY*sin(TILT) * climb), where the
## climb is BALL_START.z to ARCH_CENTER_Z. Read LIVE so it tracks the geometry, never hardcoded.
func _arch_crest_requirement() -> float:
	var decel: float = TableConfig.GRAVITY * sin(deg_to_rad(TableConfig.TILT_DEG))
	var climb: float = TableConfig.BALL_START.z - TableConfig.ARCH_CENTER_Z
	return sqrt(2.0 * decel * climb)


func test_report_delivered_speed_min_mid_max() -> void:
	## Measure the delivered ball speed at MIN / MID / MAX and report it. Pre-fix this confirmed cause
	## (a): the MIN delivered speed was below the ~45.3 u/s climb requirement. Post-fix (floor raised
	## to LAUNCH_SPEED_MIN 60 / PLUNGER_STROKE_SPEED_MIN 60) the MIN delivered speed must EXCEED the
	## climb requirement, and the MAX must stay under the double-energy ceiling while the spread holds.
	var delivered_min: float = await _measure_delivered_speed(0.0)
	var delivered_mid: float = await _measure_delivered_speed(0.5)
	var delivered_max: float = await _measure_delivered_speed(1.0)
	var required: float = _arch_crest_requirement()
	# Report the six-number diagnosis to the CI log (the slice deliverable reads these back).
	gut.p("LAUNCH DIAGNOSTIC (delivered speed): MIN=%.2f MID=%.2f MAX=%.2f u/s; arch-crest req=%.2f"
		% [delivered_min, delivered_mid, delivered_max, required])

	# (a) FLOOR: even the weakest plunge must out-deliver the frictionless arch-crest requirement,
	# with headroom for the friction loss the lane bleeds. The raised floor (~60) clears ~45.3 easily.
	assert_gt(
		delivered_min,
		required,
		"MIN delivered speed %.2f must exceed the arch-crest requirement %.2f (raised floor)"
		% [delivered_min, required]
	)
	# (b) IMPULSE: a full strike must land in the design band, not under-deliver and not double-spike.
	assert_lt(
		delivered_max,
		TableConfig.LAUNCH_SPEED_MAX * 1.1,
		"MAX delivered speed %.2f exceeded the double-energy ceiling %.2f"
		% [delivered_max, TableConfig.LAUNCH_SPEED_MAX * 1.1]
	)
	# Monotonic: more meter -> more speed. The spread is MODEST by design (1.2x floor, not 1.5x): the
	# CCD-safe ceiling caps MAX (LAUNCH_SPEED_MAX 90 - raising it to 110 made a stress bounce exceed
	# the 120 no-tunnel cap) and the HIGH top-exit lane forces a high MIN to clear, so a wide spread
	# is physically incompatible with tunneling safety. Widen the feel later by lowering the lane exit.
	assert_gt(delivered_mid, delivered_min, "MID must out-deliver MIN (monotonic)")
	assert_gte(
		delivered_max,
		1.2 * delivered_min,
		"MAX delivered %.2f must be >= 1.2x MIN delivered %.2f (modest CCD-capped spread)"
		% [delivered_max, delivered_min]
	)


func test_report_apex_min_mid_max() -> void:
	## Measure the apex (lowest z) at MIN / MID / MAX and report it. Pre-fix this confirmed the
	## symptom: the MIN (and MID) apex STALLED down-table of LAUNCH_REACHED_PLAY_Z and rolled back.
	## Post-fix the MIN apex must CLEAR LAUNCH_REACHED_PLAY_Z (cross up-table of it = smaller z). This
	## is the diagnostic twin of the behavioral lane-clear oracle in test_launch_clears_lane.gd.
	var apex_min: float = await _measure_apex(0.0)
	var apex_mid: float = await _measure_apex(0.5)
	var apex_max: float = await _measure_apex(1.0)
	gut.p("LAUNCH DIAGNOSTIC (apex z, smaller=more up-table): MIN=%.2f MID=%.2f MAX=%.2f; line=%.2f"
		% [apex_min, apex_mid, apex_max, TableConfig.LAUNCH_REACHED_PLAY_Z])

	# Even the weakest plunge must cross up-table of the reached-play line (smaller z than the line).
	assert_lt(
		apex_min,
		TableConfig.LAUNCH_REACHED_PLAY_Z,
		"MIN apex %.2f must clear (be up-table of) LAUNCH_REACHED_PLAY_Z %.2f"
		% [apex_min, TableConfig.LAUNCH_REACHED_PLAY_Z]
	)
	# The LaneExitDeflector CAPS the apex: every sufficient launch meets the same ~45-degree wall at
	# the lane top and turns into the field, so apex is NOT strictly monotonic in power by design (MID
	# and MAX both top out at the deflector). The meaningful gate is that ALL powers CLEAR the play
	# line (cross up-table of it), which is what makes the launch reliable.
	assert_lt(apex_mid, TableConfig.LAUNCH_REACHED_PLAY_Z, "MID apex must clear the play line")
	assert_lt(apex_max, TableConfig.LAUNCH_REACHED_PLAY_Z, "MAX apex must clear the play line")
