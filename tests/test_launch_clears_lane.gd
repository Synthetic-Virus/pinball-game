extends GutTest
## Test matrix entry: LAUNCH CLEARS THE LANE INTO PLAY (the behavioral gap that let the bug ship).
## Owner: gamedev-test-builder + gamedev-qa-lead.
## Slice: "Fix the launch" (DESIGN.md / BACKLOG.md / ARCHITECTURE.md section 13).
##
## WHY THIS EXISTS: prior slices proved the launch imparts SPEED but never that the ball ARRIVES.
## A green suite that checks the ball has velocity but not that it clears the lane is the exact gap
## that let a non-clearing launch ship. This test closes it: on the real tilted lane, a launch at
## MIN power (and a low/mid power) must drive the ball apex up-table PAST the lane exit / arch into
## the open playfield, then settle in the play area, NOT back in the lane.
##
## INDEPENDENT ORACLE: the ball's MEASURED position. Position cannot lie about whether the ball
## crossed into play or rolled back into the chute. We assert min(ball.position.z) (the apex) is
## up-table of TableConfig.LAUNCH_REACHED_PLAY_Z, and the final rest is in the open field, not the
## launch lane (x < LANE_INNER_X, z not back at the cradle).
##
## RED-TO-GREEN: written to FAIL against today's too-low floor (LAUNCH_SPEED_MIN 30 cannot clear the
## ~42-unit, ~45 u/s climb) and PASS after the floor is raised. Keep test_plunger_launch.gd and
## test_plunger_lane_size.gd GREEN alongside it.
##
## Built EXACTLY like tests/test_plunger_launch.gd so the geometry under test is what is played.

## Physics tick duration at 240 Hz.
const PHYSICS_TICK_S: float = 1.0 / 240.0

## Frames to settle the ball from spawn to rest against the plunger/pocket before a launch.
const SETTLE_FRAMES: int = 120

## Frames to let a launch fully play out: the climb up the lane, over the arch, into the field, and
## settle. 720 frames (3.0 s) is generous - a cleared launch crosses the reached-play line in a
## fraction of a second and is settling well before this; a failed launch has rolled back by then.
const PLAY_OUT_FRAMES: int = 720

const PLUNGER_SCENE: PackedScene = preload("res://scenes/elements/Plunger.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/elements/Ball.tscn")

var _world: Node3D = null
var _playfield: Node3D = null
var _plunger: Node = null
var _ball: RigidBody3D = null


func before_each() -> void:
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


## Fire a launch at the given power, play it out, and return the apex (lowest z reached) AND the
## final resting position via an out parameter dictionary. Kept as one stepping loop so the apex and
## the final rest come from the SAME run. Returns {"apex_z": float, "final": Vector3}.
func _launch_and_track(power: float) -> Dictionary:
	await _seat_and_settle()
	_plunger.test_strike_at_power(power)
	var apex_z: float = _ball.position.z
	for _i in range(PLAY_OUT_FRAMES):
		await wait_physics_frames(1)
		apex_z = minf(apex_z, _ball.position.z)
	return {"apex_z": apex_z, "final": _ball.position}


# ---- BEHAVIORAL: a MIN-power launch clears the lane into play -----------------------------
# TODO(test-builder): FILL the asserts below against the stable helper. The oracle is the ball's
# measured apex and final position. These FAIL against the current floor and PASS after the fix.

func test_min_power_launch_clears_lane_into_play() -> void:
	## A MINIMUM-power plunge (power 0.0) must clear the lane: the ball's apex crosses up-table of
	## LAUNCH_REACHED_PLAY_Z (smaller z = more up-table), proving it reached the open field, and it
	## must NOT come to rest back in the launch lane (x < LANE_INNER_X at the end).
	## ASSERT: result.apex_z < TableConfig.LAUNCH_REACHED_PLAY_Z (cleared into play).
	## ASSERT: final.x < TableConfig.LANE_INNER_X (settled in the open field, not the lane).
	## ORACLE: ball.position. The whole meter must be useful - even the weakest plunge clears.
	pending(
		"test-builder: assert apex < LAUNCH_REACHED_PLAY_Z and final.x < LANE_INNER_X at power 0.0"
	)


func test_low_mid_power_launch_clears_lane_into_play() -> void:
	## A LOW/MID-power plunge (power ~0.4) must clear the lane with MORE margin than the MIN launch:
	## the apex is further up-table. Same oracle, same assertions, a higher power. Confirms the whole
	## lower-to-mid band is live, not just the exact floor.
	## ASSERT: result.apex_z < TableConfig.LAUNCH_REACHED_PLAY_Z, and the apex is at least as far
	## up-table as the MIN launch's apex (monotonic: more power, no less reach).
	## ORACLE: ball.position.
	pending(
		"test-builder: assert apex < LAUNCH_REACHED_PLAY_Z at power ~0.4 with margin over MIN"
	)


func test_cleared_ball_settles_in_open_field_not_the_lane() -> void:
	## After a MIN launch clears, the ball must SETTLE in the open playfield, not dribble back into
	## the lane. Assert the final resting position is on the -X (open field) side of the lane divider
	## and is NOT back at the cradle Z (it did not roll all the way back down the lane).
	## ASSERT: final.x < TableConfig.LANE_INNER_X - TableConfig.BALL_RADIUS (clear of the lane).
	## ORACLE: ball.position after the play-out window.
	pending(
		"test-builder: assert the cleared ball's final position is in the open field, not the lane"
	)
