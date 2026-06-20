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

func test_report_delivered_speed_min_mid_max() -> void:
	## Measure the delivered ball speed at MIN / MID / MAX and report it. Pre-fix this confirms cause
	## (a): the MIN delivered speed is below the ~45.3 u/s climb requirement. Post-fix the MIN
	## delivered speed must EXCEED the climb requirement plus the measured rattle/friction loss.
	## ASSERT (post-fix): delivered_min >= the climb requirement (~45.3) plus a margin the physics-
	## programmer sets from the measurement. ALSO assert delivered_max <= LAUNCH_SPEED_MAX * ~1.1
	## (no double-energy spike) and delivered_max >= 1.5 * delivered_min (the spread holds).
	pending(
		"physics-programmer: fire MIN/MID/MAX, gd_print + assert delivered speeds; report the numbers"
	)


func test_report_apex_min_mid_max() -> void:
	## Measure the apex (lowest z) at MIN / MID / MAX and report it. Pre-fix this confirms the symptom:
	## the MIN (and likely MID) apex STALLS down-table of LAUNCH_REACHED_PLAY_Z and the ball rolls
	## back. Post-fix the MIN apex must CLEAR LAUNCH_REACHED_PLAY_Z (cross up-table of it).
	## ASSERT (post-fix): apex_min < LAUNCH_REACHED_PLAY_Z (more up-table / smaller z than the line),
	## i.e. even the weakest plunge reaches play. This is the diagnostic twin of the behavioral
	## lane-clear oracle in test_launch_clears_lane.gd.
	pending(
		"physics-programmer: fire MIN/MID/MAX, gd_print + assert apex clears LAUNCH_REACHED_PLAY_Z"
	)
