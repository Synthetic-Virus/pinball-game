extends GutTest
## Test matrix entry: INTEGRATED SOFT-LOCK RECOVERY in the real built Table.tscn (the slice's #1
## correctness fix, end to end). Owner: lead-programmer (polish pass, QA finding B2) + test-builder.
## Slice: "Playtest fixes 2".
##
## WHY THIS EXISTS (QA B2): tests/test_soft_lock_recovery.gd is a good UNIT test - it drives
## GameFlow.tick_launch_watch directly with a measured Z. But that bypasses the INTEGRATION path the
## bug actually lived on: table.gd feeding ball.position.z into tick_launch_watch every physics
## frame (table.gd _physics_process), the plunger's ball_launched -> GameFlow.on_ball_launched, and
## GameFlow.request_relaunch -> _on_request_new_ball re-arming the real plunger. The BUG-012/013/014
## history proves integration bugs sail through green unit suites here, so this file closes the gap:
## it instances the REAL Table.tscn, bypasses the plunger and calls game_flow.on_ball_launched()
## directly so the ball stays stationary in the lane, lets the real watchdog run past the settle
## window, and asserts the ball is recoverable (plunger RE-ARMED) and NO ball was spent - exactly
## the soft-lock the slice exists to kill, judged on the live tree.
##
## QA BUG-033 FIX (2026-06-20): the previous version fired test_strike_at_power(0.0) believing that
## was a "too-weak launch that never reaches play". With the Fix-the-launch slice raising
## PLUNGER_STROKE_SPEED_MIN to 60 u/s, the minimum launch now delivers ~60 u/s to the ball and
## carries it ~73 units up-table - far past the reached-play line at 16.5. So power 0.0 ALWAYS
## transitions the game to BALL_IN_PLAY, making the watchdog recovery assertions wrong. The correct
## approach (BUG-033 fix direction Option A) is to BYPASS the plunger entirely: call
## game_flow.on_ball_launched() directly, which enters LAUNCHING with the ball stationary in the
## lane (is_touching never fires; no impulse transfers; the ball just sits there). The real watchdog
## in table.gd's _physics_process then feeds the stationary ball's lane Z into tick_launch_watch
## every frame, and after LAUNCH_SETTLE_TIME_S the watchdog correctly sees "ball never crossed the
## reached-play line" and recovers. This is the genuine failed-launch scenario on the real tree.
##
## INDEPENDENT-ORACLE RULE: assertions read the REAL plunger.is_armed(), the REAL GameFlow signals
## (balls_changed / request_relaunch), and the REAL ball position, never a self-reported "recovered"
## flag.

const TableScene: PackedScene = preload("res://scenes/Table.tscn")

var _table: Node3D = null


func before_each() -> void:
	_table = TableScene.instantiate() as Node3D
	add_child_autofree(_table)
	# Let _ready() build the whole tree (geometry, dynamic elements, flow, wiring). The table now boots
	# to a main menu instead of auto-starting, so choosing PLAY is what arms the first ball - call the
	# same entry point here.
	await wait_frames(3)
	if _table.has_method("start_play"):
		_table.start_play()
	await wait_frames(2)


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


# ---- The headline integration assertion: a too-weak launch is recoverable on the live tree -------

