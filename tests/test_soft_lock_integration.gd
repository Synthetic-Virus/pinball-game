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
## it instances the REAL Table.tscn, fires a TOO-WEAK strike through the real plunger, lets the real
## watchdog run past the settle window, and asserts the ball is recoverable (plunger RE-ARMED) and
## NO ball was spent - exactly the soft-lock the slice exists to kill, judged on the live tree.
##
## INDEPENDENT-ORACLE RULE: assertions read the REAL plunger.is_armed(), the REAL GameFlow signals
## (balls_changed / request_relaunch), and the REAL ball position, never a self-reported "recovered"
## flag.

const TableScene: PackedScene = preload("res://scenes/Table.tscn")

var _table: Node3D = null


func before_each() -> void:
	_table = TableScene.instantiate() as Node3D
	add_child_autofree(_table)
	# Let _ready() build the whole tree (geometry, dynamic elements, flow, wiring) and run start_game.
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


# ---- The headline integration assertion: a too-weak launch is recoverable on the live tree -------

func test_weak_launch_in_live_table_re_arms_without_spending_a_ball() -> void:
	## Fire the WEAKEST strike (power 0.0) through the real plunger in the built table. The ball never
	## reaches play, so after LAUNCH_SETTLE_TIME_S the watchdog (fed by table.gd's _physics_process)
	## must recover: the plunger is RE-ARMED for the SAME ball and NO ball is spent. This is the exact
	## soft-lock the slice kills, exercised through the integration path the unit test cannot reach.
	var plunger: Node = _find_named("Plunger")
	var game_flow: Node = _find_named("GameFlow")
	var ball: Node3D = _find_named("Ball") as Node3D
	assert_not_null(plunger, "the built Table must contain the Plunger")
	assert_not_null(game_flow, "the built Table must contain GameFlow")
	assert_not_null(ball, "the built Table must contain the Ball")
	if plunger == null or game_flow == null or ball == null:
		return

	# Let the ball settle against the plunger face in the lane first (so the strike has real contact).
	await wait_physics_frames(180)

	# The plunger should be armed for the first ball (start_game -> request_new_ball -> arm).
	assert_true(plunger.is_armed(), "the plunger must start armed for the first ball")

	# Watch the flow signals so we can prove NO ball was spent and a relaunch WAS requested.
	watch_signals(game_flow)

	# Fire the weakest possible strike. The test hook drives _do_launch at power 0.0 exactly as a
	# release at the bottom of the meter would; production launch still comes from the contact impulse.
	assert_true(
		plunger.has_method("test_strike_at_power"),
		"the plunger must expose test_strike_at_power (the headless strike hook)"
	)
	plunger.test_strike_at_power(0.0)

	# The strike fired ball_launched -> LAUNCHING and disarmed the plunger for the in-flight ball.
	assert_false(plunger.is_armed(), "the plunger disarms while the launched ball is in flight")
	assert_eq(
		game_flow.current_state(),
		game_flow.State.LAUNCHING,
		"firing the plunger must enter LAUNCHING (not straight to BALL_IN_PLAY)"
	)

	# Let the real watchdog run well past the settle window. table.gd feeds ball.position.z to
	# tick_launch_watch every physics frame, so the recovery happens through the live wiring. We wait
	# the settle time plus a margin, converted to physics frames at the project's 240 Hz tick.
	var settle_frames: int = int((TableConfig.LAUNCH_SETTLE_TIME_S + 1.0) * 240.0)
	await wait_physics_frames(settle_frames)

	# RECOVERY: the plunger is re-armed for the SAME ball so the player can pull again (no dead state).
	assert_true(
		plunger.is_armed(),
		"after a failed (too-weak) launch the plunger must RE-ARM (no soft-lock) - QA B2"
	)
	# Back to READY_TO_LAUNCH, recovered, not stuck in LAUNCHING or BALL_IN_PLAY.
	assert_eq(
		game_flow.current_state(),
		game_flow.State.READY_TO_LAUNCH,
		"a failed launch must recover to READY_TO_LAUNCH on the live tree"
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