func test_weak_launch_in_live_table_re_arms_without_spending_a_ball() -> void:
	## Simulate a FAILED LAUNCH on the live table: bypass the plunger and call
	## game_flow.on_ball_launched() directly so the ball stays STATIONARY in the lane. The real
	## watchdog in table.gd's _physics_process measures the stationary ball's Z each frame and, after
	## LAUNCH_SETTLE_TIME_S, concludes the ball never reached play and fires the recovery path:
	## plunger RE-ARMED, NO ball spent. This is the exact soft-lock the slice kills.
	##
	## WHY we bypass the plunger (QA BUG-033): test_strike_at_power(0.0) now delivers ~60 u/s
	## (PLUNGER_STROKE_SPEED_MIN raised from 30 to 60 in the Fix-the-launch slice), which carries the
	## ball ~73 units up-table - always crossing the reached-play line at 16.5. So a real plunger
	## strike, even at minimum power, ALWAYS reaches play and the recovery watchdog is never triggered.
	## Calling on_ball_launched() directly enters LAUNCHING with the ball sitting still in the lane,
	## which IS the genuine "ball stalled in the chute" failure mode the watchdog was built for.
	var plunger: Node = _find_named("Plunger")
	var game_flow: Node = _find_named("GameFlow")
	var ball: Node3D = _find_named("Ball") as Node3D
	assert_not_null(plunger, "the built Table must contain the Plunger")
	assert_not_null(game_flow, "the built Table must contain GameFlow")
	assert_not_null(ball, "the built Table must contain the Ball")
	if plunger == null or game_flow == null or ball == null:
		return

	# Let the ball settle in the lane first so the watchdog sees a realistic lane Z from frame 1.
	await wait_physics_frames(180)

	# The plunger should be armed for the first ball (start_game -> request_new_ball -> arm).
	assert_true(plunger.is_armed(), "the plunger must start armed for the first ball")

	# Watch the flow signals so we can prove NO ball was spent and a relaunch WAS requested.
	watch_signals(game_flow)

	# BYPASS the plunger: call on_ball_launched() directly on game_flow. This mimics the signal
	# the plunger would emit, but without actually driving the face or transferring momentum. The ball
	# stays put in the lane. table.gd's _physics_process will call tick_launch_watch(ball.position.z,
	# delta) every frame with the lane-Z (never crossing LAUNCH_REACHED_PLAY_Z), so the watchdog runs
	# and fires the recovery after LAUNCH_SETTLE_TIME_S. The plunger also needs to be disarmed
	# manually (the real plunger disarms itself in _do_launch; we mirror that here so is_armed()
	# reflects "in-flight" and the post-recovery re-arm is the measurable event).
	if plunger.has_method("disarm"):
		plunger.disarm()
	game_flow.on_ball_launched()

	# Verify the state machine entered LAUNCHING (prerequisite for the watchdog to run).
	assert_eq(
		game_flow.current_state(),
		game_flow.State.LAUNCHING,
		"on_ball_launched() must enter LAUNCHING so the watchdog can detect the failed launch"
	)
	# The plunger is disarmed (we called disarm() above, mirroring what _do_launch does in production).
	assert_false(plunger.is_armed(), "the plunger must be disarmed while the ball is 'in flight'")

	# Let the real watchdog run well past the settle window. table.gd feeds ball.position.z to
	# tick_launch_watch every physics frame; the stationary ball's Z stays in the lane, so the
	# watchdog will see LAUNCH_SETTLE_TIME_S pass without the ball crossing the reached-play line
	# and will fire the recovery. Wait settle time + 1 second of margin.
	var settle_frames: int = int((TableConfig.LAUNCH_SETTLE_TIME_S + 1.0) * 240.0)
	await wait_physics_frames(settle_frames)

	# RECOVERY: the plunger is re-armed for the SAME ball so the player can pull again (no dead state).
	assert_true(
		plunger.is_armed(),
		"after a stalled (stationary) launch the plunger must RE-ARM (no soft-lock) - QA B2/BUG-033"
	)
	# Back to READY_TO_LAUNCH, recovered, not stuck in LAUNCHING or BALL_IN_PLAY.
	assert_eq(
		game_flow.current_state(),
		game_flow.State.READY_TO_LAUNCH,
		"a failed launch must recover to READY_TO_LAUNCH on the live tree - QA B2"
	)
	# request_relaunch fired (the recovery path), and crucially NO ball was spent.
	assert_signal_emitted(
		game_flow,
		"request_relaunch",
		"the live recovery must request a relaunch (re-seat + re-arm the SAME ball)"
	)
	assert_signal_not_emitted(
		game_flow,
		"balls_changed",
		"a failed launch must NOT spend a ball (no balls_changed during recovery) - QA B2"
	)
	assert_signal_not_emitted(
		game_flow,
		"game_over",
		"a failed launch must never end the game"
	)
